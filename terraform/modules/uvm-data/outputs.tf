output "bucket_name" {
  description = "UVM data GCS bucket name"
  value       = google_storage_bucket.uvm_data.name
}
