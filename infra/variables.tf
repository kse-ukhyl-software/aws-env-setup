variable "prefix" {
  description = "Prefix for resources in AWS"
  default     = "ccs"
}

variable "region" {
  default = "eu-central-1"
}

variable "project" {
  description = "Project name for tagging resources"
  default     = "ci-cd-security-course"
}

variable "contact" {
  description = "Contact name for tagging resources"
  default     = "kostia.shiian@gmail.com"
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
}

variable "alb_ingress_cidr" {
  description = "CIDR range allowed to access the public ALB over HTTPS"
  type        = string
  default     = "0.0.0.0/0"
}

variable "alb_access_logs_bucket" {
  description = "Existing S3 bucket name for ALB access logs"
  type        = string
}
