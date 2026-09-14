package sentence

import "strings"

// BuildRetryConstraint は差し戻し用の【前回の問題点】ブロックを返す。
// notes が空なら空文字。
//
// notes は quality.Verdict.Reason を想定する。judge は「どの語・どの箇所か」を
// 名指しするので、前回のタイ語文そのものを渡さなくても何を直すかは伝わる。
//
// 前回の文を載せないのは意図的。プロンプト中のタイ語は、それが×例であっても
// 生成側が写す。載せると「直せ」ではなく「これに似せろ」として効く。
//
// 配置は末尾。レジスタ制約を system prompt から末尾へ移したときと同じ理由で、
// 末尾に置いたものだけが守られる。
func BuildRetryConstraint(notes []string) string {
	cleaned := make([]string, 0, len(notes))
	for _, n := range notes {
		if n = strings.TrimSpace(n); n != "" {
			cleaned = append(cleaned, n)
		}
	}
	if len(cleaned) == 0 {
		return ""
	}
	return "【やり直し】前回の生成は次の指摘を受けた。同じ失敗を繰り返さない。\n" +
		numberedRules(cleaned) +
		"\n\n指摘された箇所を避けたうえで、条件を満たす別の文を作る。" +
		"指摘を避けるために語順・語彙を不自然にしない。"
}

// SubThemesFor はテーマのサブテーマ候補を返す。該当が無ければ nil。
//
// コーパス生成のバッチが (語, テーマ) の組ごとにサブテーマを引くために要る。
// topicSubThemes は自動生成データなので、コピーを持たせず参照だけ開ける。
func SubThemesFor(topic string) []string {
	subs := topicSubThemes[topic]
	if len(subs) == 0 {
		return nil
	}
	return append([]string(nil), subs...)
}
