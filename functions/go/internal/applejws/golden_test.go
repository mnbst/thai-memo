package applejws

import (
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
)

type appleJwsGolden struct {
	RootFingerprint string `json:"root_fingerprint"`
	Cases           []struct {
		Name                  string  `json:"name"`
		JWS                   string  `json:"jws"`
		OK                    bool    `json:"ok"`
		Error                 *string `json:"error"`
		NotificationType      *string `json:"notification_type"`
		Subtype               *string `json:"subtype"`
		OriginalTransactionID *string `json:"original_transaction_id"`
		ExpiresDate           *int64  `json:"expires_date"`
		AutoRenewStatus       *int    `json:"auto_renew_status"`
		HasRenewalInfo        bool    `json:"has_renewal_info"`
	} `json:"cases"`
}

// TestVerifyGolden は JS 実装（appStoreServer.ts:verifyAppleJwsSignature）と
// 同じ JWS に対して同じ判定を下すことを確かめる。
//
// golden は本物の JS 実装に実際の JWS を通して作っている
// （scripts/genAppleJwsGolden.ts）。証明書チェーンとルート CA のピン留めは
// 偽装通知を弾く最後の砦なので、通す/弾くの境界をここで固定する。
func TestVerifyGolden(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/apple_jws_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden appleJwsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	if len(golden.Cases) == 0 {
		t.Fatal("golden が空")
	}

	// golden はテスト用ルート CA で作られているので、ピン留め先を差し替える。
	v := &Verifier{RootFingerprint: golden.RootFingerprint}

	var accepted, rejected int
	for _, c := range golden.Cases {
		t.Run(c.Name, func(t *testing.T) {
			err := v.Verify(c.JWS)

			if !c.OK {
				rejected++
				if err == nil {
					t.Fatalf("JS は弾いた（%s）のに Go は通した", *c.Error)
				}
				// 文言まで揃えている（JS と同じ判断理由で弾いているかを見る）
				if !sameRejectReason(*c.Error, err.Error()) {
					t.Errorf("弾いた理由が違う\n  JS = %s\n  Go = %s", *c.Error, err)
				}
				return
			}

			accepted++
			if err != nil {
				t.Fatalf("JS は通したのに Go は弾いた: %v", err)
			}

			var notification struct {
				NotificationType string `json:"notificationType"`
				Subtype          string `json:"subtype"`
				Data             struct {
					SignedTransactionInfo string `json:"signedTransactionInfo"`
					SignedRenewalInfo     string `json:"signedRenewalInfo"`
				} `json:"data"`
			}
			if err := DecodePayload(c.JWS, &notification); err != nil {
				t.Fatal(err)
			}
			if notification.NotificationType != *c.NotificationType {
				t.Errorf("notificationType: want %s, got %s",
					*c.NotificationType, notification.NotificationType)
			}
			wantSubtype := ""
			if c.Subtype != nil {
				wantSubtype = *c.Subtype
			}
			if notification.Subtype != wantSubtype {
				t.Errorf("subtype: want %q, got %q", wantSubtype, notification.Subtype)
			}

			var tx struct {
				OriginalTransactionID string `json:"originalTransactionId"`
				ExpiresDate           *int64 `json:"expiresDate"`
			}
			if err := DecodePayload(notification.Data.SignedTransactionInfo, &tx); err != nil {
				t.Fatal(err)
			}
			if tx.OriginalTransactionID != *c.OriginalTransactionID {
				t.Errorf("originalTransactionId: want %s, got %s",
					*c.OriginalTransactionID, tx.OriginalTransactionID)
			}
			switch {
			case c.ExpiresDate == nil && tx.ExpiresDate != nil:
				t.Errorf("expiresDate: JS は無し、Go は %d", *tx.ExpiresDate)
			case c.ExpiresDate != nil && tx.ExpiresDate == nil:
				t.Errorf("expiresDate: JS は %d、Go は無し", *c.ExpiresDate)
			case c.ExpiresDate != nil && *c.ExpiresDate != *tx.ExpiresDate:
				t.Errorf("expiresDate: want %d, got %d", *c.ExpiresDate, *tx.ExpiresDate)
			}

			hasRenewal := notification.Data.SignedRenewalInfo != ""
			if hasRenewal != c.HasRenewalInfo {
				t.Errorf("renewalInfo の有無: want %v, got %v", c.HasRenewalInfo, hasRenewal)
			}
			if hasRenewal {
				var renewal struct {
					AutoRenewStatus int `json:"autoRenewStatus"`
				}
				if err := DecodePayload(notification.Data.SignedRenewalInfo, &renewal); err != nil {
					t.Fatal(err)
				}
				if renewal.AutoRenewStatus != *c.AutoRenewStatus {
					t.Errorf("autoRenewStatus: want %d, got %d",
						*c.AutoRenewStatus, renewal.AutoRenewStatus)
				}
			}
		})
	}

	t.Logf("%d ケース一致（通した %d / 弾いた %d）", len(golden.Cases), accepted, rejected)
	if accepted == 0 || rejected == 0 {
		t.Error("通すケースか弾くケースのどちらかが無い。golden が退化している")
	}
}

