variable "domain_name" {
  description = "Base domain name for DNS configuration"
  type        = string
  default     = "yourdomain.com"
}

variable "dns_project_id" {
  description = "ID for the DNS project"
  type        = string
  default     = "csye7125-dns"
}
