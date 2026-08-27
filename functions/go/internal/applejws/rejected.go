package applejws

// RejectedError は署名検証で通知を弾いたことを表す。
//
// App Store の通知ハンドラは Apple のリトライを避けるため、検証に失敗しても
// HTTP 200 を返す。つまり「偽装通知を弾いた」も「本物の通知を誤って弾いた」も
// 応答からは区別できない。後者は課金状態が一切更新されなくなる障害なので、
// 呼び出し側がこの型を見て専用のログを出し、監視できるようにしている。
type RejectedError struct {
	Err error
}

func (e *RejectedError) Error() string { return e.Err.Error() }
func (e *RejectedError) Unwrap() error { return e.Err }