// sameRejectReason は JS と Go の拒否理由が同じ分類かを見る。
// jose のメッセージ（signature verification failed）だけは文言が違うので対応付ける。
func sameRejectReason(jsMsg, goMsg string) bool {
	markers := []string{
		"Invalid JWS format",
		"Missing or incomplete x5c certificate chain",
		"Non-CA certificate used as issuer at index",
		"Certificate chain verification failed at index",
		"Untrusted root CA fingerprint",
	}
	for _, m := range markers {
		if strings.Contains(jsMsg, m) {
			return strings.Contains(goMsg, m)
		}
	}
	if strings.Contains(jsMsg, "signature verification failed") {
		return strings.Contains(goMsg, "署名検証に失敗")
	}
	return false
}

// TestVerifyRejectsWithProductionPinning は、golden と同じ「正当な」JWS でも
// 本番のピン留め（Apple Root CA G3）では弾かれることを確かめる。
//
// テスト用ルートは Subject が "Apple Root CA - G3" なだけの自己署名証明書。
// ピン留めがフィンガープリントで効いていなければここが通ってしまう。
func TestVerifyRejectsWithProductionPinning(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/apple_jws_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden appleJwsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}

	if golden.RootFingerprint == AppleRootCAG3Fingerprint {
		t.Fatal("テスト用ルートが本番のフィンガープリントと一致している")
	}

	var checked int
	for _, c := range golden.Cases {
		if !c.OK {
			continue
		}
		checked++
		err := DefaultVerifier.Verify(c.JWS)
		if err == nil {
			t.Errorf("%s: テスト用の偽ルート CA が本番ピン留めを通過した", c.Name)
			continue
		}
		if !strings.Contains(err.Error(), "Untrusted root CA fingerprint") {
			t.Errorf("%s: 弾いた理由が想定と違う: %v", c.Name, err)
		}
	}
	if checked == 0 {
		t.Fatal("正当ケースが1件も無い")
	}
	t.Logf("正当な %d ケースすべてが本番ピン留めでは拒否された", checked)
}

// TestVerifyRejectsNonCAIssuer は中間CA偽装を弾くことを確かめる。
//
// golden の「非CA証明書を中間CAとして持ち込む」ケースは、隣接署名が全て正当で
// ルートのフィンガープリントも一致する。つまり**署名の検証だけでは通ってしまう**。
// basicConstraints を見ているからこそ弾ける、という関係をここで固定する。
//
// 攻撃の現実味: Apple の開発者向け配布証明書は WWDR が発行し、秘密鍵は開発者
// 本人が持つ。それを中間CAの位置に置けば、誰でも偽の通知に署名できてしまう。
func TestVerifyRejectsNonCAIssuer(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/apple_jws_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden appleJwsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}

	var jws string
	for _, c := range golden.Cases {
		if c.Name == "非CA証明書を中間CAとして持ち込む" {
			jws = c.JWS
			break
		}
	}
	if jws == "" {
		t.Fatal("golden に攻撃ケースが無い")
	}

	v := &Verifier{RootFingerprint: golden.RootFingerprint}

	// 弾くこと。理由は CA 判定であること（たまたま別の理由で落ちていては意味がない）
	err = v.Verify(jws)
	if err == nil {
		t.Fatal("中間CA偽装が通過した")
	}
	if !strings.Contains(err.Error(), "Non-CA certificate used as issuer") {
		t.Errorf("CA 判定以外の理由で弾いている: %v", err)
	}

	// 監視のためにエラー種別を判別できること
	var rejected *RejectedError
	if !errors.As(err, &rejected) {
		t.Errorf("*RejectedError で返っていない: %T", err)
	}

	// このチェーンは署名の検証だけなら通る、という前提を明示しておく。
	// ここが false になったら攻撃ケースが退化している。
	if err := signatureOnlyVerify(t, jws, golden.RootFingerprint); err != nil {
		t.Errorf("攻撃ケースが退化している。署名だけでも弾けてしまう: %v", err)
	}
}

// signatureOnlyVerify は CA 判定を入れる前の検証（隣接署名 + ルートのピン留め）。
// 攻撃ケースがその範囲では防げないことを示すためだけに使う。
func signatureOnlyVerify(t *testing.T, signedPayload, rootFingerprint string) error {
	t.Helper()

	parts := strings.Split(signedPayload, ".")
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return err
	}
	var header struct {
		X5C []string `json:"x5c"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return err
	}

	var certs []*x509.Certificate
	for _, b64 := range header.X5C {
		der, err := base64.StdEncoding.DecodeString(b64)
		if err != nil {
			return err
		}
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			return err
		}
		certs = append(certs, cert)
	}

	for i := 0; i < len(certs)-1; i++ {
		if err := certs[i+1].CheckSignature(
			certs[i].SignatureAlgorithm, certs[i].RawTBSCertificate, certs[i].Signature,
		); err != nil {
			return fmt.Errorf("隣接署名 [%d] が不正: %w", i, err)
		}
	}
	if got := Fingerprint256(certs[len(certs)-1].Raw); got != rootFingerprint {
		return fmt.Errorf("ルート不一致: %s", got)
	}
	return nil
}
