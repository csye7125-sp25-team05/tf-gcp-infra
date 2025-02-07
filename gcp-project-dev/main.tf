module "gke" {
  source = "../modules/gke"

  project_id             = var.project_id
  organization_id        = var.organization_id
  billing_account        = var.billing_account
  region                 = var.region
  cidr_block             = var.cidr_block
  k8s_pod_range          = var.k8s_pod_range
  k8s_service_range      = var.k8s_service_range
  ssh_username           = var.ssh_username
  ssh_key_path           = var.ssh_key_path
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
  jenkins_cidr_block     = var.jenkins_cidr_block
  min_node_count         = var.min_node_count
  max_node_count         = var.max_node_count
  node_machine_type      = var.node_machine_type
  ssh_private_key        = var.ssh_private_key
  env                    = var.env
}