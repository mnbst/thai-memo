package sentence

import (
	"context"
	"log"
	"math/rand"
)

// SubThemeFinder はテーマのサブテーマを 1 つ選ぶ。
// 実装は internal/embeddings.Store。
type SubThemeFinder interface {
	FindBestSubTheme(ctx context.Context, word string, subThemes []string) (string, error)
}

// Resolver は生成パラメータのうち、抽選や embedding が要る部分を確定する。
//
// 確定した値だけを BuildPrompt へ渡すことで、組み立て側を決定的に保つ。
type Resolver struct {
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand
	// SubThemes は nil ならサブテーマを選ばない（プロンプトに行が出ない）。
	SubThemes SubThemeFinder
}

func (r *Resolver) choice(items []string) string {
	if len(items) == 0 {
		return ""
	}
	if r.Rand != nil {
		return items[r.Rand.Intn(len(items))]
	}
	return items[rand.Intn(len(items))]
}

// DrawRelation は地位×親密度×話し手の性別を1つずつ引いて
// 「地位／親密度／性別」の形で返す。
func (r *Resolver) DrawRelation() string {
	return r.choice(relationStatuses) + "／" + r.choice(relationIntimacy) +
		"／" + r.choice(relationSpeakers)
}

// DrawMedium は Media を重み付きで1つ引く。
func (r *Resolver) DrawMedium() string {
	total := 0
	for _, m := range Media {
		total += m.Weight
	}
	var n int
	if r.Rand != nil {
		n = r.Rand.Intn(total)
	} else {
		n = rand.Intn(total)
	}
	for _, m := range Media {
		if n < m.Weight {
			return m.Name
		}
		n -= m.Weight
	}
	return Media[0].Name
}

// Resolve は例文生成パラメータを確定する。
//
// クライアント指定値を優先し、未指定ならティアに応じた候補からランダム選択する。
// 自動選択時は estimatedVocab に応じて topic の候補プールを絞る。
//
// topic だけは未指定でも埋めず "" のまま返す。候補は TopicOptions に入るので、
// 呼び出し側がプロンプトに列挙して LLM に選ばせる（2026-08-06。find_best_topic が
// 閾値未達で諦めた場合もここを空で通し、レベル別ゲートは候補側で効かせる）。
// prompts.py:resolve_generation_params:916 の移植。
func (r *Resolver) Resolve(
	ctx context.Context, params map[string]any,
	targetWords []string, estimatedVocab int,
) ResolvedParams {
	resolved := ResolvedParams{
		// 2026-08-14: free 専用プール（FREE_TOPICS）は廃止。クライアントは
		// テーマを送らないので、tier でプールを分けても選択肢の差にならなかった。
		TopicOptions: GateTopicsForVocab(append([]string(nil), Topics...), estimatedVocab),
		Topic:        strParam(params, "topic"),
	}

	// 2026-08-05 追加の軸。「いつのことを言うか」を決める。一様に引くと
	// key_word と衝突する（พรุ่งนี้ に過去の時点）ので、語が自然に置ける時点から引く。
	resolved.TimeFrame = strParam(params, "timeFrame")
	if resolved.TimeFrame == "" {
		resolved.TimeFrame = r.choice(TimeFrameCandidates(targetWords))
	}

	// 話し手と聞き手の関係。key_word ともテーマとも衝突しない直交軸
	// （2026-08-22 追加）。
	resolved.Relation = strParam(params, "relation")
	if resolved.Relation == "" {
		resolved.Relation = r.DrawRelation()
	}

	// 文が載る媒体（2026-10-07 追加）。書き言葉の文体はここからしか出ない。
	resolved.Medium = strParam(params, "medium")
	if resolved.Medium == "" {
		resolved.Medium = r.DrawMedium()
	}

	subThemes := topicSubThemes[resolved.Topic]
	if len(subThemes) > 0 && len(targetWords) > 0 && r.SubThemes != nil {
		sub, err := r.SubThemes.FindBestSubTheme(ctx, targetWords[0], subThemes)
		if err != nil {
			// サブテーマは無くても文は作れる。embedding の失敗で生成を止めない。
			log.Printf("sub_theme の選出に失敗: %v", err)
		} else {
			resolved.SubTheme = sub
		}
	}

	return resolved
}

// strParam は params[key] を文字列で取り出す。Python の
// params.get(key) or "" と同じ。
//
// 前後の空白は落とさない（Python 版もそのままプロンプトへ入れる）。
// 文字列以外は空扱いにする。Python はそのまま通すが、クライアントは
// これらのパラメータを送らないので実入力には現れない。
func strParam(params map[string]any, key string) string {
	s, _ := params[key].(string)
	return s
}
