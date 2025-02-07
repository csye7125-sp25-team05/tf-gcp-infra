# Add to existing IAM configuration
resource "google_project_iam_member" "dns_reader" {
  project = google_project.kubernetes.project_id
  role    = "roles/dns.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}
