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

resource "google_project_iam_member" "bastion_host_cluster_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.bastion_host_sa.email}"
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

  # Set KUBECONFIG to a specific path
  export KUBECONFIG=/root/.kube/config
  export HOME=/root
  mkdir -p /root/.kube

  echo "********* Install gcloud CLI *********"
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
  sudo apt-get update
  sudo apt-get install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin

  echo "********* Configure gcloud *********"
  gcloud config set project ${var.project_id}

  echo "********* Get GKE Cluster Credentials *********"
  gcloud container clusters get-credentials my-gke-cluster --region=us-east1 --project=${var.project_id}

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


## Cert Manager infra for terraform 

resource "google_service_account" "dns_admin" {
  account_id   = "dns-admin-sa"
  display_name = "DNS Admin Service Account"
  project      = var.project_id
}

# Bind the dns.admin role to the service account
resource "google_project_iam_member" "dns_admin_binding" {
  project    = var.project_id
  role       = "roles/dns.admin"
  member     = "serviceAccount:${google_service_account.dns_admin.email}"
  depends_on = [google_service_account.dns_admin]
}

provider "kubectl" {
  host                   = "https://${google_container_cluster.my_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.my_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
  }
}

# Ensure the cert-manager namespace exists explicitly
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
  depends_on = [
    google_container_cluster.my_cluster,
    google_container_node_pool.node-pool-1,
    google_container_node_pool.node-pool-2,
    google_container_node_pool.node-pool-3,
    time_sleep.wait_for_kubernetes
  ]
}

# Create the Kubernetes service account before the Helm release
resource "kubernetes_service_account" "cert_manager_sa" {
  metadata {
    name      = "cert-manager"
    namespace = "cert-manager"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.cert_manager_dns_sa.email
    }
  }
  depends_on = [
    kubernetes_namespace.cert_manager
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = false # Set to false since we manage the namespace explicitly
  version          = "v1.13.2"
  timeout          = 600 # Increase timeout to 10 minutes

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "false" # We create the service account ourselves
  }

  set {
    name  = "serviceAccount.name"
    value = "cert-manager"
  }

  depends_on = [
    google_container_cluster.my_cluster,
    kubernetes_service_account.cert_manager_sa, # Depend on the service account
    kubernetes_namespace.cert_manager           # Depend on the namespace
  ]
}

# Create DNS Solver service account
resource "google_service_account" "cert_manager_dns_sa" {
  account_id   = "cert-manager-dns-solver"
  display_name = "Service Account for cert-manager DNS-01 challenges"
  project      = var.project_id
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager_dns_sa.email}"
}

# Set up the IAM binding for Workload Identity
resource "google_service_account_iam_binding" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager_dns_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
  ]
}

# resource "kubectl_manifest" "cluster_issuer_prod" {
#   yaml_body = <<YAML
# apiVersion: cert-manager.io/v1
# kind: ClusterIssuer
# metadata:
#   name: letsencrypt-prod
# spec:
#   acme:
#     server: https://acme-v02.api.letsencrypt.org/directory
#     email: ${var.cert_manager_email}
#     privateKeySecretRef:
#       name: letsencrypt-prod-account-key
#     solvers:
#     - dns01:
#         cloudDNS:
#           project: ${var.project_id}
#           hostedZoneName: ${var.dns_zone_name}
# YAML

#   depends_on = [
#     helm_release.cert_manager,
#     kubernetes_service_account.cert_manager_sa,
#     google_service_account_iam_binding.cert_manager_workload_identity
#   ]
# }

resource "kubectl_manifest" "prometheus_rule_cert_manager" {
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cert-manager-alerts
  namespace: monitoring
spec:
  groups:
  - name: cert-manager.rules
    rules:
    - alert: CertificateExpiringSoon
      expr: certmanager_certificate_expiration_timestamp_seconds < (time() + 604800)
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Certificate {{ $labels.name }} is expiring soon"
        description: "{{ $labels.name }} in namespace {{ $labels.namespace }} will expire in less than 7 days."
    - alert: CertificateIssuanceFailed
      expr: certmanager_certificate_ready_status{status="False"} == 1
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "Certificate {{ $labels.name }} issuance failed"
        description: "{{ $labels.name }} in namespace {{ $labels.namespace }} has not been issued successfully."
YAML
  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_operator_crds
  ]
}

