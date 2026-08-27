package uvm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	"cloud.google.com/go/storage"
)

// FreqRank は単語 -> 頻度順位。GCS の freq_rank_top10000.json 由来。
// 拘束形態素を除いた連番なので rank に穴はない。
type FreqRank map[string]int

var (
	freqRankMu   sync.Mutex
	freqRankData FreqRank
)

// GetFreqRank は GCS から freq_rank_top10000.json を読み込みキャッシュする
// （sentence_service.py:get_freq_rank）。
//
// バケットは {projectID}-uvm-data。失敗はキャッシュしない（次回また取りに行く）。
func GetFreqRank(ctx context.Context, projectID string) (FreqRank, error) {
	freqRankMu.Lock()
	defer freqRankMu.Unlock()
	if freqRankData != nil {
		return freqRankData, nil
	}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()

	bucket := projectID + "-uvm-data"
	r, err := client.Bucket(bucket).Object("freq_rank_top10000.json").NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("gs://%s/freq_rank_top10000.json を開けない: %w", bucket, err)
	}
	defer r.Close()

	b, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("freq_rank の読み出しに失敗: %w", err)
	}
	var out FreqRank
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, fmt.Errorf("freq_rank の JSON 解析に失敗: %w", err)
	}

	freqRankData = out
	return out, nil
}
