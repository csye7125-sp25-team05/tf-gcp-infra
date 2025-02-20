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
    ports    = ["22"]
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

  metadata_startup_script = file("${path.module}/init_script.sh")

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

  node_config {
    service_account = google_service_account.gke_sa.email
    disk_type       = "pd-standard"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

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

resource "google_container_node_pool" "primary_preemptible_nodes" {
  project        = var.project_id
  name           = "my-node-pool"
  location       = var.region
  cluster        = google_container_cluster.my_cluster.name
  node_locations = var.zones
  node_count     = 1
  autoscaling {

    total_min_node_count = var.min_node_count
    total_max_node_count = var.max_node_count
    # location_policy = "BALANCED"
  }

  node_config {
    machine_type = var.node_machine_type
    image_type   = "COS_CONTAINERD"
    disk_type    = "pd-standard"
    labels = {
      team = "gke"
    }
    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
