# variable "project_name" {
#   type        = string
#   description = "The name of the project"
# }

variable "organization_id" {
  type        = string
  description = "The ID of the organization"
}

variable "project_id" {
  type        = string
  description = "The ID of the existing GCP project"
}

variable "billing_account" {
  type        = string
  description = "The billing account ID"
}

variable "zones" {
  type    = list(string)
  default = ["us-east1-a", "us-east1-b", "us-east1-c"]
}

variable "region" {
  type        = string
  description = "The GCP region for resource deployment"
}

variable "cidr_block" {
  type        = string
  description = "The CIDR block for the VPC network"
}

variable "k8s_pod_range" {
  type        = string
  description = "The CIDR range for Kubernetes pods"
}

variable "k8s_service_range" {
  type        = string
  description = "The CIDR range for Kubernetes services"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token for cloning the repository"
  sensitive   = true
}

variable "ssh_username" {
  type        = string
  description = "The SSH username for the bastion host"
}

variable "ssh_key_path" {
  type        = string
  description = "The path to the SSH public key file"
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The CIDR block for the Kubernetes master nodes"
}

variable "jenkins_cidr_block" {
  type        = string
  description = "The CIDR block for Jenkins server access"
}

variable "min_node_count" {
  type        = number
  description = "The minimum number of nodes in the GKE cluster"
}

variable "max_node_count" {
  type        = number
  description = "The maximum number of nodes in the GKE cluster"
}

variable "node_machine_type" {
  type        = string
  description = "The machine type for GKE nodes"
}

variable "ssh_private_key" {
  type        = string
  description = "The path to the SSH private key file"
}

variable "env" {
  type        = string
  description = "The environment (e.g., dev, prod)"
}

variable "project_no" {
  description = "The numeric identifier of the project"
  type        = string
  default     = "567458964636"
}

variable "local_ip" {
  type        = string
  description = "Your local machine's public IP for GKE control plane access"
  default     = "0.0.0.0/0"  # Default is open to all (not recommended for production)
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