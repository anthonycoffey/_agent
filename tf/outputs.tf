output "vm_name" {
  value       = google_compute_instance.agent.name
  description = "Instance name."
}

output "vm_zone" {
  value       = google_compute_instance.agent.zone
  description = "Instance zone."
}

output "vm_internal_ip" {
  value       = google_compute_instance.agent.network_interface[0].network_ip
  description = "Internal RFC1918 IP. Not directly reachable; use Tailscale or IAP."
}

output "tailscale_hostname" {
  value       = "${var.tailscale_hostname}.<your-tailnet>.ts.net"
  description = "Once the VM joins your Tailnet, use your actual tailnet name in place of <your-tailnet>."
}

output "ssh_via_iap" {
  value       = "gcloud compute ssh ${google_compute_instance.agent.name} --zone=${var.zone} --tunnel-through-iap --project=${var.project_id}"
  description = "Fallback SSH command over IAP."
}

output "ssh_via_tailscale" {
  value       = "ssh $(whoami)@${var.tailscale_hostname}"
  description = "Primary SSH path once Tailscale is up on both ends."
}

output "backup_bucket" {
  value       = google_storage_bucket.backups.url
  description = "GCS bucket that receives off-VM backups."
}

output "service_account_email" {
  value       = google_service_account.agent_vm.email
  description = "Service account attached to the VM."
}

output "first_boot_hint" {
  value = <<EOT

=== Next steps ===

1. Wait ~3-5 minutes for cloud-init to finish (OS updates + Docker +
   Tailscale + initial compose pull).

2. Approve the node on your Tailnet admin page if you haven't already.
   https://login.tailscale.com/admin/machines

3. SSH in:
     ssh $(whoami)@${var.tailscale_hostname}
   or fall back to IAP:
     gcloud compute ssh ${google_compute_instance.agent.name} --zone=${var.zone} --tunnel-through-iap --project=${var.project_id}

4. Check the welcome MOTD. Then:
     cd ~/agent
     docker compose ps
     docker compose logs -f

5. Open the chat UI at https://${var.tailscale_hostname}.<your-tailnet>.ts.net/
   (put your actual tailnet name in the URL).

EOT
  description = "Post-apply checklist."
}
