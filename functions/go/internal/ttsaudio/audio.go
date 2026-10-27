package ttsaudio

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"

	"cloud.google.com/go/storage"
	"google.golang.org/api/googleapi"
	texttospeech "google.golang.org/api/texttospeech/v1"
)

// MaxRunes は1文として受け付ける長さの上限。プールの例文は長くても150字程度。
const MaxRunes = 400

// ErrEmpty は読む文が無い（絵文字だけ等）。
var ErrEmpty = errors.New("ttsaudio: empty text")

// ErrTooLong は MaxRunes を超えた。
var ErrTooLong = errors.New("ttsaudio: text too long")

// BucketName は音声を置くバケット（Terraform の tts_audio）。
func BucketName(projectID string) string { return projectID + "-tts-audio" }

// ObjectName は音声ファイルの名前。text は Normalize 済み。
func ObjectName(voice, text string) string {
	sum := sha256.Sum256([]byte(strings.Join(
		[]string{VoiceConfigVersion, voice, SpeakingRate, text}, "|")))
	return "audio/" + hex.EncodeToString(sum[:]) + ".mp3"
}

// Synthesizer は文を MP3 にする。テストで差し替える。
type Synthesizer interface {
	Synthesize(ctx context.Context, voice, text string) ([]byte, error)
}

// Store は音声ファイルの置き場。テストで差し替える。
type Store interface {
	// Get は無ければ (nil, false, nil) を返す。
	Get(ctx context.Context, name string) ([]byte, bool, error)
	// Create は無いときだけ書く。先に誰かが書いていたら何もしない。
	Create(ctx context.Context, name string, data []byte) error
}

// Result は Ensure の結果。
type Result struct {
	Object  string
	Voice   string
	Audio   []byte
	Created bool
	// StoreErr は作った音声を GCS へ置けなかったときのエラー。音声は Audio に入っているので
	// 呼び出し側はそのまま使える（次に要求されたときにまた作る）。
	StoreErr error
}

// Ensure は例文の全文の音声を返す。GCS に無ければ作って置く。
func Ensure(ctx context.Context, store Store, synth Synthesizer, in Input) (Result, error) {
	text := Normalize(in.ThaiText)
	if text == "" {
		return Result{}, ErrEmpty
	}
	if len([]rune(text)) > MaxRunes {
		return Result{}, ErrTooLong
	}
	voice := ChooseVoice(text, in)
	name := ObjectName(voice, text)
	res := Result{Object: name, Voice: voice}

	data, ok, err := store.Get(ctx, name)
	if err != nil {
		return res, err
	}
	if ok {
		res.Audio = data
		return res, nil
	}
	data, err = synth.Synthesize(ctx, voice, text)
	if err != nil {
		return res, fmt.Errorf("synthesize: %w", err)
	}
	res.Audio, res.Created = data, true
	if err := store.Create(ctx, name, data); err != nil {
		res.StoreErr = fmt.Errorf("store: %w", err)
	}
	return res, nil
}

// CloudSynthesizer は Cloud Text-to-Speech（Chirp3-HD）。
type CloudSynthesizer struct {
	Service *texttospeech.Service
}

func (c CloudSynthesizer) Synthesize(ctx context.Context, voice, text string) ([]byte, error) {
	resp, err := c.Service.Text.Synthesize(&texttospeech.SynthesizeSpeechRequest{
		Input:       &texttospeech.SynthesisInput{Text: text},
		Voice:       &texttospeech.VoiceSelectionParams{LanguageCode: "th-TH", Name: voice},
		AudioConfig: &texttospeech.AudioConfig{AudioEncoding: "MP3"},
	}).Context(ctx).Do()
	if err != nil {
		return nil, err
	}
	return decodeAudio(resp.AudioContent)
}

// GCSStore は GCS のバケット。
type GCSStore struct {
	Bucket *storage.BucketHandle
}

func (g GCSStore) Get(ctx context.Context, name string) ([]byte, bool, error) {
	r, err := g.Bucket.Object(name).NewReader(ctx)
	if errors.Is(err, storage.ErrObjectNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	defer r.Close()
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, false, err
	}
	return data, true, nil
}

func (g GCSStore) Create(ctx context.Context, name string, data []byte) error {
	w := g.Bucket.Object(name).If(storage.Conditions{DoesNotExist: true}).NewWriter(ctx)
	w.ContentType = "audio/mpeg"
	// 中身はファイル名で決まり、変わらない。
	w.CacheControl = "public, max-age=31536000, immutable"
	if _, err := w.Write(data); err != nil {
		w.Close()
		return err
	}
	err := w.Close()
	var gerr *googleapi.Error
	if errors.As(err, &gerr) && gerr.Code == 412 {
		// 同時に来た別の要求が先に書いた。中身は同じ。
		return nil
	}
	return err
}

// decodeAudio は REST の audioContent（base64）を戻す。
func decodeAudio(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}
