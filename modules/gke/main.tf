data "google_billing_account" "acct" {
  billing_account = var.billing_account
  open            = true
}

# resource "google_project" "kubernetes" {
#   name            = "${var.project_name}"
#   project_id      = "proj-csye7125-dns-feada260"
#   folder_id       = google_folder.dev-env.id
#   billing_account = data.google_billing_account.acct.billing_account
# }

variable "service_names" {
  type = map(string)
  default = {
    "iam"                  = "iam.googleapis.com"
    "cloud-billing"        = "cloudbilling.googleapis.com"
    "compute"              = "compute.googleapis.com"
    "container"            = "container.googleapis.com"
    "dns"                  = "dns.googleapis.com"
    "serviceusage"         = "serviceusage.googleapis.com"
    "vpc"                  = "vpcaccess.googleapis.com"
    "cloudresourcemanager" = "cloudresourcemanager.googleapis.com"
  }
}

# Create Google project services using a for_each loop
resource "google_project_service" "services" {
  for_each = var.service_names

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# resource "google_org_policy_policy" "disable_default_network" {
#   name   = "projects/${var.project_id}/policies/compute.skipDefaultNetworkCreation"
#   parent = "projects/${var.project_id}"

#   spec {
#     rules {
#       enforce = "TRUE"
#     }
#   }
# }

resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  project                 = var.project_id
  auto_create_subnetworks = "false"


  depends_on = [
    google_project_service.services["compute"],
    google_project_service.services["container"]
  ]
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "public-subnet"
  ip_cidr_range = cidrsubnet(var.cidr_block, 4, 1)
  network       = google_compute_network.vpc_network.id
  project       = var.project_id
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet"
  ip_cidr_range            = cidrsubnet(var.cidr_block, 4, 2)
  private_ip_google_access = true
  network                  = google_compute_network.vpc_network.id
  project                  = var.project_id

  secondary_ip_range {
    range_name    = "k8s-pod-range"
    ip_cidr_range = var.k8s_pod_range
  }
  secondary_ip_range {
    range_name    = "k8s-service-range"
    ip_cidr_range = var.k8s_service_range
  }
}

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "router"
  region  = var.region
  network = google_compute_network.vpc_network.name
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = "nat"
  router  = google_compute_router.router.name
  region  = var.region

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  nat_ip_allocate_option             = "MANUAL_ONLY"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  nat_ips = [google_compute_address.nat.self_link]
}

resource "google_compute_address" "nat" {
  project      = var.project_id
  name         = "nat"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [
    google_project_service.services["compute"]
  ]
}


resource "google_compute_firewall" "instance_firewall" {
  project   = var.project_id
  name      = "instance-firewall"
  network   = google_compute_network.vpc_network.name
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_service_account" "bastion_host_sa" {
  project      = var.project_id
  account_id   = "bastion-host-sa"
  display_name = "My Compute Instance Service Account"
}

resource "google_compute_instance" "bastion_host" {
  project                   = var.project_id
  name                      = "bastion-host"
  machine_type              = "e2-medium"
  zone                      = "us-east1-b"
  allow_stopping_for_update = true

  tags = ["web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      labels = {
        my_label = "value"
      }
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.self_link
    access_config {
      // To allow external IP access
    }
  }

  service_account {
    email  = google_service_account.bastion_host_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${file(var.ssh_key_path)}"
  }

  depends_on = [
    google_compute_subnetwork.private_subnet,
  ]

  metadata_startup_script = <<-EOT
  #!/bin/bash
  exec > /var/log/startup-script.log 2>&1  # Redirect logs to a file for debugging

  echo "********* Setup kubectl *********"
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl gpg kubectl

  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt-get update
  sudo apt-get install -y kubectl

  echo "********* kubectl Installation Completed *********"
EOT


}

resource "google_service_account" "gke_sa" {
  project      = var.project_id
  account_id   = format("gke-sa")
  display_name = "gke-sa"
}

resource "google_container_cluster" "my_cluster" {
  project                  = var.project_id
  name                     = "my-gke-cluster"
  location                 = var.region
  network                  = google_compute_network.vpc_network.self_link
  subnetwork               = google_compute_subnetwork.private_subnet.self_link
  remove_default_node_pool = true
  initial_node_count       = 1

  min_master_version = "1.30.9"

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8s-service-range"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${google_compute_instance.bastion_host.network_interface[0].access_config[0].nat_ip}/32"
      display_name = "Bastion Host access to cluster"
    }
    cidr_blocks {
      cidr_block   = var.jenkins_cidr_block
      display_name = "Jenkins Server access to cluster"
    }
  }

  deletion_protection = false
}

