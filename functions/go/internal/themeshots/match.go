package themeshots

import (
	"log"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// 場面合致（SceneMatch）と一様抽選（EvenDraw）。premium の全テーマ（BL を含む）で共通。
//
// 場面は属するショットの重心、ショットは1文ずつを、語彙全体との類似度で標準化した
// z で語と比べる（SceneScores。1文のショットは「1文だけの場面」として渡す）。
// 場面 z が閾値以上で、場面内にショット z が閾値以上の文がある場面だけを残し
// （閾値はテーマごとに sentence.SceneThresholds）、
// テーマ → 場面 → ショットの順に一様に選ぶ。
//
// 一様に選ぶのは偏りを減らすため。z の重みや生の類似度の最大を採ると、どの語にも
// 近く出る場面（ムエタイ、BL の重心）や場面の多いテーマ（仕事58・食べ物40場面）に寄る。
// prod の埋め込み・rank 3464 までの語で、付いたショットが語に合う割合（ショット
// z≥2）は現行 15% → 100%、最多の場面の割合は 1.3%（2026-10-20）。

// matchScene は場面合致の候補の場面1つ。
type matchScene struct {
	name  string
	ids   []string
	scene embeddings.Scene
	// shots は1文ずつを1つの場面にしたもの（ショット z を出すため）。
	shots []embeddings.Scene
}

var (
	catalogOnce sync.Once
	// catalog はテーマ → 場面（ショットの並び順）。BL は bldrama のショットから作る。
	catalog map[string][]matchScene
)

func sceneCatalog() map[string][]matchScene {
	catalogOnce.Do(func() {
		catalog = map[string][]matchScene{}
		at := map[string]map[string]int{}
		add := func(topic, scene, id, text string) {
			if at[topic] == nil {
				at[topic] = map[string]int{}
			}
			i, ok := at[topic][scene]
			if !ok {
				i = len(catalog[topic])
				at[topic][scene] = i
				catalog[topic] = append(catalog[topic], matchScene{
					name: scene, scene: embeddings.Scene{Name: scene},
				})
			}
			sc := &catalog[topic][i]
			sc.ids = append(sc.ids, id)
			sc.scene.Texts = append(sc.scene.Texts, text)
			// 名前は場面の統計のキャッシュキーに入るので、場面と取り違えないよう ID を付ける。
			sc.shots = append(sc.shots, embeddings.Scene{Name: "shot:" + id, Texts: []string{text}})
		}
		for topic, ts := range topicShots {
			for _, id := range ts.ids {
				add(topic, shotScene[id], id, shots[id])
			}
		}
		for _, sh := range bldrama.SceneShots() {
			add(sentence.Topics[15], sh.Scene, sh.ID, sh.Text)
		}
	})
	return catalog
}

// matched は場面合致を通った場面と、その中でショット z を満たした ID。
type matched struct {
	topic, scene string
	ids          []string
}

// matchScenes は topics の場面のうち場面合致を通ったものを、テーマごとに返す
// （topics の順。通った場面の無いテーマは入らない）。
func (b *Builder) matchScenes(word string, topics []string, minSceneZ float64) [][]matched {
	if b.Scenes == nil {
		return nil
	}
	var out [][]matched
	for _, topic := range topics {
		scenes := sceneCatalog()[topic]
		if len(scenes) == 0 {
			continue
		}
		emb := make([]embeddings.Scene, len(scenes))
		for i, sc := range scenes {
			emb[i] = sc.scene
		}
		z, err := b.Scenes.SceneScores(b.ctx(), word, emb)
		if err != nil {
			log.Printf("scene match の場面 z に失敗 word=%s: %v", word, err)
			return nil
		}
		if len(z) != len(scenes) {
			// 語の embedding が無い。どのテーマでも同じなので打ち切る。
			return nil
		}
		sceneMin, shotMin := sentence.SceneThresholds(topic, minSceneZ)
		var hits []matched
		for i, sc := range scenes {
			if z[i] < sceneMin {
				continue
			}
			shotZ, err := b.Scenes.SceneScores(b.ctx(), word, sc.shots)
			if err != nil || len(shotZ) != len(sc.ids) {
				continue
			}
			var good []string
			for j, v := range shotZ {
				if v >= shotMin {
					good = append(good, sc.ids[j])
				}
			}
			if len(good) > 0 {
				hits = append(hits, matched{topic: topic, scene: sc.name, ids: good})
			}
		}
		if len(hits) > 0 {
			out = append(out, hits)
		}
	}
	return out
}

// PickScene は場面合致を通った候補から、テーマ → 場面 → ショットの順に一様に選ぶ。
func (b *Builder) PickScene(word string, topics []string, minSceneZ float64) (sentence.ScenePick, bool) {
	byTopic := b.matchScenes(word, topics, minSceneZ)
	if len(byTopic) == 0 {
		return sentence.ScenePick{}, false
	}
	hits := byTopic[b.intn(len(byTopic))]
	hit := hits[b.intn(len(hits))]
	return sentence.ScenePick{
		Topic: hit.topic, Scene: hit.scene, ShotID: hit.ids[b.intn(len(hit.ids))],
	}, true
}

// HasScene は場面合致を通る場面があるか（テーマ寄せの判定用。抽選しない）。
func (b *Builder) HasScene(word string, topics []string, minSceneZ float64) bool {
	return len(b.matchScenes(word, topics, minSceneZ)) > 0
}
