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

gcloud storage cp "${CORPUS_DIR}/vocab_embeddings.npy" "gs://${BUCKET}/vocab_embeddings.npy"
gcloud storage cp "${CORPUS_DIR}/vocab_words.json" "gs://${BUCKET}/vocab_words.json"
gcloud storage cp "${CORPUS_DIR}/freq_rank_top10000.json" "gs://${BUCKET}/freq_rank_top10000.json"
gcloud storage cp "${CORPUS_DIR}/topic_embeddings.json" "gs://${BUCKET}/topic_embeddings.json"
if [[ -f "${CORPUS_DIR}/sub_theme_embeddings.json" ]]; then
  gcloud storage cp "${CORPUS_DIR}/sub_theme_embeddings.json" "gs://${BUCKET}/sub_theme_embeddings.json"
else
  echo "Skipping sub_theme_embeddings.json (not found)"
fi
if [[ -f "${CORPUS_DIR}/shot_embeddings.json" ]]; then
  gcloud storage cp "${CORPUS_DIR}/shot_embeddings.json" "gs://${BUCKET}/shot_embeddings.json"
else
  echo "Skipping shot_embeddings.json (not found)"
fi
if [[ -f "${CORPUS_DIR}/style_embeddings.json" ]]; then
  gcloud storage cp "${CORPUS_DIR}/style_embeddings.json" "gs://${BUCKET}/style_embeddings.json"
else
  echo "Skipping style_embeddings.json (not found)"
fi
if [[ -f "${CORPUS_DIR}/politeness_embeddings.json" ]]; then
  gcloud storage cp "${CORPUS_DIR}/politeness_embeddings.json" "gs://${BUCKET}/politeness_embeddings.json"
else
  echo "Skipping politeness_embeddings.json (not found)"
fi

echo "Done."
