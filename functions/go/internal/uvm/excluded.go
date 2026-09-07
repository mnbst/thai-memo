package uvm

// key_word から外す語。
//
// 単独では古語・方言・専門用語の用法しか無い語が key_word に当たると、
// 【最優先】ターゲット語必須がその1文を丸ごと壊す。プロンプト側には
// 「文語・古語の用法しかないなら文脈ごと変える」ルールがあるが、
// 語自体が古語専用なら文脈を変えても逃げ場が無いので出題側で外す。
//
// 旧実装（functions/python の build_non_vocab_dict.py + non_vocab.py）は
// Go へ未移植のまま消えた。ここはその代替で、実測で破綻した語だけを持つ。
// 予防的に語を足さないこと（台帳「予防的ルール」）。
//
// 複合語（เจ้าของ / เจ้านาย）は別トークンなので出題は残る。
var excludedTargetWords = map[string]bool{
	// 2026-08-26: ×เจ้าฝนตกแล้ว。古語・方言の二人称／「主」。
	"เจ้า": true,
	// 2026-08-26: 古語の一人称。เจ้า と同じ理由。
	"ข้า": true,
	// 2026-09-06: ×เตะเข้าเป้าดังวาเลย。長さの単位（約2m）で、
	// 会話文では単独で使いようがなく擬音として捏造された。
	"วา": true,
}

// IsExcludedTargetWord は key_word にしてはいけない語かを返す。
func IsExcludedTargetWord(word string) bool {
	return excludedTargetWords[word]
}
