package sentence

import (
	"context"
	"errors"
	"math"
	"math/rand"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// TopicChoice はターゲット語の選定前に決まるテーマの扱い。
type TopicChoice struct {
	// Topic は確定したテーマ。空なら key_word から自動選択する。
	Topic string
	// Pool は自動選択の候補。nil なら全テーマから選ぶ。
	Pool []string
	// Slots は premium おまかせの枠ごとのテーマ（Pool から一様に選んだもの）。
	// i 番目の語はテーマ指定 Slots[i] と同じ扱いで選ぶ。
	Slots []string
}

// ChooseTopic は語彙レベルに応じたテーマ候補を作り、free では 1 つに決める
// （sentence_service.py:select_uvm_target_words:294 の前半）。
//
// 候補プールは free / premium 共通（TOPICS を TOPIC_MIN_VOCAB でゲート）。
// 違うのは選び方だけで、free はここで一様抽選、premium は選定時に枠ごとに一様抽選
// する（SelectTargetWords。場面合致が無ければ embedding で key_word に最も近いテーマ）。
//
// 2026-08-14 実測: free の旧プール4件で find_best_topic を使うと BLドラマが
// 82.7%。テーマ embedding は語彙全体への平均類似度に差があり、重心の高い BL が
// 全語で argmax になる。BL は刺さる層には強いが大半には刺さらないので、
// free は分布を均等にする。
//
// 推し活は premium だけのテーマなので、free の抽選からは外す。
func ChooseTopic(
	topic string, isPremium bool, estimatedVocab int,
	randFloat func() float64, randIntn func(int) int,
) TopicChoice {
	if topic != "" {
		return TopicChoice{Topic: topic}
	}
	pool := GateTopicsForVocab(append([]string(nil), Topics...), estimatedVocab)
	if isPremium {
		return TopicChoice{Pool: pool}
	}
	if randFloat() < FreeBLTopicRate {
		// BL は語彙ゲートの対象で free（vocab は 100 でキャップ）には
		// ほぼ出ない。刺さる層向けにレベルと無関係で一定確率だけ混ぜる。
		return TopicChoice{Topic: BLTopic}
	}
	var rest []string
	for _, t := range pool {
		if t != BLTopic && t != OshiTopic {
			rest = append(rest, t)
		}
	}
	if len(rest) == 0 {
		// ゲートで BL しか残らないレベルはテーマ無しで LLM に委ねる。
		return TopicChoice{}
	}
	return TopicChoice{Topic: rest[randIntn(len(rest))]}
}

// ResolveInterviewTopic はヒアリングの goal からテーマを 1 つ選ぶ
// （sentence_service.py:resolve_interview_topic:281）。
//
// 未回答（旧クライアント）や未知の goal では空を返し、従来どおり
// key_word 起点の自動選出に任せる。候補が複数あるものは毎回引き直す。
func ResolveInterviewTopic(userData map[string]any, randIntn func(int) int) string {
	// Python は isinstance(interview, dict) を見る。Go では型アサーションが
	// 失敗しても nil map になり、そこからの読み出しはゼロ値になるので、
	// この分岐を外しても結果は変わらない（残しているのは意図を示すため）。
	interview, ok := userData["interview"].(map[string]any)
	if !ok {
		return ""
	}
	goal, _ := interview["goal"].(string)
	// INTERVIEW_GOAL_TOPICS の値は必ず 1 件以上あるので、len(...) == 0 に
	// なるのは goal が未知（map ミス）のときだけ。
	candidates := InterviewGoalTopics[goal]
	if len(candidates) == 0 {
		return ""
	}
	return candidates[randIntn(len(candidates))]
}

// GroupResolver はまとめたテーマ（TopicGroups）を、語に合う中身の個別テーマへ
// 解決する。実装は themeshots.Builder（語に近い参考例文の場面から決める）。
// 決められなければ "" を返す。
type GroupResolver interface {
	ResolveGroup(group, word string) string
}

// TargetWordSelector はターゲット語の選定に必要な依存をまとめる。
type TargetWordSelector struct {
	// Session は uvm 側の選定。Rand と Emb はここで注入する。
	Session *uvm.SessionSelector
	// Rand はテーマ抽選に使う。nil なら共有の乱数源。
	Rand *rand.Rand
	// Groups はまとめたテーマの解決に使う。nil か "" なら中身から一様に選ぶ。
	Groups GroupResolver
	// Scenes は premium の場面合致（SceneMatch）。nil なら premium も free と同じ
	// 従来の選び方（FindBestTopic・ResolveGroup）になる。
	Scenes SceneMatcher
}

// 場面合致の閾値。z は、語と場面（またはショット）の類似度を、語彙全体との
// 類似度の平均・標準偏差で標準化した値。prod の埋め込み・rank 3464 までの語で
// 7パターンを比べて決めた（2026-10-20）。
const (
	// SceneZOmakase は旧おまかせ（全テーマの場面からテーマも決めた）の場面 z。
	// おまかせは枠ごとにテーマを先に決めるようにしたので、今は照合表の検査だけで使う。
	SceneZOmakase = 3.0
	// SceneZPinned はテーマ指定の場面 z（テーマごとの値は sceneZPinnedByTopic）。
	// テーマは決まっているので合う語の数を優先する。
	SceneZPinned = 2.0
	// ShotZ はショット単体の z。場面の重心だけだと、雰囲気は近いのに参考になる
	// 文が1つも無い場面が残る。ショット単位だけで選ぶと綴りの一致による誤爆が
	// 半分ほど混ざった（มีด→値段を聞く）。
	ShotZ = 3.5
	// ShotZShotFirst は ShotFirstTopics をテーマ指定したときのショット z。場面では絞らない。
	// 場面 z は場面ごとに上位数%しか通らないので、合う語の数は場面の数に比例し、場面の
	// 少ないテーマは語彙の数%しか合わなかった（推し活 12場面で 1〜3000位の145語）。
	// 場面 z の下限（1.0）を残しても、落ちる語の7割は良い語で誤爆を選んで落とせて
	// いなかったので、ショットだけで比べる（推し活 145→611語、2026-10-27）。
	ShotZShotFirst = 4.0
)

// ShotFirstTopics は場面が少なく、テーマ指定では場面で絞らずショットだけで比べるテーマ。
// 推し活・天気・伝統（8〜12場面）と家族（15場面。ショットだけで 183→623語）。
// 場面の多いテーマ（仕事・食べ物・BL）は増える語が少なく、誤爆（BL の性的な語など）が
// 目立つので入れない。おまかせはテーマを場面で決めるので対象外。
// 趣味・推し活は物語のショットで場面が増えたので外した。ショットだけだと綴りの一致
// （พัด→ฟาด、หลุมศพ→หลุม）が混ざった（趣味は半分ほど 2026-10-29、推し活は
// ショットだけで増える語の合わない率 10%、2026-10-30）。伝統も物語のショットで
// 場面で絞るほうが多く付くようになったので外した（46.8% 対 44.9%、2026-10-30）。
var ShotFirstTopics = map[string]bool{
	Topics[4]: true, Topics[8]: true,
}

// sceneZPinnedByTopic はテーマ指定の場面 z を SceneZPinned から変えるテーマ。
// 場面 z 1.5〜2.0 の帯で付くショットを Codex に判定させ、合わない率が 2.5 以上
// （8〜15%）と同じくらいのテーマはゆるめ、高いテーマは残した（恋愛・趣味・仕事 13〜17%、
// 推し活 7%、BL 35%）。合わないショットでも例文はほぼ崩れなかった（12語中1語が誤用、2026-10-30）。
var sceneZPinnedByTopic = map[string]float64{
	Topics[14]: 1.5, Topics[9]: 1.5, Topics[3]: 1.5, OshiTopic: 1.5, Topics[12]: 1.5,
	BLTopic: 2.5,
}

// SceneThresholds は topic の場面 z とショット z の閾値を返す。
// テーマ指定（minSceneZ == SceneZPinned）は ShotFirstTopics なら場面で絞らず（-Inf）、
// ほかは sceneZPinnedByTopic の値にする。
func SceneThresholds(topic string, minSceneZ float64) (sceneZ, shotZ float64) {
	if minSceneZ != SceneZPinned {
		return minSceneZ, ShotZ
	}
	if ShotFirstTopics[topic] {
		return math.Inf(-1), ShotZShotFirst
	}
	if z, ok := sceneZPinnedByTopic[topic]; ok {
		return z, ShotZ
	}
	return minSceneZ, ShotZ
}

// ScenePick は場面合致で選んだテーマ・場面・ショット。
type ScenePick struct {
	Topic  string
	Scene  string
	ShotID string
}

// SceneMatcher は語に合う場面を選ぶ。実装は themeshots.Builder。
type SceneMatcher interface {
	// PickScene は topics の場面のうち、場面 z ≥ minSceneZ で、場面内に
	// ショット z ≥ ShotZ の文があるものから、テーマ → 場面 → ショットの順に
	// 一様に選ぶ（閾値はテーマごとに SceneThresholds で決める）。合う場面が無ければ false。
	PickScene(word string, topics []string, minSceneZ float64) (ScenePick, bool)
	// HasScene は PickScene が選べる場面があるかだけを返す（抽選しない）。
	HasScene(word string, topics []string, minSceneZ float64) bool
}

// ErrNoTargetWords は UVM から 1 語も選べなかったとき
// （sentence_service.py:require_target_words:346 の RuntimeError）。
var ErrNoTargetWords = errors.New("No target words selected from UVM")

// TargetWord は選定した key_word と、その語に割り当てるテーマ。
//
// テーマを語ごとに持たせるのは、1回の選定で複数本まとめて作る（5本セット）
// ときに、セット全部が1テーマに揃わないようにするため。
type TargetWord struct {
	Word  string
	Topic string
	// Group は頼まれたのがまとめたテーマのときその値。Topic は中身の1つに
	// 解決済み。キャッシュを引くとき、Topic に無ければ Group の他の中身も見る。
	Group string
	// Matched は場面合致で選んだ語（premium）。ShotID が空ならショットを付けない。
	Matched bool
	ShotID  string
}

// SelectTargetWords はテーマを決めたうえで UVM からターゲット語を選ぶ
// （sentence_service.py:select_uvm_target_words + require_target_words）。
//
// count 本まとめて引ける。GetSessionWords はプールから外しながら引くので、
// 1回の呼び出しで返る語は重複しない。逆に呼び出しをまたぐ排他は無いので、
// セットを作るときは分けずにここで count 本を引くこと。
//
// テーマの決め方は ChooseTopic に従う。
//
//	テーマ指定あり : 指定値。全部の語が同じテーマ
//	free おまかせ  : 一様抽選で1つ。全部の語が同じテーマ
//	premium おまかせ: 枠ごとに一様抽選（重ならないように）。枠ごとにテーマ指定と同じ選び方
//
// premium（場面合致あり）はテーマに合う語を先に選ぶ。free は語をテーマで絞らない。
// premium おまかせは以前、語を先に選んで全テーマの場面からテーマを決めていたが、
// 参考文の多いテーマへ偏った（頻度上位5000語で BL 29%・テーマ無し 18%、
// 宗教・礼儀・学校・あいさつは各1%未満）。枠ごとにテーマを先に決めると、帯の未出
// 15語でも無作為テーマに合う語がある枠が 94%（旧の合う語 82%）だった（2026-10-30）。
func (s *TargetWordSelector) SelectTargetWords(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
	uid string, params map[string]any,
	maxVocab *int, count int, isPremium bool, estimatedVocab *int,
	testedVocab int,
) ([]TargetWord, error) {
	vocab := 0
	if estimatedVocab != nil {
		vocab = *estimatedVocab
	}
	choice := ChooseTopic(strParam(params, "topic"), isPremium, vocab, s.float64n, s.intn)

	req := uvm.SessionRequest{
		UID:            uid,
		Topic:          choice.Topic,
		Count:          count,
		MaxVocab:       maxVocab,
		TopicsPool:     choice.Pool,
		EstimatedVocab: estimatedVocab,
		TestedVocab:    testedVocab,
	}
	// free は従来どおり（テーマは一様抽選、場面は themeshots の z 重み）。
	matched := isPremium && s.Scenes != nil
	if matched {
		if choice.Topic != "" {
			allowed := pinnedTopics(choice.Topic)
			req.Prefer = func(w string) bool { return s.Scenes.HasScene(w, allowed, SceneZPinned) }
		} else {
			choice.Slots = s.omakaseTopics(choice.Pool, count)
			req.PreferEach = make([]func(string) bool, len(choice.Slots))
			for i, topic := range choice.Slots {
				allowed := []string{topic}
				req.PreferEach[i] = func(w string) bool { return s.Scenes.HasScene(w, allowed, SceneZPinned) }
			}
			req.SkipTopicMatch = true
		}
	}

	words, topic, err := s.Session.GetSessionWords(ctx, db, freqRank, req)
	if err != nil {
		return nil, err
	}
	if len(words) == 0 {
		return nil, ErrNoTargetWords
	}
	if matched {
		return s.assignScenes(words, choice), nil
	}

	out, err := assignTopics(ctx, words, topic, choice, s.Session.Emb)
	if err != nil {
		return nil, err
	}
	for i := range out {
		s.resolveGroup(&out[i])
	}
	return out, nil
}

// resolveGroup はまとめたテーマを、語に合う中身の個別テーマへ置き換える。
// まとめたテーマでなければ何もしない。
func (s *TargetWordSelector) resolveGroup(tw *TargetWord) {
	members := TopicGroups[tw.Topic]
	if len(members) == 0 {
		return
	}
	tw.Group = tw.Topic
	if s.Groups != nil {
		if t := s.Groups.ResolveGroup(tw.Group, tw.Word); t != "" {
			tw.Topic = t
			return
		}
	}
	tw.Topic = members[s.intn(len(members))]
}

// pinnedTopics は指定テーマの場面を探す範囲。まとめたテーマは中身すべて。
func pinnedTopics(topic string) []string {
	if members := TopicGroups[topic]; len(members) > 0 {
		return members
	}
	return []string{topic}
}

// assignScenes は premium の語ごとに場面合致でテーマとショットを決める。
//
//	テーマ指定 : 指定テーマ（まとめたテーマは中身）の場面から。合わなければ
//	             ショット無しで指定テーマのまま（まとめたテーマは中身から一様）。
//	             生成時にテーマのショットを雰囲気として付ける（BL を除く）
//	おまかせ   : 枠ごとのテーマ（choice.Slots）をテーマ指定と同じ扱いにする。
//	             枠の無い語（Slots が足りない）は Pool の場面から選び、合わなければ
//	             テーマも空にして LLM に候補から選ばせる
func (s *TargetWordSelector) assignScenes(words []string, choice TopicChoice) []TargetWord {
	out := make([]TargetWord, len(words))
	for i, w := range words {
		tw := TargetWord{Word: w, Topic: choice.Topic, Matched: true}
		topics, minZ := choice.Pool, SceneZOmakase
		if choice.Topic == "" && i < len(choice.Slots) {
			tw.Topic = choice.Slots[i]
			topics, minZ = []string{tw.Topic}, SceneZPinned
		} else if choice.Topic != "" {
			topics, minZ = pinnedTopics(choice.Topic), SceneZPinned
			if members := TopicGroups[choice.Topic]; len(members) > 0 {
				tw.Group = choice.Topic
				tw.Topic = members[s.intn(len(members))]
			}
		}
		if pick, ok := s.Scenes.PickScene(w, topics, minZ); ok {
			tw.Topic, tw.ShotID = pick.Topic, pick.ShotID
		}
		out[i] = tw
	}
	return out
}

// assignTopics は選定した語にテーマを割り当てる。
//
// テーマが選定前に確定していれば（テーマ指定あり / free おまかせ）全部そのテーマ。
// 確定していなければ（premium おまかせ）語ごとに embedding で決める。
// GetSessionWords が決めるのは 1 本目ぶんだけなので、2 本目以降をここで埋める。
func assignTopics(
	ctx context.Context, words []string, firstTopic string,
	choice TopicChoice, emb uvm.TopicEmbedder,
) ([]TargetWord, error) {
	out := make([]TargetWord, len(words))
	for i, w := range words {
		out[i] = TargetWord{Word: w, Topic: firstTopic}
	}
	if choice.Topic != "" || emb == nil {
		return out, nil
	}
	for i := 1; i < len(out); i++ {
		topic, err := emb.FindBestTopic(
			ctx, out[i].Word, choice.Pool, uvm.TopicMatchTopK, uvm.TopicMatchThreshold)
		if err != nil {
			return nil, err
		}
		// 閾値未達は "" のまま。LLM にテーマを委ねる（1 本目と同じ扱い）。
		out[i].Topic = topic
	}
	return out, nil
}

func (s *TargetWordSelector) float64n() float64 {
	if s.Rand != nil {
		return s.Rand.Float64()
	}
	return rand.Float64()
}

// omakaseTopics は premium おまかせの枠ごとのテーマ。pool から一様に、重ならない
// ように count 個選ぶ（pool より多ければ一巡してから重ねる）。
func (s *TargetWordSelector) omakaseTopics(pool []string, count int) []string {
	if len(pool) == 0 {
		pool = Topics
	}
	out := make([]string, 0, count)
	for len(out) < count {
		rest := append([]string(nil), pool...)
		for len(rest) > 0 && len(out) < count {
			i := s.intn(len(rest))
			out = append(out, rest[i])
			rest = append(rest[:i], rest[i+1:]...)
		}
	}
	return out
}

func (s *TargetWordSelector) intn(n int) int {
	if s.Rand != nil {
		return s.Rand.Intn(n)
	}
	return rand.Intn(n)
}
