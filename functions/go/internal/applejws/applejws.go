// Package applejws は Apple の JWS（App Store Server API / Server Notifications V2）を
// 署名検証・デコードする。
// functions/javascript/src/services/appStoreServer.ts の署名検証部分の移植。
//
// Apple は本文を JWS compact 形式（ES256）で返し、署名鍵の証明書チェーンを
// ヘッダの x5c に載せてくる。チェーンのルートが Apple Root CA G3 であることを
// フィンガープリントで固定し、リーフ証明書の公開鍵で署名を確認する。
package applejws

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
)

// AppleRootCAG3Fingerprint は Apple Root CA G3 の SHA-256 フィンガープリント
// （証明書ピン留め用）。
// https://www.apple.com/certificateauthority/ の公式ルート証明書に基づく。
// **appStoreServer.ts の _appleRootCaG3Fingerprint と必ず一致させること。**
const AppleRootCAG3Fingerprint = "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79"

// ErrInvalidFormat は JWS が3パートでない場合。
var ErrInvalidFormat = errors.New("Invalid JWS format")

// Verifier は署名検証に使うルート証明書のフィンガープリントを保持する。
// テストで差し替えられるよう構造体にしている（JS の
// setAppleRootCaFingerprintForTest 相当）。
type Verifier struct {
	// RootFingerprint が空なら AppleRootCAG3Fingerprint を使う。
	RootFingerprint string
}

// DefaultVerifier は本番用（Apple Root CA G3 に固定）。
var DefaultVerifier = &Verifier{}

func (v *Verifier) rootFingerprint() string {
	if v.RootFingerprint == "" {
		return AppleRootCAG3Fingerprint
	}
	return v.RootFingerprint
}

// Verify は x5c の証明書チェーンを検証し、リーフ証明書の公開鍵で
// JWS 署名を確認する。
//
// 検証内容:
//  1. 発行者の位置に立つ証明書が CA であること（basicConstraints）
//  2. x5c チェーン内の各証明書が次の証明書で署名されていること
//  3. ルート証明書のフィンガープリントが Apple Root CA G3 と一致すること
//  4. リーフ証明書の公開鍵で JWS 署名が正当であること
//
// 返すエラーは *RejectedError なので、呼び出し側は errors.As で
// 「署名検証で弾いた」ことを判別できる（監視のため）。
func (v *Verifier) Verify(signedPayload string) error {
	if err := v.verify(signedPayload); err != nil {
		return &RejectedError{Err: err}
	}
	return nil
}

// verify は実際の検証。返すエラーは Verify が *RejectedError に包む。
func (v *Verifier) verify(signedPayload string) error {
	parts := strings.Split(signedPayload, ".")
	if len(parts) != 3 {
		return ErrInvalidFormat
	}

	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return fmt.Errorf("JWS ヘッダのデコードに失敗: %w", err)
	}
	var header struct {
		X5C []string `json:"x5c"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return fmt.Errorf("JWS ヘッダのパースに失敗: %w", err)
	}
	if len(header.X5C) < 2 {
		return errors.New("Missing or incomplete x5c certificate chain in JWS header")
	}

	certs := make([]*x509.Certificate, 0, len(header.X5C))
	for i, b64 := range header.X5C {
		der, err := base64.StdEncoding.DecodeString(b64)
		if err != nil {
			return fmt.Errorf("x5c[%d] の base64 デコードに失敗: %w", i, err)
		}
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			return fmt.Errorf("x5c[%d] の証明書パースに失敗: %w", i, err)
		}
		certs = append(certs, cert)
	}

	// 発行者の位置に立つ証明書が CA であることを確認する。
	//
	// 署名の数学的な正しさだけを見ていると、「ピン留めしたルートが正規に発行した
	// 非CA証明書」を中間CAとして持ち込む攻撃が通ってしまう。Apple の開発者向け
	// 配布証明書は WWDR 発行で秘密鍵を開発者本人が持つため、それを使って偽の
	// leaf に署名すれば、隣接署名は全て正当・ルートのフィンガープリントも一致する
	// チェーンが作れる（basicConstraints 未検証の典型的な穴）。
	// 配布証明書は CA:FALSE なので、ここで塞がる。
	//
	// basicConstraints を持たない証明書は IsCA も false になり、同じく弾かれる。
	// Node の X509Certificate.ca と挙動が一致する。
	// 実物で確認済み（2026-08-27）:
	//   Apple Root CA G3      CA:TRUE / Certificate Sign
	//   Apple WWDR CA G6      CA:TRUE, pathlen:0 / Certificate Sign
	// どちらも発行者の位置に来るが CA:TRUE なので、このチェックで
	// 本番の通知が弾かれることはない。
	// なお WWDR の pathlen:0 は「その下に CA を作れない」という Apple 自身の
	// 制約で、上の攻撃も本来はここで否定されている（pathLenConstraint は
	// JS/Go とも未検証なので、CA 判定の方で塞ぐ）。
	for i := 1; i < len(certs); i++ {
		if !certs[i].IsCA {
			return fmt.Errorf("Non-CA certificate used as issuer at index %d", i)
		}
	}

	// 証明書チェーンの署名を検証（leaf → ... → root）。
	//
	// x509.Certificate.CheckSignatureFrom は上の CA 判定に加えて KeyUsage や
	// 有効期限も見る。JS 側（Node の X509Certificate.verify）と検証内容を
	// 揃えたいので、ここでは親の公開鍵で署名そのものだけを確認する。
	for i := 0; i < len(certs)-1; i++ {
		err := certs[i+1].CheckSignature(
			certs[i].SignatureAlgorithm,
			certs[i].RawTBSCertificate,
			certs[i].Signature,
		)
		if err != nil {
			return fmt.Errorf("Certificate chain verification failed at index %d", i)
		}
	}

	// ルート証明書が Apple CA であることをフィンガープリントで確認
	root := certs[len(certs)-1]
	if got := Fingerprint256(root.Raw); got != v.rootFingerprint() {
		return fmt.Errorf("Untrusted root CA fingerprint: %s", got)
	}

	// リーフ証明書の公開鍵で JWS 署名を検証
	pub, ok := certs[0].PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return errors.New("リーフ証明書の公開鍵が ECDSA ではない")
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return fmt.Errorf("JWS 署名のデコードに失敗: %w", err)
	}
	if len(sig) != 64 {
		return fmt.Errorf("ES256 署名の長さが不正: %d", len(sig))
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return errors.New("JWS の署名検証に失敗しました")
	}
	return nil
}

// Fingerprint256 は Node の X509Certificate.fingerprint256 と同じ表記
// （大文字16進をコロン区切り）で DER の SHA-256 を返す。
func Fingerprint256(der []byte) string {
	sum := sha256.Sum256(der)
	hexStr := strings.ToUpper(hex.EncodeToString(sum[:]))

	var b strings.Builder
	for i := 0; i < len(hexStr); i += 2 {
		if i > 0 {
			b.WriteByte(':')
		}
		b.WriteString(hexStr[i : i+2])
	}
	return b.String()
}

// DecodePayload は JWS のペイロードを**署名検証せずに**取り出す。
// 呼び出し前に Verify を通すこと。
func DecodePayload(signedPayload string, v any) error {
	parts := strings.Split(signedPayload, ".")
	if len(parts) != 3 {
		return ErrInvalidFormat
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return fmt.Errorf("JWS ペイロードのデコードに失敗: %w", err)
	}
	return json.Unmarshal(payload, v)
}
