module "cloud_dns" {
  source          = "../modules/dns"
  domain_name     = var.domain_name
}
