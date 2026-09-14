# UVM Data — GCS bucket for vocabulary embeddings
#
# vocab_embeddings.npy (~30MB) と vocab_words.json を格納する。
# Cloud Functions の SA に objectViewer 権限を付与。

resource "google_storage_bucket" "uvm_data" {
  name     = "${var.project_id}-uvm-data"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = true

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

# 例文プール（corpus_pool_<lang>.json）への書き込み権限
#
# dailyBatch が judge を通った例文を毎日追記する（functions/go/sentence_pool.go）。
# 上書きには delete 権限が要るので objectViewer では足りない。
# ただしバケットには静的コーパスと embeddings（再生成に数時間かかる）も
# 同居しているので、条件でプールのオブジェクト名だけに絞る。
resource "google_storage_bucket_iam_member" "cf_pool_writer" {
  bucket = google_storage_bucket.uvm_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"

  condition {
    title       = "corpus_pool_objects_only"
    description = "例文プールのオブジェクトだけ書き換えを許す"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.uvm_data.name}/objects/corpus_pool_\")"
  }
}
