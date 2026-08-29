package sentence

import (
	"context"
	"errors"
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
}

// ChooseTopic は語彙レベルに応じたテーマ候補を作り、free では 1 つに決める
// （sentence_service.py:select_uvm_target_words:294 の前半）。
//
// 候補プールは free / premium 共通（TOPICS を TOPIC_MIN_VOCAB でゲート）。
// 違うのは選び方だけで、free は一様抽選、premium は embedding で key_word に
// 最も近いテーマを選ぶ。
//
// 2026-08-14 実測: free の旧プール4件で find_best_topic を使うと BLドラマが
// 82.7%。テーマ embedding は語彙全体への平均類似度に差があり、重心の高い BL が
// 全語で argmax になる。BL は刺さる層には強いが大半には刺さらないので、
// free は分布を均等にする。
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
		if t != BLTopic {
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

// TargetWordSelector はターゲット語の選定に必要な依存をまとめる。
type TargetWordSelector struct {
	// Session は uvm 側の選定。Rand と Emb はここで注入する。
	Session *uvm.SessionSelector
	// Rand はテーマ抽選に使う。nil なら共有の乱数源。
	Rand *rand.Rand
}

// ErrNoTargetWords は UVM から 1 語も選べなかったとき
// （sentence_service.py:require_target_words:346 の RuntimeError）。
var ErrNoTargetWords = errors.New("No target words selected from UVM")

// SelectTargetWords はテーマを決めたうえで UVM からターゲット語を選ぶ
// （sentence_service.py:select_uvm_target_words + require_target_words）。
//
// key_word 先行方式: 帯域内から key_word を選出し、embedding で最適テーマを
// 決める。テーマが明示指定されていればそのまま使う。
func (s *TargetWordSelector) SelectTargetWords(
	ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
	uid string, params map[string]any,
	maxVocab *int, count int, isPremium bool, estimatedVocab *int,
) ([]string, string, error) {
	vocab := 0
	if estimatedVocab != nil {
		vocab = *estimatedVocab
	}
	choice := ChooseTopic(strParam(params, "topic"), isPremium, vocab, s.float64n, s.intn)

	words, topic, err := s.Session.GetSessionWords(ctx, db, freqRank, uvm.SessionRequest{
		UID:            uid,
		Topic:          choice.Topic,
		Count:          count,
		MaxVocab:       maxVocab,
		TopicsPool:     choice.Pool,
		EstimatedVocab: estimatedVocab,
	})
	if err != nil {
		return nil, "", err
	}
	if len(words) == 0 {
		return nil, "", ErrNoTargetWords
	}
	return words, topic, nil
}

func (s *TargetWordSelector) float64n() float64 {
	if s.Rand != nil {
		return s.Rand.Float64()
	}
	return rand.Float64()
}

func (s *TargetWordSelector) intn(n int) int {
	if s.Rand != nil {
		return s.Rand.Intn(n)
	}
	return rand.Intn(n)
}
