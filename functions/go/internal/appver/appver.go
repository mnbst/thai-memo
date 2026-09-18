// Package appver はクライアントのアプリ版による機能出し分けを扱う。
//
// app_build_number は使えない。pubspec のビルド番号は 0 固定で、実際の番号は
// CI が --build-number=${{ github.run_number }} で注入しており、tester と prod で
// ワークフローが別＝採番系列が独立しているため大小がリリース順序を表さない。
// 判定には users/{uid} の app_version（"1.4.11" 形式）を使う。
package appver

import (
	"strconv"
	"strings"
)

// Compare は "1.4.8" 形式を major/minor/patch の順に比較する。
// パースできない値は最小扱い（-1）にして安全側へ倒す。
func Compare(version string, other [3]int) int {
	parts := strings.SplitN(strings.TrimSpace(version), ".", 4)
	if len(parts) != 3 {
		return -1
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return -1
		}
		if n != other[i] {
			if n < other[i] {
				return -1
			}
			return 1
		}
	}
	return 0
}

// AtLeast は users doc の app_version が min 以上かを返す。
// 版が読めない（記録前・旧版）ときは false。
func AtLeast(userData map[string]any, min [3]int) bool {
	version, _ := userData["app_version"].(string)
	return Compare(version, min) >= 0
}
