#!/bin/bash
# GCS bucket for Terraform state

PROJECT_ID="thai-memo-67139"
BUCKET_NAME="${PROJECT_ID}-terraform-state"
REGION="asia-northeast1"

echo "Creating GCS bucket for Terraform state..."

# Create bucket with versioning enabled
gcloud storage buckets create gs://${BUCKET_NAME} \
  --project=${PROJECT_ID} \
  --location=${REGION} \
  --uniform-bucket-level-access

# Enable versioning for state file safety
gcloud storage buckets update gs://${BUCKET_NAME} \
  --versioning

echo "Bucket created: gs://${BUCKET_NAME}"
echo "You can now uncomment the backend block in versions.tf and run: terraform init -migrate-state"
