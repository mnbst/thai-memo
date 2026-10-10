// Package themeshots は BL 以外のテーマ回に付ける参考例文ブロックを組み立てる。
//
// BL ドラマ回（internal/bldrama）と同じく、場面と実際の会話の1文を渡して
// 口語の言い回しを寄せる。違いはドラマ設定・人物を持たないことと、
// テーマと関係の行を残すこと（場面はサブテーマの代わり）。丁寧さは関係の
// 指定が決めるので、参考例文には合わせさせない（2つの指示がぶつかる）。
//
// 参考例文は1文だけ渡す。複数渡すと語を混ぜて合成した非文が出る（bldrama と同じ理由）。
//
// 選出は2段。まず場面を選び、その場面のショットから一様に選ぶ。場面は、語と
// 場面（属するショットの embedding の平均）の類似度で足切りし、通った場面から
// 一様に選ぶ。どれも通らなければ全場面から一様に選ぶ。最も近い場面を採ると
// 汎用的な場面へ、ショットから一様に選ぶとショットの多い場面へ偏った
// （コーパスの語で場面の分布を比較。学校は授業が65%→48%）。
// 付ける回を類似度で絞ることはしない（絞るとサブテーマ由来の偏り＝辛さ・
// アレルギーが戻った。食べ物156語の比較）。
package themeshots

