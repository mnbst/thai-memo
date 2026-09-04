package uvm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// TestItem は語彙テストの出題語 1 件。
// gs://{project}-uvm-data/vocab_test_items_<lang>.json 由来
// （scripts/build_vocab_test_items.py が作る）。
type TestItem struct {
	Word string `json:"word"`
	Rank int    `json:"rank"`
	// Gloss は訳語。誤答選択肢にも使い回すので、1 語 1 訳に絞ること。
	Gloss string `json:"gloss"`
}

// TestItemStore は出題語を GCS から読み、言語ごとにキャッシュする。
//
// freq_rank と違い全 1 万語は要らない。段ごとに数十語あれば足りるので、
// ファイルは 100 語程度に絞ってある。
type TestItemStore struct {
	// ProjectID は GCS バケット名 {ProjectID}-uvm-data に使う。
	ProjectID string

	mu    sync.Mutex
	cache map[lang.Lang][]TestItem
}

// Items は vocab_test_items_<lang>.json を読む。
// 失敗はキャッシュしない（次回また取りに行く）。
func (s *TestItemStore) Items(ctx context.Context, l lang.Lang) ([]TestItem, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if cached, ok := s.cache[l]; ok {
		return cached, nil
	}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()

	name := fmt.Sprintf("vocab_test_items_%s.json", l)
	bucket := s.ProjectID + "-uvm-data"
	r, err := client.Bucket(bucket).Object(name).NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("gs://%s/%s を開けない: %w", bucket, name, err)
	}
	defer r.Close()

	b, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("%s の読み出しに失敗: %w", name, err)
	}
	var items []TestItem
	if err := json.Unmarshal(b, &items); err != nil {
		return nil, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
	}

	if s.cache == nil {
		s.cache = map[lang.Lang][]TestItem{}
	}
	s.cache[l] = items
	return items, nil
}
