# Configure the gcp Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~>5.0"
    }
  }
}

provider "google" {
  region          = "us-east1"
  project         = "csye7125-project-dev"
  billing_project = "csye7125-project-dev"
}