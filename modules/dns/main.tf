# Provider configuration
provider "google" {
  project         = "csye7125-dns-449821"
  region          = "us-east1"
  billing_project = "csye7125-dns-449821"
}

# Enable Cloud DNS API
resource "google_project_service" "dns_api" {
  project = "csye7125-dns-449821"
  service = "dns.googleapis.com"
}

# Create a DNS zone
resource "google_dns_managed_zone" "dev_zone" {
  name        = "dev-gcp-zone"
  dns_name    = "dev.gcp.cyse7125-sp25-05.rocks."
  description = "Managed zone for dev subdomain"
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_dns_managed_zone" "prd_zone" {
  name        = "prd-gcp-zone"
  dns_name    = "prd.gcp.cyse7125-sp25-05.rocks."
  description = "Managed zone for prd subdomain"
  lifecycle {
    prevent_destroy = true
  }
}

# Output the name servers
output "dev_name_servers" {
  value = google_dns_managed_zone.dev_zone.name_servers
}

output "prd_name_servers" {
  value = google_dns_managed_zone.prd_zone.name_servers
}

