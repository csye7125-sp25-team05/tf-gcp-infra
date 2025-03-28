variable "organization_id" {
  description = "The id of the organization"
  type        = string

}

# variable "project_name" {
#   description = "The name of the project"
#   type        = string

# }

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