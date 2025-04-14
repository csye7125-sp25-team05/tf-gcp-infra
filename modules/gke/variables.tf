variable "organization_id" {
  description = "The id of the organization"
  type        = string
}

variable "zones" {
  type    = list(string)
  default = ["us-east1-a", "us-east1-b", "us-east1-c"]
}

variable "env" {
  description = "The environment"
  type        = string
}

variable "project_id" {
  type        = string
  description = "The ID of the existing GCP project"
}

variable "billing_account" {
  description = "The billing account"
  type        = string
}

variable "ssh_key_path" {
  description = "The ssh key"
  type        = string
}

variable "cidr_block" {
  type = string
}

variable "k8s_pod_range" {
  type = string
}

variable "k8s_service_range" {
  type = string
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token for cloning the repository"
  sensitive   = true
  default     = ""
}

variable "ssh_username" {
  type = string
}

variable "region" {
  type = string
}

variable "master_ipv4_cidr_block" {
  type = string
}

variable "jenkins_cidr_block" {
  type = string
}

variable "min_node_count" {
  type = number
}

variable "max_node_count" {
  type = number
}

variable "node_machine_type" {
  type = string
}

variable "ssh_private_key" {
  type = string
}

variable "project_no" {
  description = "The numeric identifier of the project"
  type        = string
  default     = "567458964636"
}

variable "local_ip" {
  type        = string
  description = "Your local machine's public IP for GKE control plane access"
  default     = "0.0.0.0/0" # Default is open to all (not recommended for production)
}

variable "istio_namespace" {
  type        = string
  description = "Name of the Istio system namespace"
  default     = "istio-system"
}

variable "cert_manager_namespace" {
  type        = string
  description = "Name of the Cert-Manager namespace"
  default     = "cert-manager"
}

variable "api_domain_name" {
  type        = string
  description = "The name of the Domain"
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = "shahharsh8563@cyse7125-sp25-05.rocks"
}

variable "app_namespace" {
  default = "api-server"
}

variable "dns_zone_name" {
  default     = "dev-gcp-zone"
  type        = string
  description = "The DNS zone name for the API domain"
}

variable "hosted_zone_name" {
  default = "demo-cyse7125-sp25-05-zone"
}