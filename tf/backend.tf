# Remote state in GCS.
#
# The bucket itself must exist BEFORE `terraform init` runs.
# Run bootstrap/00-create-state-bucket.sh once to create it.
#
# Edit the `bucket` value below to match the bucket name you created
# (it must be globally unique across all of GCS).

terraform {
  backend "gcs" {
    bucket = "bugsy-ai-tfstate-agent"
    prefix = "agent-vm"
  }
}
