# ---------- API enablement ----------
#
# Enabling APIs is idempotent but takes a minute on first apply.
# disable_on_destroy = false prevents destroying the APIs on `terraform destroy`,
# which would break other things in the project.

locals {
  required_apis = [
    "compute.googleapis.com",
    "iap.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false
}

# ---------- Service account for the VM ----------

resource "google_service_account" "agent_vm" {
  account_id   = "${var.vm_name}-sa"
  display_name = "Service account for ${var.vm_name}"
  description  = "Attached to the agent VM. Kept minimal; grants expanded via explicit role bindings below."

  depends_on = [google_project_service.apis]
}

# Minimum scopes the VM needs:
#  - Write logs and metrics to Cloud Logging/Monitoring (for ops visibility)
#  - Write to the backup bucket (granted on the bucket resource, not here)
#  - Pull secrets from Secret Manager if you later store provider keys there

resource "google_project_iam_member" "logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.agent_vm.email}"
}

resource "google_project_iam_member" "metrics_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.agent_vm.email}"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.agent_vm.email}"
}
