// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class L10nJa extends L10n {
  L10nJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'まいにちタイ語';

  @override
  String get settingsDisplay => '表示';

  @override
  String get settingsFont => 'フォント';

  @override
  String get settingsFontPickerTitle => 'フォントを選択';

  @override
  String get settingsLanguage => '言語（dev専用）';

  @override
  String get settingsLanguagePickerTitle => '言語を選択';

  @override
  String get settingsLanguageNote =>
      'dev ビルドの動作確認用です。切り替えても、すでに作った例文の訳は作成時の言語のまま残ります。';

  @override
  String get navLearn => '学習';

  @override
  String get navHistory => '履歴';

  @override
  String get navSettings => '設定';

  @override
  String get learnQuizTitle => 'クイズ';

  @override
  String get learnSummaryQuizTitle => 'まとめクイズ';

  @override
  String get learnNextSentence => '次の例文へ';

  @override
  String get firstGuideTitle => 'まずは体験してみましょう';

  @override
  String get firstGuideBody => '実際に1回、例文からクイズまで通して学習します。\n押すボタンはこのあと順番にご案内します。';

  @override
  String get firstGuideTrial => '最初の2日間はプレミアムの内容で学べます';

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => '再試行';

  @override
  String get coachDetailTitle => 'まずは例文をタップ';

  @override
  String get coachDetailMessage => 'カードをタップすると、単語ごとの意味と発音を確認できます。';

  @override
  String get coachQuizTitle => '次はクイズに挑戦';

  @override
  String get coachQuizMessage => '例文を読んだら、確認クイズに進みましょう。';

  @override
  String get sentencePreparing => '次の例文を準備中...';

  @override
  String get todaysWords => '今日の学習単語';

  @override
  String get playPronunciation => '発音を再生';

  @override
  String get sentenceUsingWord => 'この単語を使った例文';

  @override
  String get badgePremiumSentence => 'Premium例文';

  @override
  String get badgeFreeSentence => 'Free例文';

  @override
  String get sampleSentenceNotice => 'サンプル例文（履歴には保存されません）';

  @override
  String get sampleGreetingTranslation => 'こんにちは（男性の場合）';

  @override
  String get sampleGreetingWord1Meaning => 'こんにちは、さようなら';

  @override
  String get sampleGreetingWord1Role => '挨拶語';

  @override
  String get sampleGreetingWord2Meaning => '〜です（男性の丁寧な語尾）';

  @override
  String get sampleGreetingWord2Role => '語尾詞';

  @override
  String get sampleGreetingTopic => '日常的な挨拶';

  @override
  String get sampleGreetingStyle => '口語体';

  @override
  String get sampleGreetingEmotion => '丁寧、フォーマル';

  @override
  String get sampleGreetingUsage => '朝昼晩いつでも使える基本的な挨拶。女性の場合は「ค่ะ」を使います。';

  @override
  String get quizTodayTitle => '今日のクイズ';

  @override
  String get quizOptionalChallenge => '5問チャレンジする';

  @override
  String get quizGenerating => 'クイズを生成中...';

  @override
  String get quizOpenSentenceFirst => 'まず例文を開きましょう';

  @override
  String get quizFromLearningSentence => 'クイズは学習中の例文から出題されます';

  @override
  String get quizBackToSentence => '例文に戻る';

  @override
  String get quizCorrect => '正解！';

  @override
  String get quizIncorrect => '不正解';

  @override
  String quizCorrectAnswer(String answer) {
    return '正解: $answer';
  }

  @override
  String get quizPrompt => '下線部に入る単語を選んでください';

  @override
  String quizProgress(int index, int total) {
    return '問題 $index / $total';
  }

  @override
  String get quizSentenceReviewed => '例文を復習済み';

  @override
  String get quizReviewSentence => '例文を復習する';

  @override
  String get quizHint => 'ヒント';

  @override
  String get quizCheckSentence => '例文を確認';

  @override
  String get quizPlaySentence => '例文を再生';

  @override
  String get quizPlayWord => '単語を再生';

  @override
  String get quizWhyCorrect => '正解理由';

  @override
  String get quizWhyIncorrect => '不正解理由';

  @override
  String get quizSeeResults => '結果を見る';

  @override
  String get quizNextQuestion => '次の問題へ';

  @override
  String get commonTryAgain => 'もう一度試す';

  @override
  String get coachQuizReviewTitle => '迷ったら例文に戻れます';

  @override
  String get coachQuizReviewMessage => '答えに自信がないときは、ここから例文を見直してから回答できます。';

  @override
  String get coachSummaryQuizTitle => 'まとめクイズに挑戦';

  @override
  String get coachSummaryQuizEmphasis => '例文5つごと';

  @override
  String get coachSummaryQuizMessage =>
      '学習した内容をまとめて確認するクイズです。本来は例文5つごとに出ます。スキップして次の例文に進むこともできます。';

  @override
  String get coachTopicTitle => '次の例文のテーマを選べます';

  @override
  String get coachTopicMessage =>
      'ここをタップすると、次に生成する例文のテーマ（旅行・恋愛など）を変更できます。気分に合わせて学習内容を選びましょう。';

  @override
  String get vocabScore => '語彙スコア';

  @override
  String get vocabScoreCalculating => '語彙スコアを計算中...';

  @override
  String get vocabScoreUp => '語彙スコアアップ！';

  @override
  String get vocabScoreCapped => '語彙スコアが上限に達しました';

  @override
  String get vocabScorePremiumPitch => 'Premiumで続きの成長を記録しよう';

  @override
  String vocabWords(int count) {
    return '$count語';
  }

  @override
  String vocabWordsDelta(String delta) {
    return '$delta語';
  }

  @override
  String get historyTitle => '履歴';

  @override
  String get historyFavoritesOnly => 'お気に入りのみ表示';

  @override
  String get historyDeleteAll => 'すべて削除';

  @override
  String get historySearchHint => 'タイ語または日本語で検索';

  @override
  String get historyEmptyFavorites => 'お気に入りの例文がありません';

  @override
  String get historyEmptySearch => '検索結果が見つかりませんでした';

  @override
  String get historyEmpty => 'まだ例文がありません';

  @override
  String get historyEmptyFavoritesHint => '例文のハートアイコンをタップしてお気に入りに追加できます';

  @override
  String get historyEmptySearchHint => '別のキーワードで検索してみてください';

  @override
  String get historyEmptyHint => '新しい例文を生成してみましょう';

  @override
  String get historyDeleteAllConfirm => 'すべての例文履歴を削除しますか？この操作は取り消せません。';

  @override
  String get historyDeletedAll => 'すべての例文を削除しました';

  @override
  String historyDeleteFailed(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get historyDeleteConfirmTitle => '削除の確認';

  @override
  String get historyDeleteConfirm => 'この例文を削除しますか？';

  @override
  String get historyDeletedOne => '例文を削除しました';

  @override
  String historyWordCount(int count) {
    return '$count 単語';
  }

  @override
  String get commonError => 'エラーが発生しました';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonDelete => '削除';

  @override
  String get commonUnknown => '不明';

  @override
  String get detailTitle => '例文の詳細';

  @override
  String get detailShare => '共有';

  @override
  String detailWordBreakdown(int count) {
    return '単語の分解 ($count)';
  }

  @override
  String get detailQuizTarget => '→ クイズで出題';

  @override
  String get detailTapForTone => 'タップして声調を確認';

  @override
  String get detailContextSection => '文脈・使い方';

  @override
  String get detailContextTopic => '場面';

  @override
  String get detailContextStyle => '文体';

  @override
  String get detailContextEmotion => '感情・トーン';

  @override
  String get detailContextUsage => '使用シーン';

  @override
  String get detailContextCulture => '文化的背景';

  @override
  String detailCreatedAt(String date) {
    return '作成日: $date';
  }

  @override
  String get detailCopied => 'クリップボードにコピーしました';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsAccount => 'アカウント';

  @override
  String get settingsUser => 'ユーザー';

  @override
  String get settingsGuest => 'ゲスト';

  @override
  String get settingsNotSignedIn => 'サインインしていません';

  @override
  String get settingsPlan => 'プラン';

  @override
  String get settingsDeleteAccount => 'アカウントを削除';

  @override
  String get settingsSignOut => 'サインアウト';

  @override
  String get settingsSignInToSave => 'サインインして進捗を保存';

  @override
  String get settingsSignOutConfirm => 'サインアウトしますか？';

  @override
  String get settingsDeleteAccountTitle => 'アカウント削除';

  @override
  String get settingsDeleteAccountConfirm =>
      'アカウントを削除すると、サーバーおよび端末のすべての学習データが完全に削除されます。この操作は元に戻せません。';

  @override
  String get settingsAccountDeleted => 'アカウントとすべてのデータを削除しました';

  @override
  String get settingsFontSample => '例文';

  @override
  String get settingsLearningStatus => '学習状況';

  @override
  String get settingsLearningSection => '学習設定';

  @override
  String get settingsToneGuide => '声調ガイド';

  @override
  String get settingsToneGuideSubtitle => 'タイ語の声調ルールを学ぶ';

  @override
  String get settingsResetLearningData => '学習データをリセット';

  @override
  String get settingsResetLearningDataSubtitle => '端末の例文・クイズ履歴を削除';

  @override
  String get settingsResetTitle => '学習データのリセット';

  @override
  String get settingsResetConfirm =>
      '端末に保存されている例文・クイズ履歴・学習進捗がすべて削除されます。アカウントは維持されます。';

  @override
  String get settingsResetDone => '学習データをリセットしました';

  @override
  String get settingsResetFailed => 'リセットに失敗しました';

  @override
  String get commonReset => 'リセット';

  @override
  String get settingsDailyNotification => '毎日の例文通知';

  @override
  String get settingsDailyNotificationSubtitle => 'その日の例文をお知らせします';

  @override
  String get settingsAllowNotificationInOsSettings => '端末の設定で通知を許可してください';

  @override
  String get settingsNotificationTime => '通知する時刻';

  @override
  String get settingsTopic => 'テーマ';

  @override
  String get settingsTopicRandom => 'おまかせ';

  @override
  String settingsNextLevelIn(int count) {
    return '次のレベルまで あと$count語';
  }

  @override
  String settingsFreeVocabLimit(int limit) {
    return 'Freeプランは$limit語が上限です';
  }

  @override
  String get settingsCouldNotOpenUrl => 'URLを開けませんでした';

  @override
  String get settingsAbout => 'アプリについて';

  @override
  String get settingsTagline => '毎日タイ語を学習しましょう';

  @override
  String get settingsPrivacyPolicy => 'プライバシーポリシー';

  @override
  String get settingsTerms => '利用規約';

  @override
  String get settingsContact => 'お問い合わせ';

  @override
  String get trialEndedTitle => 'プレミアム体験が終了しました';

  @override
  String get trialEndedBody =>
      'ここからは無料プランでの学習になります。体験中に使えていた次の機能は、プレミアムでそのまま続けられます。';

  @override
  String get trialEndedLostTopic => '学びたいテーマを自分で選べる';

  @override
  String get trialEndedLostQuality => 'より自然で表現豊かな例文で学べる';

  @override
  String get trialEndedLater => 'あとで';

  @override
  String get trialEndedSeePremium => 'プレミアムを見る';

  @override
  String get topicPickerTitle => 'テーマを選択';

  @override
  String get nextTopicPrefix => '次のテーマ: ';

  @override
  String get topicName_blDrama => 'タイBLドラマ';

  @override
  String get topicSub_blDrama => '告白、すれ違い、再会、嫉妬、裏切り、仲直り、壁ドン、あだ名呼び';

  @override
  String get topicName_romance => '恋愛・男女関係';

  @override
  String get topicSub_romance => '告白、デート、甘い言葉、遠距離、別れ、仲直り';

  @override
  String get topicName_work => '仕事';

  @override
  String get topicSub_work => '報告・連絡・相談、打ち合わせ、残業申請、同僚雑談';

  @override
  String get topicName_greetings => 'あいさつ';

  @override
  String get topicSub_greetings => '朝・昼・夜、初対面、再会、別れ、電話';

  @override
  String get topicName_food => '食べ物';

  @override
  String get topicSub_food => '注文、感想、屋台、辛さ調整、アレルギー';

  @override
  String get topicName_travel => '旅行';

  @override
  String get topicSub_travel => 'ホテル、道案内、観光地、空港、ツアー';

  @override
  String get topicName_family => '家族';

  @override
  String get topicSub_family => '家族紹介、子育て、親への感謝、兄弟、家族行事';

  @override
  String get topicName_shopping => '買い物';

  @override
  String get topicSub_shopping => '値段交渉、サイズ・色の確認、返品、ナイトマーケット';

  @override
  String get topicName_transport => '交通';

  @override
  String get topicSub_transport => 'Grab、BTS、バイタク、ソンテウ、渋滞';

  @override
  String get topicName_health => '健康';

  @override
  String get topicSub_health => '症状説明、薬局、マッサージ、健康診断';

  @override
  String get topicName_weather => '天気';

  @override
  String get topicSub_weather => '暑さ、雨季、台風、日焼け対策';

  @override
  String get topicName_hobbies => '趣味';

  @override
  String get topicSub_hobbies => 'ムエタイ、音楽、映画、ゴルフ、SNS、ゲーム';

  @override
  String get topicName_school => '学校';

  @override
  String get topicSub_school => '授業中、宿題、試験、放課後、語学学校';

  @override
  String get topicName_religion => '宗教・信仰';

  @override
  String get topicSub_religion => '寺院マナー、托鉢、お守り、僧侶への話し方、仏教行事';

  @override
  String get topicName_festivals => '伝統・祭り';

  @override
  String get topicSub_festivals => 'ソンクラーン、ロイクラトン、王室行事、地域の伝統料理';

  @override
  String get topicName_etiquette => '礼儀作法';

  @override
  String get topicSub_etiquette => 'ワイの使い分け、敬語、タブー、食事マナー、贈り物';

  @override
  String get styleName_news => 'ニュース記事体';

  @override
  String get styleName_spoken => '口語体';

  @override
  String get styleName_polite => '丁寧語';

  @override
  String get styleName_sns => 'SNS・テキストメッセージ';

  @override
  String get styleName_narrative => '物語・文学体';

  @override
  String get vocabLevelIntro => '入門';

  @override
  String get vocabLevelBeginner => '初級';

  @override
  String get vocabLevelUpperBeginner => '初中級';

  @override
  String get vocabLevelIntermediate => '中級';

  @override
  String get vocabLevelAdvanced => '上級';

  @override
  String vocabDialogTitle(String level) {
    return '語彙スコア（$level）';
  }

  @override
  String vocabDialogTitleFree(String level) {
    return '語彙スコア（Free・$level）';
  }

  @override
  String vocabProgressOf(int current, int threshold) {
    return '$current / $threshold 語';
  }

  @override
  String get vocabFreeCap => 'Free上限';

  @override
  String vocabRemaining(int count) {
    return '残り$count語';
  }

  @override
  String vocabCurrentTopics(int count) {
    return '現在のテーマ数（$count件）';
  }

  @override
  String vocabFreeTopics(int count) {
    return 'Freeのテーマ数（$count件）';
  }

  @override
  String vocabNextUnlock(int count) {
    return '次の開放（+$count件）';
  }

  @override
  String vocabNextUnlockIn(int words, int count) {
    return 'あと$words語で開放（+$count件）';
  }

  @override
  String get vocabSeePremium => 'Premiumを見る';

  @override
  String get commonClose => '閉じる';

  @override
  String get vocabFreeLimitTitle => 'Freeは100語が上限です';

  @override
  String get vocabFreeLimitBody =>
      'Premiumでは100語以上学べます。また例文のテーマが増え、より多様なタイ語が学べます。';

  @override
  String get vocabUnlockMore => '語彙スコアが増えると次の例文テーマが開放されます。';

  @override
  String vocabTopicCountNow(int count) {
    return '例文テーマ候補は現在$count件です。';
  }

  @override
  String vocabPremiumAddsTopics(int count) {
    return 'Premiumで追加されるテーマ数（$count件）';
  }

  @override
  String get listSeparator => '、';

  @override
  String get paywallTitle => 'プレミアムプラン';

  @override
  String get paywallTagline => '推しの言葉が、わかる日が来る。';

  @override
  String get paywallSignInRequired => 'サインインが必要です';

  @override
  String get paywallSignInForPurchase => '購入を機種変更後も引き継ぐため、サインインしてください。';

  @override
  String get paywallSignInForRestore => '購入を復元するには、購入時のアカウントでサインインしてください。';

  @override
  String get paywallActive => 'プレミアムプランに加入中です';

  @override
  String get paywallSubscribe => 'プレミアムに登録';

  @override
  String get paywallLegal =>
      'サブスクリプションは自動更新です。期間終了24時間前までにキャンセルできます。更新料金は終了24時間以内に請求され、管理・キャンセルはApp Storeのアカウント設定から行えます。';

  @override
  String get paywallRestore => '購入を復元';

  @override
  String paywallPriceYen(String amount) {
    return '¥$amount / 月';
  }

  @override
  String paywallPrice(String currency, String amount) {
    return '$currency $amount / 月';
  }

  @override
  String get paywallFeature1Title => 'ネイティブ品質で例文生成';

  @override
  String get paywallFeature1Free => '教科書的な基礎文';

  @override
  String get paywallFeature1Premium => 'ネイティブが使う言い回し';

  @override
  String get paywallFeature2Title => 'タイドラマ・恋愛・旅行など';

  @override
  String get paywallFeature2Free => 'おまかせ出題のみ';

  @override
  String get paywallFeature2Premium => '学びたいテーマを自由に選べる';

  @override
  String get paywallFeature3Title => '学べる単語数が無制限';

  @override
  String get paywallFeature3Free => '基礎100語まで';

  @override
  String get paywallFeature3Premium => 'ドラマのセリフも理解できる';

  @override
  String get onboarding1Title => 'AIがタイ語例文を毎日生成';

  @override
  String get onboarding1Body => '毎日新しい例文が届きます。\nカードをタップで発音・意味・音声を確認。';

  @override
  String get onboarding2Title => '例文とクイズで学習';

  @override
  String get onboarding2Body => '例文を読んだらクイズで確認。\n毎日くり返して着実に定着します。';

  @override
  String get onboarding3Title => 'クイズで語彙スコアUP';

  @override
  String get onboarding3Body => '間違えた単語はくり返し出題。\nスコアに合わせて難易度も変化します。';

  @override
  String get onboardingSkip => 'スキップ';

  @override
  String get onboardingStart => 'はじめる';

  @override
  String get onboardingNext => '次へ';

  @override
  String get notifCoachTitle => '例文を毎日の習慣に';

  @override
  String get notifCoachStep1 => '通勤中や寝る前など、学習を続けやすい時刻を決めます';

  @override
  String get notifCoachStep2 => 'その時刻に、あなた向けの1例文が自動で届きます';

  @override
  String get notifCoachHabit => '毎日同じ時間に開くので、習慣になります';

  @override
  String get notifCoachPreviewLabel => '通知の例）';

  @override
  String get notifCoachFooter => '通知をタップで学習画面へ。時刻は設定で変更できます。';

  @override
  String get notifCoachNow => '今';

  @override
  String get notifCoachSampleTitle => '🇹🇭 今日のタイ語 · ขอบคุณ（ありがとう）';

  @override
  String get notifCoachSampleBody => '→ コーヒーをありがとうございます';

  @override
  String get notifCoachEnable => '通知をオンにする';

  @override
  String get notifCoachLater => 'あとで';

  @override
  String get notifCoachEnabled => '毎日この時間に例文をお届けします。時刻は設定で変更できます。';

  @override
  String get commonGotIt => 'わかった';

  @override
  String get premiumHint1Title => 'タイ例文のテーマを選べます';

  @override
  String get premiumHint1Body => 'タイドラマ・恋愛・旅行など、学びたいテーマから出題';

  @override
  String get premiumHint2Title => 'ネイティブが使う言い回しで学べます';

  @override
  String get premiumHint2Body => '教科書的な基礎文から、実際の会話で使われる表現へ';

  @override
  String get premiumHint3Title => '学べる単語数が無制限に';

  @override
  String get premiumHint3Body => '基礎100語の先へ。ドラマのセリフも聞き取れるように';

  @override
  String get premiumHintCta => 'プレミアムを見る →';

  @override
  String get signInReminderTitle => '学習の進捗を保護';

  @override
  String get signInReminderMessage =>
      'サインインすると進捗が保存され、機種変更後も学習を続けられます。サインインしない場合、3日間ご利用がないと学習の進捗は削除されます。';

  @override
  String get signInReminderBanner =>
      '学習データを保護しましょう\nサインインしないと、3日間ご利用がない場合に学習の進捗が削除されます。';

  @override
  String get commonLater => 'あとで';

  @override
  String get signIn => 'サインイン';

  @override
  String get signInSheetMessage => '進捗を保存し、機種変更後も学習を続けられます。';

  @override
  String get signInWithApple => 'Appleでサインイン';

  @override
  String get signInWithGoogle => 'Googleでサインイン';

  @override
  String get quizOfferToQuiz => '確認クイズへ';

  @override
  String get quizOfferOneQuestion => '1問だけ確認';

  @override
  String get quizOfferBody => 'この例文の単語を覚えたか、すぐ確認できます。';

  @override
  String get quizOfferTryOne => '1問だけやってみる';

  @override
  String get audioRepeat => 'リピート';

  @override
  String get audioOnce => '1回だけ';

  @override
  String get audioPause => '一時停止';

  @override
  String get audioPlay => '再生';

  @override
  String audioModeHint(String mode) {
    return '現在は$mode。長押しで再生モードを変更';
  }

  @override
  String get audioModeRepeat => 'リピート再生';

  @override
  String get audioModeOnce => '1回だけ再生';

  @override
  String get audioPosition => '再生位置';

  @override
  String get pronunciationTitle => '発音してみる';

  @override
  String get pronunciationHoldToSpeak => '押したまま話す';

  @override
  String get pronunciationRecording => '録音中… 指を離すと判定';

  @override
  String get pronunciationAnalyzing => '判定中…';

  @override
  String get pronunciationRetry => 'もう一度';

  @override
  String get pronunciationReference => 'お手本';

  @override
  String get pronunciationYours => 'あなた';

  @override
  String get pronunciationTapWordHint => '語をタップすると、どこがずれたか見られます';

  @override
  String pronunciationScore(int score) {
    return '$score点';
  }

  @override
  String get pronunciationVerdictCorrect => '合っています';

  @override
  String get pronunciationVerdictClose => '惜しい';

  @override
  String get pronunciationVerdictWrong => 'ずれています';

  @override
  String get pronunciationVerdictUnscored => '判定できず';

  @override
  String get pronunciationTooQuiet => '声が拾えませんでした。静かな場所でもう一度お試しください';

  @override
  String get pronunciationNoSpeakerRange => '声の高さが読み取れませんでした。もう一度お試しください';

  @override
  String get pronunciationNoSyllables => 'この例文は発音練習に対応していません';

  @override
  String get pronunciationMonotone => '声の高さがほとんど動いていません。お手本を聞いて、上げ下げを付けてもう一度';

  @override
  String get pronunciationCaptureFailed => 'マイクから音声を取得できませんでした。もう一度お試しください';

  @override
  String get pronunciationPermissionTitle => 'マイクの使用を許可してください';

  @override
  String get pronunciationPermissionBody =>
      '発音を判定するためにマイクを使います。録音した音声は端末の中だけで処理され、どこにも送信されません。';

  @override
  String get pronunciationPermissionOpenSettings => '設定を開く';

  @override
  String get pronunciationBandCombined => '線の色＝声調と発音を合わせた判定';

  @override
  String get pronunciationSpeechRecognized => '発音（子音・母音）：通じました';

  @override
  String get pronunciationSpeechMissing => '発音（子音・母音）：通じませんでした';

  @override
  String get pronunciationSpeechUnavailable =>
      'いまは発音（子音・母音）を判定できません。声調だけを見ています';

  @override
  String get pronunciationSpeechNoAsset =>
      'この端末にタイ語の音声入力が入っていないため、発音（子音・母音）は判定できません。声調だけを見ています';

  @override
  String get pronunciationSpeechNoAssetHow =>
      '「設定」→「一般」→「キーボード」でタイ語のキーボードを追加し、音声入力をオンにすると使えるようになります。';

  @override
  String get pronunciationSpeechAuthDenied =>
      '音声認識が許可されていないため、発音（子音・母音）は判定できません。声調だけを見ています';

  @override
  String get pronunciationSpeechAndroid =>
      'Android では発音（子音・母音）の判定に対応していません。声調だけを見ています';

  @override
  String get pronunciationPremiumTitle => '発音練習はプレミアム機能です';

  @override
  String get pronunciationPremiumBody => '録音した声をお手本と比べ、音節ごとの声調と、語が通じたかを返します。';

  @override
  String tipWithExample(String content, String example) {
    return '$content\n例: $example';
  }

  @override
  String get errQuizGenerationFailed => 'クイズの生成に失敗しました。もう一度お試しください。';

  @override
  String get quotaQuizReached => '本日のクイズ生成上限に達しました。';

  @override
  String get quotaSentenceReached => '本日の例文生成上限に達しました。\nまた明日ご利用ください。';

  @override
  String get errAuth => '認証エラーが発生しました。アプリを再起動してください。';

  @override
  String get errNetwork => 'ネットワーク接続エラーが発生しました。インターネット接続を確認してください。';

  @override
  String get errTimeout => 'リクエストがタイムアウトしました。もう一度お試しください。';

  @override
  String get errServer => 'サーバーエラーが発生しました。しばらく待ってから再試行してください。';

  @override
  String get errSentenceGenerationFailed => '例文の生成に失敗しました。もう一度お試しください。';

  @override
  String get errLoadFailed => 'データの読み込みに失敗しました';

  @override
  String get errLoadFailedRetry => 'データの読み込みに失敗しました。もう一度お試しください。';

  @override
  String errUnexpected(String error) {
    return '予期しないエラーが発生しました: $error';
  }

  @override
  String get errSignInRequiredForPremium => 'プレミアムのご利用にはサインインが必要です';

  @override
  String get errProductLoadFailed => '課金商品を取得できませんでした';

  @override
  String get errPurchaseStartFailed => '購入を開始できませんでした';

  @override
  String get errStoreUnavailable => 'App Storeに接続できませんでした';

  @override
  String get errNothingToRestore => '復元できる購入が見つかりませんでした';

  @override
  String get errRestoreFailed => '復元に失敗しました';

  @override
  String get errGoogleSignInFailed => 'Googleサインインに失敗しました';

  @override
  String get errAppleSignInFailed => 'Appleサインインに失敗しました';

  @override
  String get errSignOutFailed => 'サインアウトに失敗しました';

  @override
  String get errDeleteAccountFailed => 'アカウント削除に失敗しました';

  @override
  String quotaResetInHours(int hours, int minutes) {
    return '次のリセットまで $hours時間$minutes分';
  }

  @override
  String quotaResetInMinutes(int minutes) {
    return '次のリセットまで $minutes分';
  }

  @override
  String shareTopic(String value) {
    return '【場面】$value';
  }

  @override
  String shareStyle(String value) {
    return '【文体】$value';
  }

  @override
  String shareEmotion(String value) {
    return '【トーン】$value';
  }

  @override
  String shareUsage(String value) {
    return '【使用シーン】$value';
  }

  @override
  String shareCulture(String value) {
    return '【文化的背景】$value';
  }

  @override
  String get contactSent => 'お問い合わせを送信しました。ありがとうございます。';

  @override
  String get contactFailed => '送信に失敗しました。しばらくしてから再度お試しください。';

  @override
  String get contactName => 'お名前';

  @override
  String get contactNameRequired => 'お名前を入力してください';

  @override
  String get contactEmail => 'メールアドレス';

  @override
  String get contactEmailRequired => 'メールアドレスを入力してください';

  @override
  String get contactEmailInvalid => '正しいメールアドレスを入力してください';

  @override
  String get contactBody => 'お問い合わせ内容';

  @override
  String get contactBodyRequired => 'お問い合わせ内容を入力してください';

  @override
  String get contactSubmit => '送信する';

  @override
  String get consonantClassHigh => '高子音';

  @override
  String get consonantClassMiddle => '中子音';

  @override
  String get consonantClassLow => '低子音';

  @override
  String get commonUnknownShort => '不明';

  @override
  String get toneMarkNone => '声調記号なし';

  @override
  String get toneMarkMaiEk => 'マイエーク';

  @override
  String get toneMarkMaiTho => 'マイトー';

  @override
  String get toneMarkMaiTri => 'マイトリー';

  @override
  String get toneMarkMaiChattawa => 'マイチャッタワー';

  @override
  String get toneMarkSymbolNone => 'なし';

  @override
  String get syllableLive => '生音節';

  @override
  String get syllableDead => '死音節';

  @override
  String get syllableDeadShort => '死音節（短母音）';

  @override
  String get syllableDeadLong => '死音節（長母音・複合母音）';

  @override
  String get syllableLiveDesc => '長母音 または -m, -n, -ng, -y, -w で終わる';

  @override
  String get syllableDeadDesc => '短母音で末子音なし または -p, -t, -k で終わる';

  @override
  String get toneMid => '平声';

  @override
  String get toneLow => '低声';

  @override
  String get toneFalling => '下降声';

  @override
  String get toneHigh => '高声';

  @override
  String get toneRising => '上昇声';

  @override
  String get toneAnalyzerEmptyWord => '単語が空です';

  @override
  String get toneDialogTitle => '声調の解説';

  @override
  String get toneSyllableBreakdown => '音節分解';

  @override
  String toneSyllableNumber(int number) {
    return '音節 $number';
  }

  @override
  String get toneMainConsonant => '主子音';

  @override
  String get toneSyllableType => '音節タイプ';

  @override
  String get toneResultPrefix => '結果: ';

  @override
  String get toneMarkLabel => '声調記号';

  @override
  String get toneMarkPrefix => '声調記号: ';

  @override
  String get toneResultTone => '結果の声調';

  @override
  String toneShiftFor(String consonantClass) {
    return '$consonantClassの声調変化';
  }

  @override
  String toneShiftTableFor(String consonantClass) {
    return '$consonantClassの声調変化表';
  }

  @override
  String get toneRareUsage => '例外的な使用（現代では稀）';

  @override
  String get toneAppliedRule => '= この単語に適用されている規則';

  @override
  String get toneLearnMore => '声調について詳しく学ぶ';

  @override
  String toneExamplePrefix(String value) {
    return '例: $value';
  }

  @override
  String get toneGuideTitle => 'タイ語の声調ガイド';

  @override
  String get toneGuideHeading => 'タイ語の声調について';

  @override
  String get toneGuideIntro =>
      'タイ語には5つの声調があり、同じ綴りでも声調によって意味が変わります。声調は、主子音（声調を決める子音）のクラス、声調記号、音節タイプによって決まります。';

  @override
  String get toneGuideFiveTones => '5つの声調';

  @override
  String get toneGuideConsonantClasses => '子音クラス';

  @override
  String get toneGuideToneMarks => '声調記号';

  @override
  String get toneGuideSyllableTypes => '音節タイプ';

  @override
  String get toneGuideShiftTable => '声調変化表';

  @override
  String get toneGuideShiftTableIntro =>
      '子音クラスごとに、声調記号と音節タイプの組み合わせで決まる声調を示します。';

  @override
  String toneGuideLetterCount(int count) {
    return '$count文字';
  }

  @override
  String get toneMidDesc => '音の高さが平らで変化しない声調です。';

  @override
  String get toneMidExample => 'กา (gaa) カラス';

  @override
  String get toneLowDesc => '低い音から始まり、少し下がる声調です。';

  @override
  String get toneLowExample => 'ก่า (gàa) ガランガル';

  @override
  String get toneFallingDesc => '高い音から低く落ちる声調です。';

  @override
  String get toneFallingExample => 'ก้า (gâa) 歩み';

  @override
  String get toneHighDesc => '高い音で始まり、さらに上がる声調です。';

  @override
  String get toneHighExample => 'ก๊า (gáa) 〜だよ（語尾）';

  @override
  String get toneRisingDesc => '低い音から高く上がる声調です。';

  @override
  String get toneRisingExample => 'ก๋า (gǎa) 〜だね（語尾）';

  @override
  String get toneMarkMaiEkDesc => '第1声調記号。子音クラスによって異なる声調になります。';

  @override
  String get toneMarkMaiThoDesc => '第2声調記号。子音クラスによって異なる声調になります。';

  @override
  String get toneMarkMaiTriDesc => '第3声調記号。中子音で使用。低子音・高子音では例外的です。';

  @override
  String get toneMarkMaiChattawaDesc => '第4声調記号。中子音で使用。低子音・高子音では例外的です。';

  @override
  String get tipCatVowel => '母音';

  @override
  String get tipCatCulture => '文化';

  @override
  String get tipCatTone => '声調';

  @override
  String get tipCatConsonant => '子音';

  @override
  String get tipCatNumber => '数字';

  @override
  String get tipCatDaily => '日常表現';

  @override
  String get tipCatStudy => '学習のコツ';

  @override
  String get tip_vowelA_title => 'อะ / อา （a / aa）';

  @override
  String get tip_vowelA_content => '短母音 อะ は「a」、長母音 อา は「aa」。長さで意味が変わります。';

  @override
  String get tip_vowelA_example => 'จะ（jà＝〜する） / จา（jaa＝皿）';

  @override
  String get tip_vowelI_title => 'อิ / อี （i / ii）';

  @override
  String get tip_vowelI_content => '短母音 อิ は短い「i」、長母音 อี は長い「ii」。';

  @override
  String get tip_vowelI_example => 'นิด（nít＝少し） / นี่（nîi＝これ）';

  @override
  String get tip_vowelU_title => 'อุ / อู （u / uu）';

  @override
  String get tip_vowelU_content => '短母音 อุ は短い「u」、長母音 อู は長い「uu」。';

  @override
  String get tip_vowelU_example => 'รุ่น（rûn＝世代） / รู้（rúu＝知る）';

  @override
  String get tip_vowelE_title => 'เอ / แอ （ee / ɛɛ）';

  @override
  String get tip_vowelE_content => 'เอ は「ee」、แอ は口を大きく開けた「ɛɛ」。';

  @override
  String get tip_vowelE_example => 'เก่ง（kèeng＝上手） / แก่（kɛ̀ɛ＝老いた）';

  @override
  String get tip_vowelO_title => 'โอ / ออ （oo / ɔɔ）';

  @override
  String get tip_vowelO_content => 'โอ は口をすぼめた「oo」、ออ は口を開けた「ɔɔ」。';

  @override
  String get tip_vowelO_example => 'โต（too＝大きい） / ต่อ（tɔ̀ɔ＝続ける）';

  @override
  String get tip_vowelUea_title => 'เอือ （ʉa）';

  @override
  String get tip_vowelUea_content => 'เอือ は日本語にない母音。「ʉa」と表記されます。';

  @override
  String get tip_vowelUea_example => 'เมือง（mʉʉang＝街・国）';

  @override
  String get tip_vowelUu_title => 'อือ / อื （ʉ / ʉʉ）';

  @override
  String get tip_vowelUu_content => '日本語にない音。「i」の口で「u」と発音するイメージ。';

  @override
  String get tip_vowelUu_example => 'คือ（khʉʉ＝〜である） / ฝืน（fʉ̌ʉn＝無理する）';

  @override
  String get tip_vowelIa_title => 'เอีย （ia）';

  @override
  String get tip_vowelIa_content => 'เอีย は「ia」。i から a へ滑らかにつなげます。';

  @override
  String get tip_vowelIa_example => 'เรียน（riian＝学ぶ）';

  @override
  String get tip_vowelUa_title => 'อัว （ua）';

  @override
  String get tip_vowelUa_content => 'อัว は「ua」。u から a へ滑らかにつなげます。';

  @override
  String get tip_vowelUa_example => 'ตัว（tuua＝体・匹）';

  @override
  String get tip_vowelAw_title => 'เอา （aw）';

  @override
  String get tip_vowelAw_content => 'เอา は「aw」。口を開けてからすぼめます。';

  @override
  String get tip_vowelAw_example => 'เอา（aw＝要る・取る）';

  @override
  String get tip_vowelAi_title => 'ไอ / ใอ （ai）';

  @override
  String get tip_vowelAi_content => 'ไอ と ใอ は同じ「ai」の発音。ใ を使う語は20語だけ。';

  @override
  String get tip_vowelAi_example => 'ไป（pai＝行く） / ใจ（jai＝心）';

  @override
  String get tip_vowelShortE_title => 'เอ็（短母音 e）';

  @override
  String get tip_vowelShortE_content => '短い「e」。เ〜็ の形で表記されます。';

  @override
  String get tip_vowelShortE_example => 'เก็บ（kèp＝拾う・保管する）';

  @override
  String get tip_vowelShortAe_title => 'แอ็（短母音 ɛ）';

  @override
  String get tip_vowelShortAe_content => '短い「ɛ」（口を大きく開ける）。แ〜็ の形。';

  @override
  String get tip_vowelShortAe_example => 'แบ็ก（bɛ̀k＝バッグ）';

  @override
  String get tip_vowelOe_title => 'เออ （əə）';

  @override
  String get tip_vowelOe_content => 'เออ は曖昧な母音「əə」。口を半開きにして発音。';

  @override
  String get tip_vowelOe_example => 'เธอ（thəə＝あなた・彼女）';

  @override
  String get tip_vowelLength_title => '母音の長短で意味が変わる';

  @override
  String get tip_vowelLength_content => 'タイ語は母音の長さが重要。短母音と長母音で別の単語になります。';

  @override
  String get tip_vowelLength_example => 'ปะ（pà＝出会う） / ป้า（pâa＝おばさん）';

  @override
  String get tip_cultureWai_title => 'wâi（合掌・ไหว้）';

  @override
  String get tip_cultureWai_content => '両手を合わせるタイ式挨拶。目上の人には鼻の高さ、同年代は胸の高さで。';

  @override
  String get tip_cultureTemple_title => '寺院参拝のマナー';

  @override
  String get tip_cultureTemple_content => '寺院では靴を脱ぎ、肩と膝を隠す服装で。仏像より高い位置に座らないこと。';

  @override
  String get tip_cultureSongkran_title => 'sǒngkraan（水かけ祭り）';

  @override
  String get tip_cultureSongkran_content => '毎年4月13〜15日のタイ正月。水をかけ合い新年を祝います。';

  @override
  String get tip_cultureLoyKrathong_title => 'lɔɔi krathong（灯篭流し）';

  @override
  String get tip_cultureLoyKrathong_content =>
      '陰暦12月の満月に川へ灯篭を流す祭り。水の精霊に感謝を捧げます。';

  @override
  String get tip_cultureEating_title => 'タイ料理の食べ方';

  @override
  String get tip_cultureEating_content => 'フォークとスプーンを使い、スプーンで口に運びます。箸は麺料理の時だけ。';

  @override
  String get tip_cultureMaiPenRai_title => 'ไม่เป็นไร（mâi pen rai）';

  @override
  String get tip_cultureMaiPenRai_content =>
      '「気にしないで・大丈夫」。タイ人の寛容さを表す代表的フレーズです。';

  @override
  String get tip_toneFive_title => 'タイ語は5つの声調';

  @override
  String get tip_toneFive_content => '平声・低声・下声・高声・上声の5つ。声調が違うと全く別の単語になります。';

  @override
  String get tip_toneFive_example =>
      'ไหม（mǎi＝絹） / ใหม่（mài＝新しい） / ไม่（mâi＝〜ない）';

  @override
  String get tip_toneMaiEk_title => '声調記号 ่ （mái èek）';

  @override
  String get tip_toneMaiEk_content => '文字の上に付く第1声調記号。中子音・高子音に付くと低声になります。';

  @override
  String get tip_toneMaiEk_example => 'เก่า（kàw＝古い）、ข่าว（khàaw＝ニュース）';

  @override
  String get tip_toneMaiTho_title => '声調記号 ้ （mái thoo）';

  @override
  String get tip_toneMaiTho_content => '文字の上に付く第2声調記号。中子音に付くと下声になります。';

  @override
  String get tip_toneMaiTho_example => 'น้ำ（náam＝水）、บ้าน（bâan＝家）';

  @override
  String get tip_toneMaiTriChat_title => '声調記号 ๊ と ๋';

  @override
  String get tip_toneMaiTriChat_content =>
      '๊（mái trii）は高声、๋（mái jàttawaa）は上声を示します。使用頻度は低め。';

  @override
  String get tip_toneMaiTriChat_example => 'โน๊ต（nóot＝ノート）、จ๋า（jǎa＝はいよ）';

  @override
  String get tip_toneClassRelation_title => '子音クラスと声調の関係';

  @override
  String get tip_toneClassRelation_content =>
      '声調は子音クラス（高・中・低）×母音の長短×末子音×声調記号で決まります。';

  @override
  String get tip_toneMistake_title => '声調を間違えると…';

  @override
  String get tip_toneMistake_content =>
      'สวย（sǔuai＝美しい）と ซวย（suuai＝ついてない）のように声調で意味が激変。';

  @override
  String get tip_toneMidExplain_title => '平声（sǎa-man）';

  @override
  String get tip_toneMidExplain_content =>
      '中くらいの高さで平らに発音。中子音＋長母音（声調記号なし）が基本パターン。';

  @override
  String get tip_toneMidExplain_example => 'กา（kaa＝カラス）、ดี（dii＝良い）';

  @override
  String get tip_toneRisingExplain_title => '上声（jàttawaa）';

  @override
  String get tip_toneRisingExplain_content =>
      '低い音から高い音へ上がる声調。日本語の疑問文の語尾上げに少し似ています。';

  @override
  String get tip_toneRisingExplain_example => 'สวย（sǔuai＝美しい）、หนาว（nǎaw＝寒い）';

  @override
  String get tip_toneRelative_title => '声調は相対的な高さ';

  @override
  String get tip_toneRelative_content => '声調の高さは前の音節で変わります。フレーズごと覚えるのが効果的。';

  @override
  String get tip_consonant44_title => 'タイ語は44の子音字';

  @override
  String get tip_consonant44_content =>
      '44文字ありますが、現在使われるのは42文字。発音は21種類に集約されます。';

  @override
  String get tip_consonantHigh_title => '高子音（àksɔ̌ɔn sǔung）';

  @override
  String get tip_consonantHigh_content =>
      'ข ฃ ข ฉ ฐ ถ ผ ฝ ศ ษ ส ห の11文字。声調ルールが中・低子音と異なります。';

  @override
  String get tip_consonantMid_title => '中子音（àksɔ̌ɔn klaang）';

  @override
  String get tip_consonantMid_content =>
      'ก จ ฎ ฏ ด ต บ ป อ の9文字。声調記号がそのまま反映される基本グループ。';

  @override
  String get tip_consonantLow_title => '低子音（àksɔ̌ɔn tàm）';

  @override
  String get tip_consonantLow_content =>
      '残り24文字が低子音。対応する高子音がある「対応字」と「単独字」に分かれます。';

  @override
  String get tip_consonantFinal_title => '末子音の発音ルール';

  @override
  String get tip_consonantFinal_content =>
      '末子音は k, t, p, n, m, ng, i, o の8音のみ。元の子音と違う音になることも。';

  @override
  String get tip_consonantFinal_example => 'บ,ป,พ,ภ,ฟ → 末子音ではすべて -p';

  @override
  String get tip_consonantAspiration_title => '有気音と無気音';

  @override
  String get tip_consonantAspiration_content =>
      'タイ語は息の有無で子音を区別。ป（無気音 p）と พ（有気音 ph）は別の音。';

  @override
  String get tip_consonantAspiration_example => 'ปลา（plaa＝魚） / พลา（phlaa＝失敗する）';

  @override
  String get tip_consonantSilent_title => '黙字記号 ์（kaa-ran）';

  @override
  String get tip_consonantSilent_content =>
      '文字の上に付く ์ は「この子音は読まない」という記号。外来語に多いです。';

  @override
  String get tip_consonantSilent_example => 'จันทร์（jan＝月） ← ร์ は読まない';

  @override
  String get tip_consonantCluster_title => '二重子音（àksɔ̌ɔn khûap）';

  @override
  String get tip_consonantCluster_content =>
      '子音が2つ連続する場合、一緒に発音します。kr, kl, pr, pl などのパターン。';

  @override
  String get tip_consonantCluster_example => 'กรุง（krung＝都） / ปลา（plaa＝魚）';

  @override
  String get tip_numberThai_title => 'タイ数字';

  @override
  String get tip_numberThai_content =>
      'タイには独自の数字があります。๐๑๒๓๔๕๖๗๘๙（0〜9）。看板や公文書で使われます。';

  @override
  String get tip_number1to5_title => '1〜5の読み方';

  @override
  String get tip_number1to5_content => '๑ nʉ̀ng、๒ sɔ̌ɔng、๓ sǎam、๔ sìi、๕ hâa';

  @override
  String get tip_number6to10_title => '6〜10の読み方';

  @override
  String get tip_number6to10_content => '๖ hòk、๗ jèt、๘ pɛ̀ɛt、๙ kâw、๑๐ sìp';

  @override
  String get tip_number11and21_title => '11と21の特殊な読み方';

  @override
  String get tip_number11and21_content =>
      '11は sìp èt、21は yîi sìp èt。1の位と2の十の位が特殊。';

  @override
  String get tip_numberClassifier_title => '類別詞（láksanànaam）';

  @override
  String get tip_numberClassifier_content =>
      '数を数えるとき「数詞＋類別詞」が必要。日本語の「〜本」「〜枚」と同じ仕組み。';

  @override
  String get tip_numberClassifier_example => 'khon（人）、tua（動物）、an（小物）';

  @override
  String get tip_numberBig_title => '百・千・万の位';

  @override
  String get tip_numberBig_content =>
      'rɔ́ɔi（百）、phan（千）、mʉ̀ʉn（万）、sǎen（十万）、láan（百万）';

  @override
  String get tip_numberPrice_title => '値段の聞き方';

  @override
  String get tip_numberPrice_content =>
      '「いくらですか？」は thâo rài。raakhaa（価格）と合わせて覚えましょう。';

  @override
  String get tip_numberPrice_example => 'an-níi thâo rài（これいくら？）';

  @override
  String get tip_dailyPolite_title => 'ครับ / ค่ะ（khráp / khâ）';

  @override
  String get tip_dailyPolite_content =>
      '男性は khráp（ครับ）、女性は khâ（ค่ะ）を文末に付けて丁寧にします。タイ語の基本マナー。';

  @override
  String get tip_dailyPolite_example => 'khɔ̀ɔp khun khráp / khɔ̀ɔp khun khâ';

  @override
  String get tip_dailyHello_title => 'สวัสดี（sà-wàt-dii）';

  @override
  String get tip_dailyHello_content => '「こんにちは」朝昼夜いつでも使える万能挨拶。別れ際にも使います。';

  @override
  String get tip_dailyThanks_title => 'ขอบคุณ（khɔ̀ɔp khun）';

  @override
  String get tip_dailyThanks_content => '「ありがとう」。khɔ̀ɔp khun mâak で「大変ありがとう」。';

  @override
  String get tip_dailySorry_title => 'ขอโทษ（khɔ̌ɔ thôot）';

  @override
  String get tip_dailySorry_content => '「すみません・ごめんなさい」。謝罪にも呼びかけにも使えます。';

  @override
  String get tip_dailyYesNo_title => 'ใช่ / ไม่ใช่（châi / mâi châi）';

  @override
  String get tip_dailyYesNo_content => '「はい / いいえ」。確認に対する返答に使います。';

  @override
  String get tip_dailyYesNo_example => 'châi mǎi（そうですか？）→ châi khráp（はい）';

  @override
  String get tip_dailyEat_title => 'กิน（kin）＝食べる';

  @override
  String get tip_dailyEat_content => '「ご飯食べた？」kin khâao rʉ̌ʉ yang はタイの定番挨拶です。';

  @override
  String get tip_dailyDelicious_title => 'อร่อย（à-ròi）＝おいしい';

  @override
  String get tip_dailyDelicious_content =>
      'タイ料理を食べたら à-ròi！mâak を付けると「とてもおいしい」。';

  @override
  String get tip_dailyPronouns_title => '人称代名詞の使い分け';

  @override
  String get tip_dailyPronouns_content => 'phǒm（僕）は男性、dì-chǎn（私）は女性のフォーマルな一人称。';

  @override
  String get tip_dailyPronouns_example => 'カジュアルでは rao や chǎn も使います';

  @override
  String get tip_studyThaiOnly_title => 'タイ語だけでクイズに挑戦';

  @override
  String get tip_studyThaiOnly_content => '例文や解説を見ずにタイ語だけで意味が分かるか、クイズで挑戦してみよう！';

  @override
  String get errPurchaseStatusFailed => '購入状態の取得に失敗しました';

  @override
  String get errPurchaseGeneric => '購入エラーが発生しました';

  @override
  String get purchasePending => '購入の承認待ちです。承認後に反映されます';

  @override
  String get errSignInBeforePurchase => 'ログインしてから購入してください';

  @override
  String get errPurchaseVerificationFailed => '購入の検証に失敗しました';
}
