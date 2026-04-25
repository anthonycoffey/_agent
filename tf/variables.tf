# ---------- GCP ----------

variable "project_id" {
  type        = string
  description = "GCP project ID. Create the project first with `gcloud projects create` if it doesn't exist."
}

variable "region" {
  type        = string
  description = "GCP region."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "GCP zone. Must be inside `region`."
  default     = "us-central1-a"
}

variable "owner_label" {
  type        = string
  description = "Short identifier for the human who owns this stack (used as a resource label)."
  default     = "me"
}

# ---------- VM ----------

variable "vm_name" {
  type        = string
  description = "Name of the Compute Engine instance."
  default     = "agent-vm"
}

variable "machine_type" {
  type        = string
  description = "Machine type. n2-standard-4 is the recommended starter. Bump to n2-standard-8 if you plan to run a local LLM on CPU."
  default     = "n2-standard-4"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB. 200 is comfortable for images + volumes."
  default     = 200
}

variable "boot_disk_type" {
  type        = string
  description = "Boot disk type. pd-balanced is the usual sweet spot."
  default     = "pd-balanced"
  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be one of pd-standard, pd-balanced, pd-ssd."
  }
}

variable "image_family" {
  type        = string
  description = "Ubuntu LTS image family. 24.04 is current LTS through 2029."
  default     = "ubuntu-2404-lts-amd64"
}

variable "image_project" {
  type        = string
  description = "Image host project."
  default     = "ubuntu-os-cloud"
}

# ---------- Tailscale ----------

variable "tailscale_auth_key" {
  type        = string
  description = <<EOT
A reusable (or one-shot) ephemeral pre-auth key from
https://login.tailscale.com/admin/settings/keys

Used only during cloud-init to join the VM to your Tailnet.
Treat this as a secret.
EOT
  sensitive   = true
}

variable "tailscale_hostname" {
  type        = string
  description = "Tailscale MagicDNS hostname to register (no domain suffix)."
  default     = "agent-vm"
}

variable "tailscale_tags" {
  type        = list(string)
  description = "Tailscale ACL tags to apply (e.g. [\"tag:agent\"]). Must be pre-declared in your Tailnet ACL."
  default     = []
}

# ---------- Networking ----------

variable "allow_iap_ssh" {
  type        = bool
  description = "If true, allow SSH from GCP IAP (35.235.240.0/20) as a Tailscale fallback. Recommended: true."
  default     = true
}

# ---------- Backups ----------

variable "enable_snapshot_schedule" {
  type        = bool
  description = "Attach a daily snapshot schedule to the boot disk."
  default     = true
}

variable "snapshot_retention_days" {
  type        = number
  description = "How long to keep automatic disk snapshots."
  default     = 14
}

variable "backup_bucket_suffix" {
  type        = string
  description = <<EOT
Suffix appended to the backup bucket name.
Full name will be "<project_id>-agent-backups-<suffix>".
Bucket names are globally unique, so pick something distinct.
EOT
  default     = "01"
}

# ---------- Agent stack ----------

variable "timezone" {
  type        = string
  description = "IANA timezone for the VM and stack (used by n8n scheduler, logs, cron)."
  default     = "America/Chicago"
}

variable "agent_admin_email" {
  type        = string
  description = "Your email. Informational only (printed in the MOTD)."
  default     = "you@example.com"
}
