package function

import (
	"context"
	"fmt"
	"log"
	"math"
	"math/rand"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 語彙テスト（startVocabTest / submitVocabTest）。
//
// estimated_vocab はクイズの正誤でしか動かないが、この 2 本だけは測定値を
// 直接書く。推定を迂回できる唯一の経路なので、
//
//   - プレミアム（トライアル含む）限定。オンボーディングは全員トライアル中
//   - 正解はセッション doc（クライアントから読めない）に置き、採点はサーバー
//
//   - 1 か月（vocabTestInterval）に 1 回まで
//
// の 3 つで抑える。サーバー採点は「正解を知って満点を取る」ことしか防がない
// ので、機械的な受け直しは間隔で止める。
//
// セッションは 1 ユーザー 1 つ。users/{uid}/vocab_test/current を上書きする
// （中断は上書きで捨てられる。rules で未定義のサブコレクションなので
// クライアントからは読めない）。

const (
	// vocabTestInterval は次に受け直せるまでの間隔。
	//
	// 無制限だと 4 択の上振れを機械的に釣れる（1 段の通過確率は当てずっぽうで
	// 約 5%）。測定値は estimated_vocab を直接書く唯一の経路で、推定を
	// 迂回するので、間隔で止める。
	// 語彙は月単位で動くものなので、月 1 回で足りる。
	vocabTestInterval = 30 * 24 * time.Hour

	// vocabTestStartsPerWindow は 1 つの間隔の中で開始できる回数。
	//
	// 締めるのは「測り直し」で、通信断や誤タップからの復帰は通したい。
	// 締めた回（done）が 1 度でもあればその時点で打ち切るので、この回数を
	// 使えるのは中断した受験だけ。段の通過には 4 択 3 問が要るため、3 回の
	// やり直しでは上振れを釣れない。
	vocabTestStartsPerWindow = 3
)

// vocabTestSessionDoc はセッション doc への参照。
func vocabTestSessionDoc(db *firestore.Client, uid string) *firestore.DocumentRef {
	return db.Collection("users").Doc(uid).Collection("vocab_test").Doc("current")
}

// vocabTestItemStore は出題語のキャッシュ（インスタンス内で使い回す）。
var vocabTestItemStore = &uvm.TestItemStore{}

type startVocabTestRequest struct {
	Lang string `json:"lang"`
}

type vocabTestQuestionOut struct {
	Word    string   `json:"word"`
	Choices []string `json:"choices"`
}

// startVocabTest は語彙テストを開始し、最初の 1 段ぶんの設問を返す。
func startVocabTest(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}
	var in startVocabTestRequest
	if err := req.Bind(&in); err != nil {
		return nil, err
	}
	l := lang.Resolve(in.Lang)

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	userRef := db.Collection("users").Doc(uid)
	data := map[string]any{}
	if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
		data = snap.Data()
	} else if err != nil && !isNotFoundErr(err) {
		log.Printf("startVocabTest: ユーザー doc を読めない: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "語彙テストを準備できませんでした")
	}

	// クォータが無い doc は onUserCreate トリガーが当たっていない（トリガー
	// 失敗・削除済み・導入前ユーザー・部分doc）。トライアルの期限も無いので
	// 「プレミアム限定」で弾かれる。オンボーディングは例文生成より先に語彙
	// テストへ来るため、生成側の自己回復（runGenerateThaiSentence）だけでは
	// 間に合わない。ここでも冪等に初期クォータを付与する。
	//
	// 判定はクォータフィールドの有無で行う。doc の有無で見ると、クイズ系だけの
	// 部分doc が残っているユーザーが直らない（生成側と同じ理由）。
	if _, ok := data["remaining_sentences"]; !ok {
		initial, err := ensureUserQuota(ctx, userRef)
		if err != nil {
			log.Printf("startVocabTest: 初期クォータの付与に失敗: uid=%s error=%v", uid, err)
			return nil, callable.Errorf(callable.Internal, "語彙テストを準備できませんでした")
		}
		for k, v := range initial {
			data[k] = v
		}
	}

	if !premium.IsEffectivePremium(data, now) {
		return nil, callable.Errorf(callable.PermissionDenied,
			"語彙テストはプレミアム限定です")
	}

	// 間隔は開始時刻で数える。完了時だと、途中で閉じたぶんが数えられず
	// 「開き直す」だけで無制限になる。
	windowAt, hasWindow := data["vocab_test_window_at"].(time.Time)
	inWindow := hasWindow && now.Sub(windowAt) < vocabTestInterval
	measured := false
	if inWindow {
		measured, err = vocabTestMeasured(ctx, db, uid)
		if err != nil {
			return nil, err
		}
	}
	count, newWindow, err := vocabTestStartCount(
		now, windowAt, inWindow, measured, intOf(data["vocab_test_count"]))
	if err != nil {
		return nil, err
	}

	items, err := vocabTestItems(ctx, l)
	if err != nil {
		log.Printf("startVocabTest: 出題語を読めない: uid=%s lang=%s error=%v", uid, l, err)
		return nil, callable.Errorf(callable.Internal, "語彙テストを準備できませんでした")
	}

	// 開始段は常に 1 段目。自己申告で下の段を飛ばさない（uvm/vocabtest.go の
	// 冒頭コメント）。初心者はそこで落ちれば 4 問で終わる。
	const stage = 0
	questions, err := buildVocabTestStage(items, stage)
	if err != nil {
		return nil, err
	}

	progress := map[string]any{
		"vocab_test_count": count,
		// 旧・1日3回の記録。読まなくなったのでここで掃除する。
		"vocab_test_count_date": firestore.Delete,
	}
	if newWindow {
		progress["vocab_test_window_at"] = now
	}
	if _, err := userRef.Set(ctx, progress, firestore.MergeAll); err != nil {
		log.Printf("startVocabTest: 回数の記録に失敗: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "語彙テストを開始できませんでした")
	}

	if _, err := vocabTestSessionDoc(db, uid).Set(ctx, map[string]any{
		"lang":       string(l),
		"stage":      stage,
		"history":    []any{},
		"seeds":      []any{},
		"questions":  questionsToStore(questions),
		"started_at": firestore.ServerTimestamp,
	}); err != nil {
		log.Printf("startVocabTest: セッション保存に失敗: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "語彙テストを開始できませんでした")
	}

	return vocabTestStageResponse(stage, questions), nil
}

type submitVocabTestRequest struct {
	// Answers は出題順の選択肢 index。未回答は -1。
	//
	// any で受けるのは、Flutter の Firebase SDK が Dart の int を
	// Int64 ラッパーに包んで送るため（callable.Int が両方を解く）。
	Answers []any `json:"answers"`

	// Stage はこの回答がどの段のものか。サーバーの段と食い違えば採点しない。
	// 古いクライアントは送らないので、欠けていたら照合を省く。
	Stage any `json:"stage"`
}

// submitVocabTest は 1 段ぶんの回答を採点し、次の段か最終結果を返す。
func submitVocabTest(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}
	var in submitVocabTestRequest
	if err := req.Bind(&in); err != nil {
		return nil, err
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	sessionRef := vocabTestSessionDoc(db, uid)
	snap, err := sessionRef.Get(ctx)
	if err != nil || !snap.Exists() {
		return nil, callable.Errorf(callable.FailedPrecondition,
			"語彙テストが開始されていません")
	}
	session := snap.Data()

	// 既に締めた回。応答が届かずクライアントが送り直すと、ここに来る。
	// もう一度採点すると 2 段目以降を空回しすることになるので、保存した結果を
	// そのまま返す（callable にリトライは無いが、タイムアウトした送信を
	// 画面から再試行できるようにしてある）。
	if done, _ := session["done"].(bool); done {
		return map[string]any{
			"done":        true,
			"vocab":       intOf(session["vocab"]),
			"asked":       intOf(session["asked"]),
			"free_capped": intOf(session["vocab"]) > uvm.FreeTierMaxVocab,
		}, nil
	}

	stage := intOf(session["stage"])
	stored := storedQuestions(session["questions"])
	if len(stored) == 0 {
		return nil, callable.Errorf(callable.FailedPrecondition, "出題が見つかりません")
	}

	// 段の食い違い＝この回答は採点済みの段のもの。採点し直さず、いま出すべき
	// 段をもう一度返す。二重送信（同時タップ・送信のやり直し）がここで止まる。
	if n, ok := callable.Int(in.Stage); ok && n != stage {
		log.Printf("submitVocabTest: 段が食い違うので再送: uid=%s client=%d server=%d",
			uid, n, stage)
		return storedStageResponse(stage, stored), nil
	}

	// 採点。回答が足りない分は誤答として数える（中断された段をそのまま締める）。
	answers := parseAnswers(in.Answers)
	correct := 0
	seeds := seedsOf(session["seeds"])
	for i, q := range stored {
		ok := i < len(answers) && answers[i] == q.answer
		if ok {
			correct++
		}
		seeds = append(seeds, vocabTestSeed{word: q.word, rank: q.rank, correct: ok})
	}

	history := append(historyOf(session["history"]),
		uvm.StageResult{Stage: stage, Correct: correct})
	next, done := uvm.NextStage(history)

	if !done {
		items, err := vocabTestItems(ctx, lang.Resolve(session["lang"]))
		if err != nil {
			return nil, callable.Errorf(callable.Internal, "語彙テストを続けられませんでした")
		}
		questions, err := buildVocabTestStage(items, next)
		if err != nil {
			return nil, err
		}
		if _, err := sessionRef.Set(ctx, map[string]any{
			"stage":     next,
			"history":   historyToStore(history),
			"seeds":     seedsToStore(seeds),
			"questions": questionsToStore(questions),
		}, firestore.MergeAll); err != nil {
			log.Printf("submitVocabTest: セッション更新に失敗: uid=%s error=%v", uid, err)
			return nil, callable.Errorf(callable.Internal, "語彙テストを続けられませんでした")
		}
		return vocabTestStageResponse(next, questions), nil
	}

	vocab := uvm.ScoreVocab(history)
	if err := finishVocabTest(ctx, db, uid, vocab, seeds); err != nil {
		log.Printf("submitVocabTest: 結果の保存に失敗: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "結果を保存できませんでした")
	}
	// セッションは消さずに済んだ印を付ける。消すと、応答が届かなかった
	// クライアントの再送が「開始されていません」になり、測れているのに
	// 失敗として見える。次の開始で丸ごと上書きされる。
	if _, err := sessionRef.Set(ctx, map[string]any{
		"done":      true,
		"vocab":     vocab,
		"asked":     len(seeds),
		"questions": []any{},
	}, firestore.MergeAll); err != nil {
		log.Printf("submitVocabTest: セッションの完了印に失敗: uid=%s error=%v", uid, err)
	}

	log.Printf("submitVocabTest completed: uid=%s vocab=%d stages=%d", uid, vocab, len(history))
	return map[string]any{
		"done":        true,
		"vocab":       vocab,
		"asked":       len(seeds),
		"free_capped": vocab > uvm.FreeTierMaxVocab,
	}, nil
}

// finishVocabTest は測定結果を反映する。
//
// estimated_vocab は測定値そのもの（＝出発点）。下限は作らない。4 択 16 問の
// 推定は上振れることがあるので、その後のクイズの正誤で下方修正できる余地を
// 残す。自己申告レベルもここには入れない（SyncEstimatedVocab のコメント）。
func finishVocabTest(
	ctx context.Context, db *firestore.Client, uid string,
	vocab int, seeds []vocabTestSeed,
) error {
	userRef := db.Collection("users").Doc(uid)

	if _, err := userRef.Set(ctx, map[string]any{
		"estimated_vocab":  vocab,
		"vocab_test_at":    firestore.ServerTimestamp,
		"vocab_test_vocab": vocab,
	}, firestore.MergeAll); err != nil {
		return err
	}

	if err := seedVocabTestUvm(ctx, db, uid, seeds); err != nil {
		// 種付けに失敗しても測定値は入っている。テストは成功として返す。
		log.Printf("finishVocabTest: UVM の種付けに失敗: uid=%s error=%v", uid, err)
	}

	uvm.PublishLeaderboardVocab(ctx, db, uid, vocab)
	return nil
}

// vocabTestSeed は出題1語ぶんの結果。
type vocabTestSeed struct {
	word    string
	rank    int
	correct bool
}

func seedsToStore(seeds []vocabTestSeed) []any {
	out := make([]any, 0, len(seeds))
	for _, s := range seeds {
		out = append(out, map[string]any{
			"word": s.word, "rank": s.rank, "correct": s.correct,
		})
	}
	return out
}

func seedsOf(v any) []vocabTestSeed {
	raw, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]vocabTestSeed, 0, len(raw))
	for _, e := range raw {
		m, ok := e.(map[string]any)
		if !ok {
			continue
		}
		word, _ := m["word"].(string)
		if word == "" {
			continue
		}
		correct, _ := m["correct"].(bool)
		out = append(out, vocabTestSeed{
			word: word, rank: intOf(m["rank"]), correct: correct,
		})
	}
	return out
}

// seedVocabTestUvm は出題語の P をテスト結果で反映する。
// 書くのは「既に UVM にある語を間違えた」ときだけ（uvm.TestSeedP を参照）。
func seedVocabTestUvm(
	ctx context.Context, db *firestore.Client, uid string,
	seeds []vocabTestSeed,
) error {
	if len(seeds) == 0 {
		return nil
	}
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")

	refs := make([]*firestore.DocumentRef, 0, len(seeds))
	for _, s := range seeds {
		refs = append(refs, uvmRef.Doc(s.word))
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		return err
	}
	existing := map[string]map[string]any{}
	for _, s := range snaps {
		if s.Exists() {
			existing[s.Ref.ID] = s.Data()
		}
	}

	now := float64(time.Now().UnixNano()) / 1e9
	batch := db.BulkWriter(ctx)
	for _, s := range seeds {
		data, exists := existing[s.word]
		oldP := 0.0
		if exists {
			if p, ok := data["p"].(float64); ok {
				oldP = p
			}
		}
		p, write := uvm.TestSeedP(oldP, exists, s.correct)
		if !write {
			// 未登録のまま／今の P のまま残す。key_word の候補に上がるように
			// するため（uvm.TestSeedP のコメント）。
			continue
		}
		if _, err := batch.Update(uvmRef.Doc(s.word), []firestore.Update{
			{Path: "p", Value: p},
			{Path: "last_seen", Value: now},
			{Path: "last_result", Value: s.correct},
		}); err != nil {
			return err
		}
	}
	batch.End()
	return nil
}

// vocabTestItems は出題語を読む。ProjectID は init 時に決まらないのでここで入れる。
func vocabTestItems(ctx context.Context, l lang.Lang) ([]uvm.TestItem, error) {
	vocabTestItemStore.ProjectID = fbapp.ProjectID()
	return vocabTestItemStore.Items(ctx, l)
}

// buildVocabTestStage は 1 段ぶんの設問を作る。
// 出題語が足りない段はテストとして成立しないので落とす。
func buildVocabTestStage(items []uvm.TestItem, stage int) ([]uvm.TestQuestion, error) {
	if stage < 0 || stage >= len(uvm.TestStages) {
		return nil, callable.Errorf(callable.Internal, "出題段が不正です")
	}
	questions := uvm.BuildStageQuestions(
		items, uvm.TestStages[stage], uvm.TestItemsPerStage, rand.New(rand.NewSource(time.Now().UnixNano())))
	if len(questions) < uvm.TestItemsPerStage {
		return nil, callable.Errorf(callable.Internal, "出題語が足りません")
	}
	return questions, nil
}

// vocabTestStageResponse は 1 段ぶんの返し。正解は含めない。
func vocabTestStageResponse(stage int, questions []uvm.TestQuestion) map[string]any {
	out := make([]vocabTestQuestionOut, 0, len(questions))
	for _, q := range questions {
		out = append(out, vocabTestQuestionOut{Word: q.Word, Choices: q.Choices})
	}
	return map[string]any{
		"done":         false,
		"stage":        stage,
		"total_stages": len(uvm.TestStages),
		"questions":    out,
	}
}

// parseAnswers は回答の index を読む。読めない要素は未回答（-1）扱いにする。
// 正常なクライアントは必ず整数を送るので、ここで落とさず段を締める。
func parseAnswers(raw []any) []int {
	out := make([]int, 0, len(raw))
	for _, v := range raw {
		n, ok := callable.Int(v)
		if !ok {
			n = -1
		}
		out = append(out, n)
	}
	return out
}

// storedQuestion はセッション doc に置く出題（正解つき）。
//
// 選択肢も残す。同じ段をもう一度返せないと、送信が届いたのに応答が返らなかった
// 場合（タイムアウト・回線断）に、クライアントが何を出せばいいか分からなくなる。
type storedQuestion struct {
	word    string
	rank    int
	choices []string
	answer  int
}

func questionsToStore(questions []uvm.TestQuestion) []any {
	out := make([]any, 0, len(questions))
	for _, q := range questions {
		choices := make([]any, 0, len(q.Choices))
		for _, c := range q.Choices {
			choices = append(choices, c)
		}
		out = append(out, map[string]any{
			"word": q.Word, "rank": q.Rank,
			"choices": choices, "answer": q.AnswerIndex,
		})
	}
	return out
}

func storedQuestions(v any) []storedQuestion {
	raw, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]storedQuestion, 0, len(raw))
	for _, e := range raw {
		m, ok := e.(map[string]any)
		if !ok {
			continue
		}
		word, _ := m["word"].(string)
		if word == "" {
			continue
		}
		var choices []string
		if raw, ok := m["choices"].([]any); ok {
			for _, c := range raw {
				if s, ok := c.(string); ok {
					choices = append(choices, s)
				}
			}
		}
		out = append(out, storedQuestion{
			word: word, rank: intOf(m["rank"]),
			choices: choices, answer: intOf(m["answer"]),
		})
	}
	return out
}

