package embeddings

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"os"
	"sort"
	"strings"
	"sync"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

// GCS 上のオブジェクト名。
const (
	embBlob         = "vocab_embeddings.npy"
	wordsBlob       = "vocab_words.json"
	topicEmbBlob    = "topic_embeddings.json"
	subThemeEmbBlob = "sub_theme_embeddings.json"
	shotEmbBlob     = "shot_embeddings.json"
)

// Store は embedding データを保持する。
//
// Cloud Functions はコンテナが再利用されるため、初回ロード後はメモリ上に保持して
// 2回目以降の GCS アクセスを避ける。
type Store struct {
	mu sync.Mutex

	matrix   [][]float32
	words    []Word
	wordToIx map[string]int

	topicEmbs    map[string][]float32
	subThemeEmbs map[string][]float32
	shotEmbs     map[string][]float32

	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand

	// Bucket は差し替え用。空なら環境変数から決める。
	Bucket string
}

// Default は本番用のストア。
var Default = &Store{}

// bucketName は UVM_DATA_BUCKET、未設定なら "<project>-uvm-data"。
func (s *Store) bucketName() string {
	if s.Bucket != "" {
		return s.Bucket
	}
	if b := os.Getenv("UVM_DATA_BUCKET"); b != "" {
		return b
	}
	return fbapp.ProjectID() + "-uvm-data"
}

func (s *Store) download(ctx context.Context, name string) ([]byte, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("GCS クライアントの生成に失敗: %w", err)
	}
	defer client.Close()

	r, err := client.Bucket(s.bucketName()).Object(name).NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("%s を読めない: %w", name, err)
	}
	defer r.Close()
	return io.ReadAll(r)
}

// Load は語彙 embedding と単語メタデータを読み込む。ロード済みなら何もしない。
func (s *Store) Load(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.loadLocked(ctx)
}

func (s *Store) loadLocked(ctx context.Context) error {
	if s.matrix != nil {
		return nil
	}

	raw, err := s.download(ctx, embBlob)
	if err != nil {
		return err
	}
	matrix, err := parseNPY(raw)
	if err != nil {
		return err
	}

	wordsRaw, err := s.download(ctx, wordsBlob)
	if err != nil {
		return err
	}
	var words []Word
	if err := json.Unmarshal(wordsRaw, &words); err != nil {
		return fmt.Errorf("%s のパースに失敗: %w", wordsBlob, err)
	}

	wordToIx := make(map[string]int, len(words))
	for i, w := range words {
		// Python は上書きなしの代入なので、重複語は**後**が勝つ。
		wordToIx[w.Word] = i
	}

	s.matrix, s.words, s.wordToIx = matrix, words, wordToIx
	return nil
}

// loadJSONEmbeddings は名前つき embedding 表を読む（ロード済みなら何もしない）。
func (s *Store) loadJSONEmbeddings(
	ctx context.Context, dst *map[string][]float32, blob string,
) error {
	if *dst != nil {
		return nil
	}
	raw, err := s.download(ctx, blob)
	if err != nil {
		return err
	}
	var parsed map[string][]float32
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return fmt.Errorf("%s のパースに失敗: %w", blob, err)
	}
	*dst = parsed
	return nil
}

// Embedding は語の embedding を返す。語彙リストに無い未知語は nil。
func (s *Store) Embedding(word string) []float32 {
	s.mu.Lock()
	defer s.mu.Unlock()
	i, ok := s.wordToIx[word]
	if !ok {
		return nil
	}
	return s.matrix[i]
}

// TopicEmbedding はテーマ文字列の embedding を返す。
// 完全一致に加えて部分一致（どちらの向きでも）を許す。
func (s *Store) TopicEmbedding(ctx context.Context, topic string) ([]float32, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.loadJSONEmbeddings(ctx, &s.topicEmbs, topicEmbBlob); err != nil {
		return nil, err
	}
	return findEmbedding(topic, s.topicEmbs), nil
}

// findEmbedding は Python の _find_embedding。
// map の反復順に依存するため、Go では決定的になるようキー順で走査する。
func findEmbedding(label string, embs map[string][]float32) []float32 {
	for _, key := range sortedKeys(embs) {
		if label == key || strings.Contains(key, label) || strings.Contains(label, key) {
			return embs[key]
		}
	}
	return nil
}

func sortedKeys(m map[string][]float32) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func (s *Store) rng() *rand.Rand {
	if s.Rand != nil {
		return s.Rand
	}
	return nil
}

// pick は重みつきランダムで1件選ぶ。weights が nil なら一様。
func (s *Store) pick(n int, weights []float64) int {
	if n <= 0 {
		return -1
	}
	r := s.rng()
	randFloat := rand.Float64
	randIntn := rand.Intn
	if r != nil {
		randFloat = r.Float64
		randIntn = r.Intn
	}

	if weights == nil {
		return randIntn(n)
	}
	var total float64
	for _, w := range weights {
		total += w
	}
	target := randFloat() * total
	var cum float64
	for i, w := range weights {
		cum += w
		if target < cum {
			return i
		}
	}
	return n - 1
}

// LoadFromBytes は GCS を介さずにデータを読み込む（テスト・ローカル実行用）。
func (s *Store) LoadFromBytes(npy []byte, words []Word) error {
	matrix, err := parseNPY(npy)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.matrix = matrix
	s.words = words
	s.wordToIx = make(map[string]int, len(words))
	for i, w := range words {
		s.wordToIx[w.Word] = i
	}
	return nil
}

// SetNamedEmbeddings はテーマ・サブテーマ・ショットの embedding を差し込む
// （テスト・ローカル実行用）。
func (s *Store) SetNamedEmbeddings(topic, subTheme, shot map[string][]float32) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if topic != nil {
		s.topicEmbs = topic
	}
	if subTheme != nil {
		s.subThemeEmbs = subTheme
	}
	if shot != nil {
		s.shotEmbs = shot
	}
}
