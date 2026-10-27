package themeshots

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"runtime"
	"sort"
	"sync"
)

// MatchTableBlob は場面合致の表の GCS 上の名前（uvm-data バケット）。
const MatchTableBlob = "scene_match_table.json"

// BlobSource は GCS のオブジェクトを読む。実装は embeddings.Store。
type BlobSource interface {
	Blob(ctx context.Context, name string) ([]byte, error)
}

// MatchTable は語ごとの場面・ショットの近さ（topicScores）を事前に計算した表。
// ショット z が minShotZ 以上のショットだけを持ち、閾値での絞り込みは本番で行う。
type MatchTable struct {
	// Version はショットの並びと本文から作る（catalogVersion）。合わない表は使わない。
	Version string `json:"version"`
	// Shots は "テーマ\x00ショットID" の並び。Rows の添字はこれを指す。
	Shots []string `json:"shots"`
	// Rows は語 → その語の近さ。embedding の無い語は入らない。
	Rows map[string]TableRow `json:"rows"`
}

// TableRow は語1つぶんの [ショットの添字, 場面 z, ショット z]（ショットの並び順）。
// ショット z が minShotZ 未満のショットしか無い場面は判定に使われないので持たない。
type TableRow [][3]float32

// catalogVersion はショットの並び・本文・表の下限から作る版。ショットを足すと変わる。
func catalogVersion() string {
	h := sha256.New()
	fmt.Fprintf(h, "%v\n", minShotZ)
	for _, topic := range catalogTopics() {
		for _, sc := range sceneCatalog()[topic] {
			fmt.Fprintf(h, "%s\x00%s\n", topic, sc.name)
			for i, id := range sc.ids {
				fmt.Fprintf(h, "%s\x00%s\n", id, sc.shots[i].Texts[0])
			}
		}
	}
	return hex.EncodeToString(h.Sum(nil))[:16]
}

func catalogTopics() []string {
	var out []string
	for t := range sceneCatalog() {
		out = append(out, t)
	}
	sort.Strings(out)
	return out
}

// BuildMatchTable は words の表をその場の計算（b.Scenes）で作る。cmd/scenetable が使う。
func (b *Builder) BuildMatchTable(words []string) *MatchTable {
	t := &MatchTable{Version: catalogVersion(), Rows: map[string]TableRow{}}
	at := map[string]int{}
	for _, topic := range catalogTopics() {
		for _, sc := range sceneCatalog()[topic] {
			for _, id := range sc.ids {
				at[topic+"\x00"+id] = len(t.Shots)
				t.Shots = append(t.Shots, topic+"\x00"+id)
			}
		}
	}
	rows := make([]*TableRow, len(words))
	var wg sync.WaitGroup
	next := make(chan int)
	for range runtime.NumCPU() {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range next {
				row := &TableRow{}
				for _, topic := range catalogTopics() {
					scores, ok := b.liveScores(words[i], topic)
					if !ok {
						row = nil
						break
					}
					for _, sc := range scores {
						for _, sh := range sc.shots {
							*row = append(*row, [3]float32{float32(at[topic+"\x00"+sh.id]), float32(sc.z), float32(sh.z)})
						}
					}
				}
				rows[i] = row
			}
		}()
	}
	for i := range words {
		next <- i
	}
	close(next)
	wg.Wait()
	for i, r := range rows {
		if r != nil {
			t.Rows[words[i]] = *r
		}
	}
	return t
}

// matchIndex は表を本番で引く形にしたもの。
type matchIndex struct {
	// rows は 語 → テーマ → 場面の並び順の近さ（当たりのある場面だけ）。
	rows map[string]map[string][]sceneScore
}

func newMatchIndex(t *MatchTable) (*matchIndex, error) {
	if v := catalogVersion(); t.Version != v {
		return nil, fmt.Errorf("表の版 %s がショットの版 %s と合わない（cmd/scenetable で作り直す）", t.Version, v)
	}
	type ref struct {
		topic string
		id    string
	}
	refs := make([]ref, len(t.Shots))
	for i, k := range t.Shots {
		for j := range len(k) {
			if k[j] == 0 {
				refs[i] = ref{k[:j], k[j+1:]}
				break
			}
		}
	}
	sceneOf := map[ref]int{}
	for topic, scenes := range sceneCatalog() {
		for i, sc := range scenes {
			for _, id := range sc.ids {
				sceneOf[ref{topic, id}] = i
			}
		}
	}
	idx := &matchIndex{rows: make(map[string]map[string][]sceneScore, len(t.Rows))}
	for word, row := range t.Rows {
		byTopic := map[string][]sceneScore{}
		// 行はショットの並び順なので、同じ場面のショットは続けて出る。
		for _, h := range row {
			r := refs[int(h[0])]
			scenes := byTopic[r.topic]
			name := sceneCatalog()[r.topic][sceneOf[r]].name
			if len(scenes) == 0 || scenes[len(scenes)-1].name != name {
				scenes = append(scenes, sceneScore{name: name, z: float64(h[1])})
			}
			last := &scenes[len(scenes)-1]
			last.shots = append(last.shots, shotScore{id: r.id, z: float64(h[2])})
			byTopic[r.topic] = scenes
		}
		idx.rows[word] = byTopic
	}
	return idx, nil
}

// scores は liveScores と同じ形で表を引く。表に無い語は embedding の無い語。
func (m *matchIndex) scores(word, topic string) ([]sceneScore, bool) {
	row, ok := m.rows[word]
	if !ok {
		return nil, false
	}
	return row[topic], true
}

// LoadMatchTable は表をパースして Builder に持たせる（cmd・テスト用）。
func (b *Builder) LoadMatchTable(raw []byte) error {
	var t MatchTable
	if err := json.Unmarshal(raw, &t); err != nil {
		return fmt.Errorf("%s のパースに失敗: %w", MatchTableBlob, err)
	}
	idx, err := newMatchIndex(&t)
	if err != nil {
		return err
	}
	b.tableOnce.Do(func() {})
	b.table = idx
	return nil
}

// matchIndex は表を初回だけ読む。読めない・版が合わなければ nil（その場で計算する）。
func (b *Builder) matchIndex() *matchIndex {
	b.tableOnce.Do(func() {
		if b.Tables == nil {
			return
		}
		raw, err := b.Tables.Blob(b.ctx(), MatchTableBlob)
		if err != nil {
			log.Printf("場面合致の表を読めない。その場で計算する: %v", err)
			return
		}
		var t MatchTable
		if err := json.Unmarshal(raw, &t); err != nil {
			log.Printf("%s のパースに失敗。その場で計算する: %v", MatchTableBlob, err)
			return
		}
		idx, err := newMatchIndex(&t)
		if err != nil {
			log.Printf("場面合致の表を使わない: %v", err)
			return
		}
		b.table = idx
		log.Printf("場面合致の表を読んだ: %d語 版=%s", len(idx.rows), t.Version)
	})
	return b.table
}
