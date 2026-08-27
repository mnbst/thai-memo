package userdata

import (
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// isNotFound は Firestore の NotFound を判定する。
// Go SDK の DocumentRef.Get は存在しない doc に対して NotFound エラーを返す
// （JS の get() が exists:false のスナップショットを返すのと違う）。
func isNotFound(err error) bool {
	return status.Code(err) == codes.NotFound
}
