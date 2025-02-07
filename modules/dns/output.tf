output "name_servers" {
  value       = module.cloud_dns.name_servers
  description = "DNS name servers for Route53 configuration"
}
