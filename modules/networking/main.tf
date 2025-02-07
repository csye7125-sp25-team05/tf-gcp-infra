resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  project                 = var.project_id
  auto_create_subnetworks = "false"


#   depends_on = [
#     google_project_service.services["compute"],
#     google_project_service.services["container"],
#     google_org_policy_policy.disable_default_network
#   ]
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

#   depends_on = [
#     google_project_service.services["compute"]
#   ]
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