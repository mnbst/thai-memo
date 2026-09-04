package callable

import (
	"encoding/json"
	"math"
	"strconv"
)

// Int は callable の data に載る整数を読む。
//
// Flutter（iOS/Android）の Firebase SDK は Dart の int を素の JSON 数値では
// なく、callable プロトコルの Int64 ラッパーに包んで送る:
//
//	{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"3"}
//
// Go の構造体に int で受けると "cannot unmarshal object into ... of type int"
// で落ちるので、数値・文字列・このラッパーのどれでも読めるようにする。
// JS SDK は素の数値を送るため、両方を受ける必要がある。
func Int(v any) (int, bool) {
	switch n := v.(type) {
	case float64:
		if math.IsNaN(n) || math.IsInf(n, 0) {
			return 0, false
		}
		return int(n), true
	case int:
		return n, true
	case int64:
		return int(n), true
	case json.Number:
		if i, err := n.Int64(); err == nil {
			return int(i), true
		}
	case string:
		if i, err := strconv.ParseInt(n, 10, 64); err == nil {
			return int(i), true
		}
	case bool:
		// Python 版は bool を int のサブクラスとして受けていた（True→1）。
		if n {
			return 1, true
		}
		return 0, true
	case map[string]any:
		// ラッパーは value に文字列で数値が入る。@type は見ない
		// （Int64Value / UInt64Value のどちらでも同じ形）。
		if inner, ok := n["value"]; ok {
			return Int(inner)
		}
	}
	return 0, false
}