// storedStageResponse は保存済みの出題をそのまま返す（同じ段の再送）。
func storedStageResponse(stage int, stored []storedQuestion) map[string]any {
	out := make([]vocabTestQuestionOut, 0, len(stored))
	for _, q := range stored {
		out = append(out, vocabTestQuestionOut{Word: q.word, Choices: q.choices})
	}
	return map[string]any{
		"done":         false,
		"stage":        stage,
		"total_stages": len(uvm.TestStages),
		"questions":    out,
	}
}

func historyToStore(history []uvm.StageResult) []any {
	out := make([]any, 0, len(history))
	for _, r := range history {
		out = append(out, map[string]any{"stage": r.Stage, "correct": r.Correct})
	}
	return out
}

func historyOf(v any) []uvm.StageResult {
	raw, ok := v.([]any)
	if !ok {
		return nil
	}
	out := make([]uvm.StageResult, 0, len(raw))
	for _, e := range raw {
		m, ok := e.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, uvm.StageResult{
			Stage:   intOf(m["stage"]),
			Correct: intOf(m["correct"]),
		})
	}
	return out
}

// vocabTestStartCount は開始時の制限判定（IO なし）。
//
//   - inWindow: 直前の開始から vocabTestInterval が経っていない
//   - measured: その期間に測り終えている（vocabTestMeasured を参照）
//   - count:    その期間で開始した回数
//
// 返す count はこの開始を数えた後の値。newWindow なら起点を now に置き直す
// （やり直しでは据え置く。延ばせると「6日目にやり直し」で間隔が伸びていく）。
func vocabTestStartCount(
	now, windowAt time.Time, inWindow, measured bool, count int,
) (next int, newWindow bool, err error) {
	if !inWindow {
		return 1, true, nil
	}
	if measured {
		return 0, false, callable.Errorf(callable.ResourceExhausted,
			"語彙テストは月1回までです。%s", vocabTestNextAt(now, windowAt))
	}
	if count >= vocabTestStartsPerWindow {
		return 0, false, callable.Errorf(callable.ResourceExhausted,
			"語彙テストのやり直しは%d回までです。%s",
			vocabTestStartsPerWindow, vocabTestNextAt(now, windowAt))
	}
	return count + 1, false, nil
}

