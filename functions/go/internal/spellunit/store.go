package spellunit

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
)

// collectionName は部品データの置き場所。uvm とは別のコレクションにする。
const collectionName = "units"

// users/{uid}/units/{unit} の項目:
//
//	dim         次元（onset / vowel / coda / tone）
//	value       部品の値（例: "OO"）
//	p           見分けられる確率
//	attempts    その部品を測った回数
//	confusions  取り違えた先 -> 回数。どの部品と混同しているかが分かると、
//	            同じ次元で深掘りする出題（4番目の段階）を組める。
//	last_seen   最終更新（Unix 秒）

// Apply は綴り4択の証拠を users/{uid}/units へ書き込む。
//
// ここで作ったデータは estimated_vocab にも uvm にも流さない。
func Apply(
	ctx context.Context, db *firestore.Client, uid string, obs []Observation,
) error {
	if len(obs) == 0 {
		return nil
	}
	col := db.Collection("users").Doc(uid).Collection(collectionName)

	refs := make([]*firestore.DocumentRef, 0, len(obs))
	for _, o := range obs {
		refs = append(refs, col.Doc(o.UnitID()))
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		return fmt.Errorf("units の一括取得に失敗: %w", err)
	}
	existing := make(map[string]map[string]any, len(snaps))
	for _, s := range snaps {
		if s.Exists() {
			existing[s.Ref.ID] = s.Data()
		}
	}

	now := float64(time.Now().UnixNano()) / 1e9
	batch := db.BulkWriter(ctx)
	for _, o := range obs {
		id := o.UnitID()
		p := float64(NewUnitP)
		attempts := 0
		var confusions map[string]int
		if data, ok := existing[id]; ok {
			if v, ok := data["p"].(float64); ok {
				p = v
			}
			if v, ok := data["attempts"].(int64); ok {
				attempts = int(v)
			}
			confusions = confusionsField(data)
		}
		doc := map[string]any{
			"dim":       o.Dim.String(),
			"value":     o.Value,
			"p":         UpdateP(p, o.Correct),
			"attempts":  attempts + 1,
			"last_seen": now,
		}
		if !o.Correct && o.ConfusedWith != "" {
			if confusions == nil {
				confusions = map[string]int{}
			}
			confusions[o.ConfusedWith]++
			doc["confusions"] = confusions
		}
		if _, err := batch.Set(col.Doc(id), doc, firestore.MergeAll); err != nil {
			return fmt.Errorf("units の更新に失敗 (%s): %w", id, err)
		}
	}
	batch.End()
	return nil
}

// confusionsField は confusions を読む。Firestore の数値は int64 で返る。
func confusionsField(data map[string]any) map[string]int {
	raw, ok := data["confusions"].(map[string]any)
	if !ok {
		return nil
	}
	out := make(map[string]int, len(raw))
	for k, v := range raw {
		if n, ok := v.(int64); ok {
			out[k] = int(n)
		}
	}
	return out
}
