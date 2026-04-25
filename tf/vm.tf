# ---------- Generated secrets ----------
#
# These are generated once on first apply and kept in state.
# Terraform state lives in GCS with default encryption + your IAM constraints.
# If that's not enough, switch to Secret Manager later (see README).

resource "random_password" "webui_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "n8n_encryption_key" {
  length  = 64
  special = false
}

resource "random_password" "n8n_jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "langfuse_secret" {
  length  = 64
  special = false
}

resource "random_password" "langfuse_salt" {
  length  = 64
  special = false
}

resource "random_password" "nextauth_secret" {
  length  = 64
  special = false
}

# ---------- cloud-init ----------
#
# IMPORTANT: For GCE user-data, both gzip and base64_encode must be FALSE.
# The cloudinit_config data source's encoding options are designed for AWS EC2,
# which has a different delivery pipeline. GCE's metadata server delivers
# user-data as-is to cloud-init, so we need plain-text YAML.

data "cloudinit_config" "agent_vm" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "agent-vm.yaml"

    content = templatefile("${path.module}/cloud-init/agent-vm.yaml.tftpl", {
      tailscale_auth_key = var.tailscale_auth_key
      tailscale_hostname = var.tailscale_hostname
      tailscale_tags_arg = length(var.tailscale_tags) > 0 ? "--advertise-tags=${join(",", var.tailscale_tags)}" : ""
      timezone           = var.timezone
      admin_email        = var.agent_admin_email

      # Rendered files, base64-encoded to preserve formatting exactly.
      docker_compose_b64 = filebase64("${path.module}/../agent/docker-compose.yml")
      env_template_b64   = filebase64("${path.module}/../agent/env.template")
      backup_script_b64  = filebase64("${path.module}/../agent/backup.sh")
      motd_b64           = filebase64("${path.module}/../agent/motd")

      # Secrets baked into the .env on first boot.
      webui_secret_key   = random_password.webui_secret_key.result
      n8n_encryption_key = random_password.n8n_encryption_key.result
      n8n_jwt_secret     = random_password.n8n_jwt_secret.result
      postgres_password  = random_password.postgres_password.result
      langfuse_secret    = random_password.langfuse_secret.result
      langfuse_salt      = random_password.langfuse_salt.result
      nextauth_secret    = random_password.nextauth_secret.result
    })
  }
}

# ---------- Snapshot schedule (optional) ----------

resource "google_compute_resource_policy" "daily_snapshot" {
  count = var.enable_snapshot_schedule ? 1 : 0

  name   = "${var.vm_name}-daily-snapshot"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "07:00"
      }
    }
    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
    snapshot_properties {
      storage_locations = [var.region]
      labels = {
        auto_snapshot = "true"
        source_vm     = var.vm_name
      }
    }
  }
}

# ---------- Boot disk ----------
#
# Kept as a separate resource (rather than inline on the VM) so we can attach
# the snapshot schedule policy.

resource "google_compute_disk" "boot" {
  name  = "${var.vm_name}-boot"
  type  = var.boot_disk_type
  zone  = var.zone
  size  = var.boot_disk_size_gb
  image = "${var.image_project}/${var.image_family}"

  #resource_policies = var.enable_snapshot_schedule ? [google_compute_resource_policy.daily_snapshot[0].self_link] : []

  depends_on = [google_project_service.apis]
}

# ---------- The instance ----------

resource "google_compute_instance" "agent" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.vm_name]

  boot_disk {
    source      = google_compute_disk.boot.self_link
    auto_delete = false
  }

  network_interface {
    network    = google_compute_network.agent.id
    subnetwork = google_compute_subnetwork.agent.id

    # No access_config block = no external IP. Ingress via Tailscale only.
    # Egress still works via Cloud NAT or direct for Google APIs (since
    # private_ip_google_access = true on the subnet).
  }

  service_account {
    email = google_service_account.agent_vm.email
    # cloud-platform is the broadest scope; narrow via IAM roles instead.
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data      = data.cloudinit_config.agent_vm.rendered
  }

  # This VM is effectively a pet, not cattle. Protect against accidents.
  allow_stopping_for_update = true

  # Note: cloud-init only runs on first boot. If you change the cloud-init
  # template and want it to take effect, force VM replacement with:
  #   terraform apply -replace=google_compute_instance.agent
}

# ---------- Cloud NAT ----------
#
# Gives the VM outbound internet (needed for apt, docker pull, tailscale, etc.)
# without assigning a public IP to it.

resource "google_compute_router" "nat_router" {
  name    = "${var.vm_name}-nat-router"
  region  = var.region
  network = google_compute_network.agent.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.vm_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}
