package function

import (
	"context"
	"errors"
	"log"
	"sync"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"
	texttospeech "google.golang.org/api/texttospeech/v1"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/ttsaudio"
)

// getSentenceAudio はお手本（例文の全文）の音声を返す。
//
// GCS に無ければ Cloud TTS で作って置く（internal/ttsaudio）。音声は MP3 の
// バイト列をそのまま返す（JSON では base64。1文 7〜20KB）。URL を渡さないので
// バケットは非公開のままでよい。アプリは受け取った音声を端末に保存して再生し、
// 失敗したら端末の読み上げに戻す。
//
// 文はクライアントが送るので、文を変え続ければ新しい音声を作らせ続けられる。
// 新しく作る回数だけを1人1日 audioDailyCreateLimit 回に絞る（作成済みを返すのは数えない）。
//
// 入力: {"thai_text": "...", "topic": "...", "words": [{word, meaning, grammatical_role}]}
// 出力: {"audio": <base64>, "voice": "th-TH-Chirp3-HD-..."}
func getSentenceAudio(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}
	var in ttsaudio.Input
	if err := req.Bind(&in); err != nil {
		return nil, err
	}
	store, synth, err := sentenceAudioDeps(ctx)
	if err != nil {
		log.Printf("getSentenceAudio: init failed: %v", err)
		return nil, callable.Errorf(callable.Internal, "音声を用意できませんでした")
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	res, err := ttsaudio.Ensure(ctx, store, cappedSynth{inner: synth, db: db, uid: uid}, in)
	switch {
	case errors.Is(err, ttsaudio.ErrEmpty), errors.Is(err, ttsaudio.ErrTooLong):
		return nil, callable.Errorf(callable.InvalidArgument, "読み上げられない文です")
	case errors.Is(err, errAudioDailyLimit):
		log.Printf("getSentenceAudio: daily limit uid=%s", uid)
		return nil, callable.Errorf(callable.ResourceExhausted, "今日はこれ以上音声を用意できません")
	case err != nil:
		log.Printf("getSentenceAudio: object=%s failed: %v", res.Object, err)
		return nil, callable.Errorf(callable.Unavailable, "音声を用意できませんでした")
	}
	if res.StoreErr != nil {
		log.Printf("getSentenceAudio: object=%s not stored: %v", res.Object, res.StoreErr)
	}
	if res.Created {
		log.Printf("getSentenceAudio: created object=%s voice=%s bytes=%d", res.Object, res.Voice, len(res.Audio))
	}
	return map[string]any{"audio": res.Audio, "voice": res.Voice}, nil
}

// audioDailyCreateLimit は1人1日に新しく作れる音声の数。
// 毎日の例文は多くても十数本なので、普通に使って当たることはない。
const audioDailyCreateLimit = 100

// audioUsageCollection は新しく作った数の記録（users/{uid} とは分ける。
// users/{uid} はアプリが購読しているので、書くたびに端末へ通知が飛ぶ）。
const audioUsageCollection = "tts_usage"

var errAudioDailyLimit = errors.New("audio daily create limit")

// cappedSynth は Cloud TTS を呼ぶ直前に、その人の今日の作成数を1つ進める。
// 上限に達していたら呼ばない。
type cappedSynth struct {
	inner ttsaudio.Synthesizer
	db    *firestore.Client
	uid   string
}

func (c cappedSynth) Synthesize(ctx context.Context, voice, text string) ([]byte, error) {
	if err := reserveAudioCreate(ctx, c.db, c.uid, nowJST().Format("2006-01-02")); err != nil {
		return nil, err
	}
	return c.inner.Synthesize(ctx, voice, text)
}

// reserveAudioCreate は uid の day の作成数を1つ進める。上限なら errAudioDailyLimit。
func reserveAudioCreate(ctx context.Context, db *firestore.Client, uid, day string) error {
	ref := db.Collection(audioUsageCollection).Doc(uid)
	return db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		count := int64(0)
		snap, err := tx.Get(ref)
		if err != nil && !isNotFoundErr(err) {
			return err
		}
		if err == nil && stringField(snap.Data()["day"]) == day {
			count, _ = snap.Data()["count"].(int64)
		}
		if count >= audioDailyCreateLimit {
			return errAudioDailyLimit
		}
		return tx.Set(ref, map[string]any{"day": day, "count": count + 1})
	})
}

var (
	audioDepsMu    sync.Mutex
	audioDepsStore ttsaudio.Store
	audioDepsSynth ttsaudio.Synthesizer
)

// sentenceAudioDeps は GCS と Cloud TTS のクライアントを作って使い回す。
// 作るのに失敗したら覚えておかず、次の要求でまた作る（一時的な失敗で
// そのインスタンスがずっと使えなくならないように）。
func sentenceAudioDeps(ctx context.Context) (ttsaudio.Store, ttsaudio.Synthesizer, error) {
	audioDepsMu.Lock()
	defer audioDepsMu.Unlock()
	if audioDepsSynth != nil {
		return audioDepsStore, audioDepsSynth, nil
	}
	// リクエストの ctx で作ると、そのリクエストが終わった後にクライアントが使えなくなる。
	bg := context.WithoutCancel(ctx)
	gcs, err := storage.NewClient(bg)
	if err != nil {
		return nil, nil, err
	}
	svc, err := texttospeech.NewService(bg)
	if err != nil {
		gcs.Close()
		return nil, nil, err
	}
	audioDepsStore = ttsaudio.GCSStore{Bucket: gcs.Bucket(ttsaudio.BucketName(fbapp.ProjectID()))}
	audioDepsSynth = ttsaudio.CloudSynthesizer{Service: svc}
	return audioDepsStore, audioDepsSynth, nil
}
