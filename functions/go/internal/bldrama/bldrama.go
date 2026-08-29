// Package bldrama は BL ドラマ回の専用プロンプトブロックを組み立てる。
// functions/python/themes/bl_drama.py の移植。
//
// 参考セリフは意図的に1文だけ渡す。複数渡すと単語を混ぜて合成した
// 非文が生成されるため、混成の余地を構造的に無くしている。
package bldrama

import (
	"context"
	"log"
	"math/rand"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// ShotContext はショットが属するドラマ設定とシーン。
type ShotContext struct {
	Drama   string
	Context string
	Scene   string
}

// ShotFinder は単語に最も近いセリフを選ぶ。実装は internal/embeddings.Store。
type ShotFinder interface {
	FindBestDramaShot(ctx context.Context, word string, shots []embeddings.Shot) (string, error)
}

// Builder は BL ドラマ回のプロンプト断片を作る。
type Builder struct {
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand
	// Shots は nil ならランダム選出だけになる。
	Shots ShotFinder
	// Ctx は embedding の取得に使う。nil なら context.Background()。
	Ctx context.Context
}

// PickShot は参考にするセリフを1つ選び、そのショットIDを返す。
//
// ターゲット単語があれば embedding 類似度で全セリフから選出する。
// 単語が無い / embedding が引けない場合はランダム。
func (b *Builder) PickShot(targetWords []string) string {
	if len(targetWords) > 0 && b.Shots != nil {
		// 候補は shotIDs の順で渡す。同点のときに選ばれるセリフを
		// Python（dict の挿入順）と揃えるため。
		all := make([]embeddings.Shot, 0, len(shotIDs))
		for _, sid := range shotIDs {
			all = append(all, embeddings.Shot{ID: sid, Text: shots[sid]})
		}
		shotID, err := b.Shots.FindBestDramaShot(b.ctx(), targetWords[0], all)
		if err != nil {
			// セリフの選出に失敗しても回はドラマのまま。ランダムへ縮退させる。
			log.Printf("drama shot の選出に失敗: %v", err)
		} else if shotID != "" {
			return shotID
		}
	}
	return shotIDs[b.intn(len(shotIDs))]
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

// BuildDramaSection は BL ドラマ用のプロンプト断片を返す。
func (b *Builder) BuildDramaSection(targetWords []string) sentence.DramaSection {
	shotID := b.PickShot(targetWords)
	pick := shotContext[shotID]
	shotText := shots[shotID]

	contextLines := []string{
		"BLドラマ（男性同士）。セリフをそのまま引用せず雰囲気を参考にすること",
		"ドラマの設定: " + pick.Context,
		"場面: " + pick.Scene,
		"参考タイ語例（雰囲気・口語感の参考。この1文のみ）: " + shotText,
		"usage_scenariosにはどんな場面かわかる説明を書くこと",
	}

	requiredLines := []string{
		"話し手・聞き手の人称代名詞は参考タイ語例と同じ丁寧度で統一すること。" +
			"参考例でกู/มึงが使われていればthai_textでもกู/มึงを使う。ฉัน/คุณ/ผมへの置き換え禁止",
		"相手の呼び方（二人称）も参考タイ語例に合わせること。" +
			"参考例でพี่/เฮียなどが使われていればคุณに置き換えない",
		"参考タイ語例の雰囲気・構文を参考にオリジナルのタイ語文を作ること。" +
			"単語を部分的に差し替えて別の意味の語を作らない（例: ช่วยดูแล を ช่วยดู にするなど）",
	}

	return sentence.DramaSection{
		Context:  bulletList(contextLines),
		Required: bulletList(requiredLines),
	}
}

func bulletList(lines []string) string {
	var b strings.Builder
	for _, line := range lines {
		b.WriteString("- ")
		b.WriteString(line)
		b.WriteString("\n")
	}
	return b.String()
}