resource "kubectl_manifest" "cluster_issuer_staging" {
  yaml_body  = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${var.cert_manager_email}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - dns01:
        cloudDNS:
          project: ${var.project_id}
          hostedZoneName: ${var.dns_zone_name}
YAML
  depends_on = [helm_release.cert_manager]
}

# Install NGINX Ingress Controller
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.7.1"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  depends_on = [
    google_container_cluster.my_cluster,
    time_sleep.wait_for_kubernetes
  ]
}

# Wait until the ingress controller has an IP address
resource "time_sleep" "wait_for_ingress_ip" {
  depends_on      = [helm_release.ingress_nginx]
  create_duration = "45s"
}

# Get the IP address of the NGINX Ingress Controller
data "kubernetes_service" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.wait_for_ingress_ip
  ]
}

# Deploy application
resource "helm_release" "application" {
  name  = "api-server"
  chart = "${path.module}/charts/api-server" # Local path to your Helm chart director

  depends_on = [
    google_container_cluster.my_cluster,
    helm_release.cert_manager,
    kubectl_manifest.cluster_issuer_staging,
    helm_release.istio_base,
    helm_release.istio_discovery,
    helm_release.istio_gateway,
    helm_release.eggress_gateways,
    helm_release.ingress_gateways
  ]
}

# Create Certificate resources
resource "kubectl_manifest" "api_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-server-tls
  namespace: ${var.app_namespace}
spec:
  secretName: api-server-tls-secret
  duration: 2160h
  renewBefore: 360h
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  dnsNames:
  - ${var.api_domain_name}
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
    group: cert-manager.io
YAML

  depends_on = [
    helm_release.application,
    kubectl_manifest.cluster_issuer_staging,
    helm_release.application
  ]
}

# Create Ingress resources
resource "kubectl_manifest" "api_ingress" {
  yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-server-ingress
  namespace: ${var.app_namespace}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: 50m
spec:
  tls:
  - hosts:
    - ${var.api_domain_name}
    secretName: api-server-tls-secret
  rules:
  - host: ${var.api_domain_name}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
YAML

  depends_on = [
    kubectl_manifest.api_certificate,
    helm_release.ingress_nginx,
    helm_release.application
  ]
}

########


resource "google_dns_record_set" "api_domain" {
  name         = "${var.api_domain_name}."
  managed_zone = var.dns_zone_name
  type         = "A"
  ttl          = 300

  rrdatas = [data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip]
  project = var.project_id
}

resource "helm_release" "prometheus_operator_crds" {
  name             = "prometheus-operator-crds"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-operator-crds"
  namespace        = "monitoring"
  version          = "0.1.1" # Check for the latest version
  create_namespace = true

  depends_on = [
    google_container_cluster.my_cluster,
    kubernetes_namespace.monitoring
  ]
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  chart      = "${path.module}/charts/base" # Path to the base chart in your local directory
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  depends_on = [kubernetes_namespace.istio_system]
}

# Apply the istio-discovery (istiod) chart
resource "helm_release" "istio_discovery" {
  name       = "istiod"
  chart      = "${path.module}/charts/istio-discovery" # Path to the istio-discovery chart
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  depends_on = [helm_release.istio_base]

  timeout = 600

  set {
    name  = "global.hub"
    value = "gcr.io/istio-release"
  }

  # Reduce resource requests for istiod
  set {
    name  = "pilot.resources.requests.cpu"
    value = "200m" # Default is 500m
  }
  set {
    name  = "pilot.resources.requests.memory"
    value = "1024Mi" # Default is 2048Mi
  }
}

# Apply the gateway chart (optional, for ingress)
resource "helm_release" "istio_gateway" {
  name       = "istio-gateway"
  chart      = "${path.module}/charts/gateway" # Path to the gateway chart
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  depends_on = [helm_release.istio_discovery]
}

# Apply the gateways chart (optional, for additional gateway configurations)
resource "helm_release" "eggress_gateways" {
  name       = "eggress-gateways"
  chart      = "${path.module}/charts/gateways/istio-egress" # Path to the gateways chart
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  depends_on = [helm_release.istio_gateway]
}
resource "helm_release" "ingress_gateways" {
  name       = "istio-gateways"
  chart      = "${path.module}/charts/gateways/istio-ingress" # Path to the gateways chart
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  depends_on = [helm_release.istio_gateway]
}


