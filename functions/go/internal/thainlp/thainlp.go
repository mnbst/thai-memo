package thainlp

import "errors"

// errSplitTr は Python 側で seg.split('<tr/>') が2要素に割れないときの
// ValueError に対応する。gen_golden はこれを {"__error__": true} と記録する。
var errSplitTr = errors.New("thainlp: <tr/> が見つからない")

// ErrNotImplemented は未移植の API が返す。nlpdump はこれを受けたら
// golden の {"__error__": true} と同じ扱いにせず、行そのものを出力しない
// （欠落として verify.py に検出させ、進捗が誤魔化されないようにする）。
var ErrNotImplemented = errors.New("thainlp: not implemented")

// ---------------------------------------------------------------------------
// tier1 — 呼び出し側が依存する公開API。
// Python 側の対応:
//   ThaiToPronunciation -> pronunciation.thai_to_pronunciation
//   SegmentSyllables    -> nlp.segment_syllables
//   POSJapanese         -> nlp.get_pos_japanese
//   TokenizeWords       -> word_gap._tokenize_words
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// tier2 — 不一致の原因切り分け用プリミティブ。
// ---------------------------------------------------------------------------
