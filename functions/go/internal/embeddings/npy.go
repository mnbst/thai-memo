package embeddings

import (
	"encoding/binary"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// parseNPY は numpy の .npy（float32・C order・2次元）を読む。
//
// 形式は単純で、マジック \x93NUMPY + バージョン2バイト + ヘッダ長 +
// Python の dict リテラル（dtype / fortran_order / shape）+ 生データ。
// numpy を持ち込む代わりにここで直接読む。
func parseNPY(raw []byte) ([][]float32, error) {
	const magic = "\x93NUMPY"
	if len(raw) < 10 || string(raw[:6]) != magic {
		return nil, fmt.Errorf("npy のマジックが不正")
	}

	major := raw[6]
	var headerLen int
	var offset int
	switch major {
	case 1:
		headerLen = int(binary.LittleEndian.Uint16(raw[8:10]))
		offset = 10
	case 2, 3:
		headerLen = int(binary.LittleEndian.Uint32(raw[8:12]))
		offset = 12
	default:
		return nil, fmt.Errorf("npy のバージョンが不明: %d", major)
	}

	if offset+headerLen > len(raw) {
		return nil, fmt.Errorf("npy のヘッダが切れている")
	}
	header := string(raw[offset : offset+headerLen])
	body := raw[offset+headerLen:]

	descr, err := headerValue(header, "descr")
	if err != nil {
		return nil, err
	}
	// float32 リトルエンディアンのみ対応（生成側が固定）。
	if descr != "<f4" {
		return nil, fmt.Errorf("npy の dtype が想定外: %s（<f4 のみ対応）", descr)
	}

	fortran, err := headerValue(header, "fortran_order")
	if err != nil {
		return nil, err
	}
	if fortran != "False" {
		return nil, fmt.Errorf("npy が fortran order。C order のみ対応")
	}

	rows, cols, err := parseShape(header)
	if err != nil {
		return nil, err
	}

	want := rows * cols * 4
	if len(body) < want {
		return nil, fmt.Errorf("npy の本体が短い: %d < %d", len(body), want)
	}

	out := make([][]float32, rows)
	// 行ごとに切り出す。1本の連続領域から参照させて割り当てを減らす。
	flat := make([]float32, rows*cols)
	for i := range flat {
		flat[i] = math.Float32frombits(
			binary.LittleEndian.Uint32(body[i*4 : i*4+4]))
	}
	for r := range rows {
		out[r] = flat[r*cols : (r+1)*cols]
	}
	return out, nil
}

var reHeaderValue = regexp.MustCompile(`'(\w+)':\s*'?([^',}]+)'?`)

func headerValue(header, key string) (string, error) {
	for _, m := range reHeaderValue.FindAllStringSubmatch(header, -1) {
		if m[1] == key {
			return strings.TrimSpace(m[2]), nil
		}
	}
	return "", fmt.Errorf("npy ヘッダに %s が無い", key)
}

var reShape = regexp.MustCompile(`'shape':\s*\((\d+)\s*,\s*(\d+)\s*\)`)

func parseShape(header string) (rows, cols int, err error) {
	m := reShape.FindStringSubmatch(header)
	if m == nil {
		return 0, 0, fmt.Errorf("npy の shape が2次元でない: %s", header)
	}
	rows, err = strconv.Atoi(m[1])
	if err != nil {
		return 0, 0, err
	}
	cols, err = strconv.Atoi(m[2])
	if err != nil {
		return 0, 0, err
	}
	return rows, cols, nil
}
