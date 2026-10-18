package embeddings

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"strings"
	"testing"
)

// testNPY は float32 の2次元 .npy を作る。
func testNPY(rows [][]float32) []byte {
	header := fmt.Sprintf("{'descr': '<f4', 'fortran_order': False, 'shape': (%d, %d), }", len(rows), len(rows[0]))
	header += strings.Repeat(" ", 63-(10+len(header))%64) + "\n"
	var b bytes.Buffer
	b.WriteString("\x93NUMPY\x01\x00")
	binary.Write(&b, binary.LittleEndian, uint16(len(header)))
	b.WriteString(header)
	for _, r := range rows {
		binary.Write(&b, binary.LittleEndian, r)
	}
	return b.Bytes()
}

// ショットの embedding は .npy の行と本文の配列を同じ並びで対応させる。
func TestParseShotEmbeddings(t *testing.T) {
	npy := testNPY([][]float32{{1, 0}, {0, 1}})

	got, err := parseShotEmbeddings(npy, []byte(`["ก","ข"]`))
	if err != nil {
		t.Fatal(err)
	}
	if got["ก"][0] != 1 || got["ข"][1] != 1 {
		t.Errorf("行と本文の対応がずれている: %v", got)
	}

	if _, err := parseShotEmbeddings(npy, []byte(`["ก"]`)); err == nil {
		t.Error("件数が合わないのに通った")
	}
}