import (
	"context"
	"log"
	"math/rand"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// SceneFinder は語に近い場面を返す。実装は internal/embeddings.Store。
type SceneFinder interface {
	FindNearScenes(ctx context.Context, word string, scenes []embeddings.Scene, threshold float64) ([]string, error)
}

// sceneThreshold は場面を足切りする類似度の下限。食べ物156語のうち約3分の1が
// 届き、届いた語の場面はほぼ妥当（ทอด→調理法、อิ่ม→量の多さ）。下回る語の
// 最近傍は意味を持たない（รัฐมนตรี→昔ながらの味）。
const sceneThreshold = 0.75

// topicShot はテーマごとのショットの候補と、場面を落としたときのやり取り。
type topicShot struct {
	ids []string
	// fallback は場面が語と合わないときに代わりに置くやり取り（「〜にする」の〜）。
	fallback string
}

// topicShots はショットを持つテーマ。
var topicShots = map[string]topicShot{
	sentence.Topics[0]:  {greetingShotIDs, "あいさつのやり取り"},
	sentence.Topics[1]:  {foodShotIDs, "食事・注文のやり取り"},
	sentence.Topics[2]:  {travelShotIDs, "旅行中のやり取り"},
	sentence.Topics[3]:  {workShotIDs, "仕事のやり取り"},
	sentence.Topics[4]:  {familyShotIDs, "家族の会話"},
	sentence.Topics[5]:  {shoppingShotIDs, "買い物のやり取り"},
	sentence.Topics[6]:  {transportShotIDs, "移動のやり取り"},
	sentence.Topics[7]:  {healthShotIDs, "体調・健康の会話"},
	sentence.Topics[8]:  {weatherShotIDs, "天気の会話"},
	sentence.Topics[9]:  {hobbyShotIDs, "趣味の会話"},
	sentence.Topics[10]: {schoolShotIDs, "学校での会話"},
	sentence.Topics[11]: {religionShotIDs, "寺や信仰の会話"},
	sentence.Topics[12]: {traditionShotIDs, "伝統や行事の会話"},
	sentence.Topics[13]: {mannersShotIDs, "礼儀を意識したやり取り"},
	sentence.Topics[14]: {romanceShotIDs, "恋人や好きな人との会話"},
}

// Builder はテーマ回のプロンプト断片を作る。
type Builder struct {
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand
	// Scenes は nil なら場面で絞らず、全ショットからランダムに選ぶ。
	Scenes SceneFinder
	// Ctx は embedding の取得に使う。nil なら context.Background()。
	Ctx context.Context
}

// PickShot はテーマの候補から参考にするショットを1つ選ぶ。候補が無いテーマなら "" を返す。
func (b *Builder) PickShot(topic string, targetWords []string) string {
	ids := topicShots[topic].ids
	if len(ids) == 0 {
		return ""
	}
	scene := b.findScene(ids, targetWords)
	if scene == "" {
		names := sceneNames(ids)
		scene = names[b.intn(len(names))]
	}
	var in []string
	for _, id := range ids {
		if shotScene[id] == scene {
			in = append(in, id)
		}
	}
	return in[b.intn(len(in))]
}

// sceneNames はショットの場面を重複なく、出てきた順で返す。
func sceneNames(ids []string) []string {
	var names []string
	seen := map[string]bool{}
	for _, id := range ids {
		if !seen[shotScene[id]] {
			seen[shotScene[id]] = true
			names = append(names, shotScene[id])
		}
	}
	return names
}

// findScene は語に十分近い場面のどれかを一様に選んで返す。無ければ ""。
func (b *Builder) findScene(ids, targetWords []string) string {
	if b.Scenes == nil || len(targetWords) == 0 {
		return ""
	}
	var scenes []embeddings.Scene
	at := map[string]int{}
	for _, id := range ids {
		name := shotScene[id]
		i, ok := at[name]
		if !ok {
			i = len(scenes)
			at[name] = i
			scenes = append(scenes, embeddings.Scene{Name: name})
		}
		scenes[i].Texts = append(scenes[i].Texts, shots[id])
	}
	near, err := b.Scenes.FindNearScenes(b.ctx(), targetWords[0], scenes, sceneThreshold)
	if err != nil {
		// 場面で絞れなくても回はショット付きのまま。ランダムへ縮退させる。
		log.Printf("theme scene の選出に失敗: %v", err)
		return ""
	}
	if len(near) == 0 {
		return ""
	}
	return near[b.intn(len(near))]
}

func (b *Builder) ctx() context.Context {
	if b.Ctx != nil {
		return b.Ctx
	}
	return context.Background()
}

func (b *Builder) intn(n int) int {
	if b.Rand != nil {
		return b.Rand.Intn(n)
	}
	return rand.Intn(n)
}

// BuildShotSection はテーマ回のプロンプト断片を返す。ショットの無いテーマならゼロ値。
//
// medium が会話以外で、そのテーマにその媒体の例文（writtenShots）があればそちらを付ける。
// 無ければ会話のショットを付け、媒体を対面の会話に戻す。
func (b *Builder) BuildShotSection(topic string, targetWords []string, medium string) sentence.DramaSection {
	if texts := writtenShots[topic][medium]; len(texts) > 0 {
		return sentence.DramaSection{
			Context: "- 参考タイ語例（言い回しの参考。この1文のみ）: " + texts[b.intn(len(texts))] + "\n",
			Required: "- 参考タイ語例をそのまま使わず、オリジナルの1文を作る。" +
				"参考例の語を部分的に差し替えて別の意味の語を作らない\n",
			Medium: medium,
		}
	}
	id := b.PickShot(topic, targetWords)
	if id == "" {
		return sentence.DramaSection{}
	}
	return b.shotSection(topic, id)
}

// shotSection は会話のショット1つを参考例文にした断片を返す。
func (b *Builder) shotSection(topic, id string) sentence.DramaSection {
	return sentence.DramaSection{
		Medium: sentence.Media[0].Name,
		Context: "- 場面: " + shotScene[id] + "\n" +
			"- 参考タイ語例（話し言葉の言い回しの参考。この1文のみ）: " + shots[id] + "\n",
		Required: "- 参考タイ語例をそのまま使わず、同じ場面のオリジナルの1文を作る。" +
			"参考例の語を部分的に差し替えて別の意味の語を作らない\n" +
			"- 場面がターゲット単語と合わなければ場面は落とし、ターゲット単語が字義どおり出てくる" + topicShots[topic].fallback + "にする\n",
	}
}

// ResolveGroup はまとめたテーマ（sentence.TopicGroups）を、語に近い場面を持つ
// 中身の個別テーマへ解決する（sentence.GroupResolver）。
//
// 場面は中身すべてのショットの場面から、足切りを通ったものを一様に選ぶ。同じ名前の場面が複数のテーマにある
// （食べ物と買い物の「値段を聞く」など）ときは、その場面のショットを1つ引き、
// その持ち主のテーマにする。語に十分近い場面が無ければ "" を返し、
// 呼び出し側が中身から一様に選ぶ。
func (b *Builder) ResolveGroup(group, word string) string {
	var ids []string
	owner := map[string]string{}
	for _, t := range sentence.TopicGroups[group] {
		for _, id := range topicShots[t].ids {
			ids = append(ids, id)
			owner[id] = t
		}
	}
	scene := b.findScene(ids, []string{word})
	if scene == "" {
		return ""
	}
	var in []string
	for _, id := range ids {
		if shotScene[id] == scene {
			in = append(in, id)
		}
	}
	return owner[in[b.intn(len(in))]]
}

// SceneShots はテーマの場面ごとのショット文を返す。コーパスの場面を均すときの
// 語と場面の近さの計算に使う。
func SceneShots(topic string) map[string][]string {
	out := map[string][]string{}
	for _, id := range topicShots[topic].ids {
		out[shotScene[id]] = append(out[shotScene[id]], shots[id])
	}
	return out
}

// BuildSceneSection は場面を指定してテーマ回のプロンプト断片を返す。
// 語に近い場面は特定の場面へ集まるので、コーパスの場面を均して作り直すときに使う。
// その場面のショットが無ければゼロ値。
func (b *Builder) BuildSceneSection(topic, scene string) sentence.DramaSection {
	var in []string
	for _, id := range topicShots[topic].ids {
		if shotScene[id] == scene {
			in = append(in, id)
		}
	}
	if len(in) == 0 {
		return sentence.DramaSection{}
	}
	return b.shotSection(topic, in[b.intn(len(in))])
}
