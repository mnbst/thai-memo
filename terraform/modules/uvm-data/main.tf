# UVM Data — GCS bucket for vocabulary embeddings
#
# vocab_embeddings.npy (~30MB) と vocab_words.json を格納する。
# Cloud Functions の SA に objectViewer 権限を付与。

resource "google_storage_bucket" "uvm_data" {
  name     = "${var.project_id}-uvm-data"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
}

# Default CF service account に読み取り権限
resource "google_storage_bucket_iam_member" "cf_reader" {
  bucket = google_storage_bucket.uvm_data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}
