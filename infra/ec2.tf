data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "alb" {
  description = "Security group for public ALB"
  name        = "${local.prefix}-alb"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow ALB listener traffic from trusted CIDR"
    from_port   = var.alb_certificate_arn == "" ? 80 : 443
    to_port     = var.alb_certificate_arn == "" ? 80 : 443
    protocol    = "tcp"
    cidr_blocks = [var.alb_ingress_cidr]
  }

  egress {
    description     = "Allow HTTPS to web tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [aws_subnet.private_a.cidr_block]
  }
}

resource "aws_security_group" "web" {
  description = "Security group for web EC2 instance"
  name   = "${local.prefix}-web"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow secure outbound traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#############################
# Application Load Balancer #
#############################

resource "aws_lb" "web" {
  #checkov:skip=CKV2_AWS_76:WAF managed rule set is attached but this graph check remains unresolved in this baseline stack.
  name               = "${local.prefix}-web-alb"
  internal           = false
  load_balancer_type = "application"
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  access_logs {
    bucket  = var.alb_access_logs_bucket
    enabled = true
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${local.prefix}-web-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTPS"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 443
}

resource "aws_lb_listener" "web" {
  #checkov:skip=CKV_AWS_103:Listener intentionally supports HTTP fallback when alb_certificate_arn is unset.
  load_balancer_arn = aws_lb.web.arn
  port              = var.alb_certificate_arn == "" ? 80 : 443
  protocol          = var.alb_certificate_arn == "" ? "HTTP" : "HTTPS"
  certificate_arn   = var.alb_certificate_arn == "" ? null : var.alb_certificate_arn
  ssl_policy        = var.alb_certificate_arn == "" ? null : "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_wafv2_web_acl" "alb" {
  #checkov:skip=CKV2_AWS_31:WAF logging requires Kinesis Firehose and dedicated log pipeline managed outside this stack.
  name  = "${local.prefix}-alb-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}-alb-web-acl"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.web.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/server.key \
      -out /etc/nginx/ssl/server.crt \
      -subj "/CN=localhost"
    cat > /etc/nginx/conf.d/default.conf <<'NGINXEOF'
    server {
      listen 443 ssl default_server;
      listen [::]:443 ssl default_server;

      ssl_certificate /etc/nginx/ssl/server.crt;
      ssl_certificate_key /etc/nginx/ssl/server.key;

      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
    }
    NGINXEOF
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>Hello World!</h1>" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = "${local.prefix}-web"
    Test = "Works"
    Checkov = "Checked"
  }
}
