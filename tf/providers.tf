provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all supported resources.
  default_labels = {
    managed_by = "terraform"
    stack      = "agent-vm"
    owner      = var.owner_label
  }
}

provider "random" {}
provider "cloudinit" {}
