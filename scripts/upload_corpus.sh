#!/bin/bash
# UVMデータをGCSバケットにアップロードする
#
# Usage: ./upload_corpus.sh [project_id]
# Example: ./upload_corpus.sh thai-memo-dev

set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value project)}"
BUCKET="${PROJECT_ID}-uvm-data"
CORPUS_DIR="$(dirname "$0")/corpus"

echo "Uploading UVM data to gs://${BUCKET}/"

gsutil cp "${CORPUS_DIR}/vocab_embeddings.npy" "gs://${BUCKET}/vocab_embeddings.npy"
gsutil cp "${CORPUS_DIR}/vocab_words.json" "gs://${BUCKET}/vocab_words.json"
gsutil cp "${CORPUS_DIR}/freq_rank_top10000.json" "gs://${BUCKET}/freq_rank_top10000.json"
gsutil cp "${CORPUS_DIR}/topic_embeddings.json" "gs://${BUCKET}/topic_embeddings.json"

echo "Done."
