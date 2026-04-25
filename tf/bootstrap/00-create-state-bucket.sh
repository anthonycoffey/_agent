#!/usr/bin/env bash
# One-time bootstrap: create the GCS bucket that holds Terraform state.
#
# Run this ONCE, before `terraform init`. After that, Terraform manages
# everything.

set -euo pipefail

if [ $# -lt 2 ]; then
    cat <<EOF
usage: $0 <project-id> <bucket-name>

example:
    $0 my-gcp-project-123 my-gcp-project-123-tfstate-agent

The bucket name must be globally unique across all of GCS.
A common convention is "<project-id>-tfstate-<stack>".

After running this, update backend.tf with the bucket name and run:
    terraform init
EOF
    exit 1
fi

PROJECT_ID=$1
BUCKET_NAME=$2
LOCATION=${LOCATION:-US}

echo "==> Setting active project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

echo "==> Enabling Cloud Storage API"
gcloud services enable storage.googleapis.com --project="$PROJECT_ID"

echo "==> Creating bucket: gs://$BUCKET_NAME (location: $LOCATION)"
if gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "    bucket already exists, skipping create"
else
    gcloud storage buckets create "gs://$BUCKET_NAME" \
        --project="$PROJECT_ID" \
        --location="$LOCATION" \
        --uniform-bucket-level-access \
        --public-access-prevention
fi

echo "==> Enabling versioning (so state history survives overwrites)"
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

echo "==> Setting lifecycle: keep 10 noncurrent versions, delete older"
cat > /tmp/tfstate-lifecycle.json <<'JSON'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"numNewerVersions": 10, "isLive": false}
      }
    ]
  }
}
JSON
gcloud storage buckets update "gs://$BUCKET_NAME" --lifecycle-file=/tmp/tfstate-lifecycle.json
rm /tmp/tfstate-lifecycle.json

cat <<EOF

==> Done.

Next steps:
  1. Edit backend.tf and set:
       bucket = "$BUCKET_NAME"
  2. Copy terraform.tfvars.example to terraform.tfvars and fill it in.
  3. Run: terraform init
  4. Run: terraform plan
  5. Run: terraform apply

EOF
