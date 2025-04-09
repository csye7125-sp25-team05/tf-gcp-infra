data "google_billing_account" "acct" {
  billing_account = var.billing_account
  open            = true
}

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

  echo "********* Install Istio *********"
  curl -L https://istio.io/downloadIstio | sh -
  cd istio-*
  export PATH="$PWD/bin:$PATH"
  echo 'export PATH="$PWD/bin:$PATH"' >> ~/.bashrc
  istioctl version

  echo "********* Install Git and Clone Repository *********"
  sudo apt-get install -y git
  git clone https://Harshshah2306:${var.github_token}@github.com/Harshshah2306/helm-charts-fork.git
  cd helm-charts-fork

  echo "********* Install Helm *********"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm version

  echo "********* Apply Istio and Helm Configurations *********"
  istioctl install -f custom-profile.yaml
  helm install istio ./

  echo "********* Install Kiali with Helm *********"
  helm repo add kiali https://kiali.org/helm-charts
  helm repo update
  helm install kiali-server kiali/kiali-server \
    --namespace istio-system \
    --set auth.strategy="anonymous" \
    --set deployment.viewOnlyMode=false \
    --set istio_namespace="istio-system" \
    --set external_services.istio.root_namespace="istio-system"

  echo "********* Install Prometheus *********"
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/addons/prometheus.yaml

  echo "********* Install Cert-Manager *********"
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set installCRDs=true

  helm repo add external-dns https://charts.bitnami.com/bitnami
  helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --set provider=google \
  --set google.project=${var.project_id}

  echo "********* Setup Complete *********"
  EOT
}

resource "google_service_account" "gke_sa" {
  project      = var.project_id
  account_id   = format("gke-sa")
  display_name = "gke-sa"
}

# IAM permissions for Google Managed Prometheus
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Additional role that may be needed for full GMP functionality
resource "google_project_iam_member" "monitoring_dashboard_editor" {
  project = var.project_id
  role    = "roles/monitoring.dashboardEditor"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
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
    cidr_blocks {
      cidr_block   = var.local_ip
      display_name = "Local Machine Terraform Access"
    }
  }

  # Enable Cloud Logging
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS", # System logs (e.g., kubelet, container runtime)
      "WORKLOADS"          # Application logs from workloads
    ]
  }

  # Enable Cloud Monitoring
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS" # System metrics (e.g., CPU, memory)
    ]

    # Enable Managed Prometheus for custom metrics
    managed_prometheus {
      enabled = true
    }
  }

  deletion_protection = false

  depends_on = [
    google_project_service.services["logging"],
    google_project_service.services["monitoring"],
    google_project_service.services["container"]
  ]
}

resource "google_container_node_pool" "node-pool-1" {
  name           = "node-pool-1"
  location       = var.region
  cluster        = google_container_cluster.my_cluster.name
  node_count     = 1
  node_locations = ["us-east1-b"]
  project        = var.project_id

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
  project        = var.project_id

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
  project        = var.project_id

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
  project      = var.project_id
}

# IAM Binding for GCS Access
resource "google_project_iam_member" "gcs_sa_binding" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.gcs_sa.email}"
}

# Workload Identity Binding for Monitoring
resource "google_service_account_iam_binding" "monitoring_workload_identity_binding" {
  service_account_id = google_service_account.gke_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[gmp-system/collector]",
    "serviceAccount:${var.project_id}.svc.id.goog[monitoring/prometheus-collector]"
  ]
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

resource "google_project_iam_audit_config" "gke_audit_logs" {
  project = var.project_id
  service = "container.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ" # Logs admin activity reads
  }

  audit_log_config {
    log_type = "DATA_READ" # Logs data read operations
  }

  audit_log_config {
    log_type = "DATA_WRITE" # Logs data write operations
  }

  depends_on = [
    google_project_service.services["container"]
  ]
}

data "google_client_config" "default" {}

resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1,
    google_container_node_pool.node-pool-2,
    google_container_node_pool.node-pool-3
  ]

  create_duration = "30s"
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.my_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
}

# Define the Istio system namespace
resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = var.istio_namespace
  }
  depends_on = [
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1
  ]
}

# Define the Cert-Manager namespace
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.cert_manager_namespace
  }
  depends_on = [
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1
  ]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1
  ]
}

resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = <<EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
      action: replace
      target_label: __metrics_path__
      regex: (.+)
    - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
      action: replace
      regex: (.+):(?:\d+);(\d+)
      replacement: $1:$2
      target_label: __address__
EOF
  }
}

resource "kubernetes_cluster_role" "gmp_operator_role" {
  metadata {
    name = "gmp-operator-cluster-role"
    labels = {
      "app.kubernetes.io/name" = "gmp-operator"
    }
  }
  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["*"]
  }
  depends_on = [
    google_container_cluster.my_cluster
  ]
}

resource "kubernetes_cluster_role_binding" "gmp_operator_binding" {
  metadata {
    name = "gmp-operator-cluster-role-binding"
    labels = {
      "app.kubernetes.io/name" = "gmp-operator"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.gmp_operator_role.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "operator"
    namespace = "gmp-system"
  }
  depends_on = [
    google_container_cluster.my_cluster,
    kubernetes_cluster_role.gmp_operator_role
  ]
}

resource "kubernetes_manifest" "istio_pod_monitor" {
  manifest = {
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitoring"
    metadata = {
      name      = "istio-components"
      namespace = var.istio_namespace
    }
    spec = {
      selector = {
        matchLabels = {
          "istio.io/rev" = "custom"
        }
      }
      endpoints = [
        {
          port     = "http-envoy-prom"
          path     = "/stats/prometheus"
          interval = "30s"
        }
      ]
    }
  }
  depends_on = [
    time_sleep.wait_for_kubernetes,
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1,
    kubernetes_namespace.istio_system
  ]
}

resource "kubernetes_manifest" "cert_manager_pod_monitor" {
  manifest = {
    apiVersion = "monitoring.googleapis.com/v1"
    kind       = "PodMonitoring"
    metadata = {
      name      = "cert-manager"
      namespace = var.cert_manager_namespace
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "cert-manager"
        }
      }
      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
        }
      ]
    }
  }
  depends_on = [
    time_sleep.wait_for_kubernetes,
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1,
    kubernetes_namespace.cert_manager
  ]
}
