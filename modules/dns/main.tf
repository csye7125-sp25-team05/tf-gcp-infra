resource "google_project" "dns_project" {
  name            = "csye7125-dns"
  project_id      = "csye7125-dns-${substr(random_uuid.project_id.result, 0, 8)}"
  folder_id       = google_folder.project.name
}

resource "google_project_service" "dns_api" {
  project  = google_project.dns_project.project_id
  service  = "dns.googleapis.com"
}

resource "google_dns_managed_zone" "primary" {
  project     = google_project.dns_project.project_id
  name        = "primary-zone"
  dns_name    = "${var.domain_name}."
  description = "Primary DNS zone for ${var.domain_name}"

  depends_on = [google_project_service.dns_api]
}

resource "google_project_iam_member" "dns_admin" {
  project = google_project.dns_project.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}
