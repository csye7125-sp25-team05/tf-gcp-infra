output "vpc_network_id" {
  value = google_compute_network.vpc_network.id
}
output "public_subnet_id" {
  value = google_compute_subnetwork.public_subnet.id
}
output "private_subnet_id" {
  value = google_compute_subnetwork.private_subnet.id
}