// vocabTestMeasured はその期間に測り終えているか。
//
// 締めた回はセッション doc に done の印が残る。セッションが残っていなければ
// 測った扱いにする（消えた・回数制限より前の実装で測った）。測ったのに
// 測っていない扱いにするほうが緩いので、そちらへは倒さない。
func vocabTestMeasured(ctx context.Context, db *firestore.Client, uid string) (bool, error) {
	snap, err := vocabTestSessionDoc(db, uid).Get(ctx)
	if isNotFoundErr(err) {
		return true, nil
	}
	if err != nil {
		// 読めないだけで受験権を消費させない（通信エラーで月1回が飛ぶ）。
		log.Printf("startVocabTest: セッションを読めない: uid=%s error=%v", uid, err)
		return false, callable.Errorf(callable.Internal, "語彙テストを開始できませんでした")
	}
	if !snap.Exists() {
		return true, nil
	}
	done, _ := snap.Data()["done"].(bool)
	return done, nil
}

// vocabTestNextAt は次に受けられるまでの案内文。
func vocabTestNextAt(now, windowAt time.Time) string {
	wait := vocabTestInterval - now.Sub(windowAt)
	if wait <= 0 {
		return "またすぐ受けられます"
	}
	if wait < 24*time.Hour {
		return fmt.Sprintf("あと%d時間で受けられます", int(math.Ceil(wait.Hours())))
	}
	return fmt.Sprintf("あと%d日で受けられます", int(math.Ceil(wait.Hours()/24)))
}

// intOf は Firestore が int64 で返す数値を int にする。
func intOf(v any) int {
	switch n := v.(type) {
	case int64:
		return int(n)
	case int:
		return n
	case float64:
		return int(n)
	}
	return 0
}
