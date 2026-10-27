package embeddings

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"sort"
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
	// ショットは件数が多く JSON のパースが重いので、embedding を .npy、本文を
	// 同じ並びの JSON 配列で持つ（scripts/build_shot_embeddings.py が書く）。
	shotEmbBlob   = "shot_embeddings.npy"
	shotTextsBlob = "shot_texts.json"
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

	// sceneStats は場面ごとの centroid と基準語との類似度の分布（SceneScores）。
	sceneStats map[string]sceneStat

	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand

	// Bucket は差し替え用。空なら環境変数から決める。
	Bucket string
	// dir は LoadLocalShots の読み込み元。空でなければ GCS ではなくここから読む。
	dir string
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

// Blob は uvm-data バケットのオブジェクトを読む（LoadLocalShots の Store はローカルから）。
func (s *Store) Blob(ctx context.Context, name string) ([]byte, error) {
	if s.dir != "" {
		return os.ReadFile(filepath.Join(s.dir, name))
	}
	return s.download(ctx, name)
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

// loadShotEmbeddings はショットの embedding を読む（ロード済みなら何もしない）。
func (s *Store) loadShotEmbeddings(ctx context.Context) error {
	if s.shotEmbs != nil {
		return nil
	}
	npy, err := s.download(ctx, shotEmbBlob)
	if err != nil {
		return err
	}
	texts, err := s.download(ctx, shotTextsBlob)
	if err != nil {
		return err
	}
	shots, err := parseShotEmbeddings(npy, texts)
	if err != nil {
		return err
	}
	s.shotEmbs = shots
	return nil
}

// parseShotEmbeddings は .npy の行と本文の配列を突き合わせて、本文 → embedding にする。
func parseShotEmbeddings(npy, textsRaw []byte) (map[string][]float32, error) {
	matrix, err := parseNPY(npy)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", shotEmbBlob, err)
	}
	var texts []string
	if err := json.Unmarshal(textsRaw, &texts); err != nil {
		return nil, fmt.Errorf("%s のパースに失敗: %w", shotTextsBlob, err)
	}
	if len(texts) != len(matrix) {
		return nil, fmt.Errorf("%s（%d行）と %s（%d件）の件数が合わない", shotEmbBlob, len(matrix), shotTextsBlob, len(texts))
	}
	out := make(map[string][]float32, len(texts))
	for i, t := range texts {
		out[t] = matrix[i]
	}
	return out, nil
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

// LoadLocalShots は GCS を介さず、ローカルの語 embedding とショット embedding を
// 読み込んだ Store を返す（cmd での試行・コーパス生成用）。dir は scripts/corpus。
func LoadLocalShots(dir string) (*Store, error) {
	npy, err := os.ReadFile(filepath.Join(dir, embBlob))
	if err != nil {
		return nil, err
	}
	var words []Word
	if err := readJSONFile(filepath.Join(dir, wordsBlob), &words); err != nil {
		return nil, err
	}
	shotNPY, err := os.ReadFile(filepath.Join(dir, shotEmbBlob))
	if err != nil {
		return nil, err
	}
	shotTexts, err := os.ReadFile(filepath.Join(dir, shotTextsBlob))
	if err != nil {
		return nil, err
	}
	shots, err := parseShotEmbeddings(shotNPY, shotTexts)
	if err != nil {
		return nil, err
	}
	s := &Store{dir: dir}
	if err := s.LoadFromBytes(npy, words); err != nil {
		return nil, err
	}
	s.SetNamedEmbeddings(nil, nil, shots)
	return s, nil
}

func readJSONFile(path string, v any) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, v)
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
