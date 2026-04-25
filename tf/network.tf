# ---------- VPC ----------
#
# Dedicated VPC so firewall rules don't leak onto other workloads in the project.

resource "google_compute_network" "agent" {
  name                    = "${var.vm_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "agent" {
  name                     = "${var.vm_name}-subnet"
  ip_cidr_range            = "10.10.0.0/24"
  region                   = var.region
  network                  = google_compute_network.agent.id
  private_ip_google_access = true
}

# ---------- Firewall rules ----------
#
# Default posture: DENY all ingress except what we explicitly allow.
# GCP VPCs have an implicit allow-egress and an implicit deny-ingress;
# the rules below only ADD allowances.

# Allow SSH from Google's IAP range, as a Tailscale fallback.
# IAP is authenticated via your Google identity, not the public internet.
resource "google_compute_firewall" "iap_ssh" {
  count = var.allow_iap_ssh ? 1 : 0

  name    = "${var.vm_name}-allow-iap-ssh"
  network = google_compute_network.agent.name

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP source range for SSH tunneling.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.vm_name]
}

# Explicit, low-priority deny for all other inbound.
# (Redundant with the implicit deny, but documents intent.)
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "${var.vm_name}-deny-all-ingress"
  network = google_compute_network.agent.name

  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.vm_name]
}