resource "google_container_node_pool" "node-pool-1" {
  name           = "node-pool-1"
  location       = var.region
  cluster        = google_container_cluster.my_cluster.name
  node_count     = 1
  node_locations = ["us-east1-b"]

  node_config {
    service_account = google_service_account.gke_sa.email
    image_type      = "COS_CONTAINERD"
    machine_type    = "e2-medium"
    disk_type       = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

resource "google_container_node_pool" "node-pool-2" {
  name           = "node-pool-2"
  location       = var.region
  cluster        = google_container_cluster.my_cluster.name
  node_count     = 1
  node_locations = ["us-east1-c"]

  node_config {
    service_account = google_service_account.gke_sa.email
    image_type      = "COS_CONTAINERD"
    machine_type    = "e2-medium"
    disk_type       = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

resource "google_container_node_pool" "node-pool-3" {
  name           = "node-pool-3"
  location       = var.region
  cluster        = google_container_cluster.my_cluster.name
  node_count     = 1
  node_locations = ["us-east1-d"]

  node_config {
    service_account = google_service_account.gke_sa.email
    image_type      = "COS_CONTAINERD"
    machine_type    = "e2-medium"
    disk_type       = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

// Fetch existing GKE KeyRing (if it exists)
data "google_kms_key_ring" "existing_gke_key_ring" {
  name     = "gke-key-ring"
  location = var.region
  project  = var.project_id
}

// Create GKE KeyRing ONLY if it does not exist
resource "google_kms_key_ring" "gke_key_ring" {
  count    = length(data.google_kms_key_ring.existing_gke_key_ring.id) > 0 ? 0 : 1
  name     = "gke-key-ring"
  location = var.region
  project  = var.project_id
}

// Determine the correct KeyRing ID
locals {
  gke_key_ring_id = length(data.google_kms_key_ring.existing_gke_key_ring.id) > 0 ? data.google_kms_key_ring.existing_gke_key_ring.id : google_kms_key_ring.gke_key_ring[0].id
}

// Fetch existing GKE Crypto Key (if it exists)
data "google_kms_crypto_key" "existing_gke_crypto_key" {
  name     = "gke-encryption-key"
  key_ring = local.gke_key_ring_id
}

// Create GKE Crypto Key ONLY if it does not exist
resource "google_kms_crypto_key" "gke_crypto_key" {
  count           = length(data.google_kms_crypto_key.existing_gke_crypto_key.id) > 0 ? 0 : 1
  name            = "gke-encryption-key"
  key_ring        = local.gke_key_ring_id
  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = false
  }
}

// ====================================================================

// Fetch existing SOPS KeyRing (if it exists)
data "google_kms_key_ring" "existing_sops_key_ring" {
  name     = "sops-key-ring"
  location = var.region
  project  = var.project_id
}

// Create SOPS KeyRing ONLY if it does not exist
resource "google_kms_key_ring" "sops_key_ring" {
  count    = length(data.google_kms_key_ring.existing_sops_key_ring.id) > 0 ? 0 : 1
  name     = "sops-key-ring"
  location = var.region
  project  = var.project_id
}

// Determine the correct KeyRing ID
locals {
  sops_key_ring_id = length(data.google_kms_key_ring.existing_sops_key_ring.id) > 0 ? data.google_kms_key_ring.existing_sops_key_ring.id : google_kms_key_ring.sops_key_ring[0].id
}

// Fetch existing SOPS Crypto Key (if it exists)
data "google_kms_crypto_key" "existing_sops_crypto_key" {
  name     = "sops-encryption-key"
  key_ring = local.sops_key_ring_id
}

// Create SOPS Crypto Key ONLY if it does not exist
resource "google_kms_crypto_key" "sops_crypto_key" {
  count           = length(data.google_kms_crypto_key.existing_sops_crypto_key.id) > 0 ? 0 : 1
  name            = "sops-encryption-key"
  key_ring        = local.sops_key_ring_id
  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = false
  }
}

# Service Account for Cloud Storage
resource "google_service_account" "gcs_sa" {
  account_id   = "gcs-access-sa"
  display_name = "Service Account for GCS Access"
}

# IAM Binding for GCS Access
resource "google_project_iam_member" "gcs_sa_binding" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.gcs_sa.email}"
}

# Workload Identity Binding
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.gcs_sa.name
  role               = "roles/iam.workloadIdentityUser"


  # members = [
  #   "serviceAccount:${var.project_id}.svc.id.goog[backup-operator/backup-operator-controller]"
  # ]
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[api-server/api-server-sa]"
  ]
}





































# # resource "google_storage_bucket_iam_member" "gke_sa_storage_admin" {
# #   bucket = "csye7125-sp25-05"
# #   role   = "roles/storage.objectAdmin"
# #   member = "serviceAccount:${google_service_account.gke_sa.email}"
# # }

# # Kubernetes provider configuration
# data "google_client_config" "default" {}

# provider "kubernetes" {
#   host                   = "https://${google_container_cluster.my_cluster.endpoint}"
#   token                  = data.google_client_config.default.access_token
#   cluster_ca_certificate = base64decode(google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
# }

# # Create namespace for your application
# resource "kubernetes_namespace" "app_namespace" {
#   metadata {
#     name = "api-server"
#   }
#   depends_on = [
#     google_container_node_pool.node-pool-1,
#     google_container_cluster.my_cluster
#   ]
# }

# resource "kubernetes_service_account" "pdf_uploader_sa" {
#   metadata {
#     name      = "pdf-uploader-sa"
#     namespace = kubernetes_namespace.app_namespace.metadata[0].name
#     annotations = {
#       "iam.gke.io/gcp-service-account" = google_service_account.gke_sa.email
#     }
#   }
#   depends_on = [
#     kubernetes_namespace.app_namespace
#   ]
# }

# resource "google_storage_bucket_iam_member" "gke_sa_storage_admin" {
#   bucket = "csye7125-sp25-05"
#   role   = "roles/storage.objectAdmin"
#   member = "principal://iam.googleapis.com/projects/${var.project_no}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/${kubernetes_namespace.app_namespace.metadata[0].name}/sa/${kubernetes_service_account.pdf_uploader_sa.metadata[0].name}"
# }
