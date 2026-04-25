# Off-VM backup destination. Daily pg_dump / qdrant snapshots / n8n exports
# get synced here by the backup.sh cron on the VM.

resource "google_storage_bucket" "backups" {
  name     = "${var.project_id}-agent-backups-${var.backup_bucket_suffix}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 60
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 14
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  force_destroy = false

  depends_on = [google_project_service.apis]
}

# Let the VM's service account read and write its own backup bucket.
resource "google_storage_bucket_iam_member" "vm_backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.agent_vm.email}"
}
