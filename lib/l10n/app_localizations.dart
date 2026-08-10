import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja')
  ];

  /// アプリ名。タスクスイッチャーとタイトルバーに出る
  ///
  /// In ja, this message translates to:
  /// **'まいにちタイ語'**
  String get appTitle;

  /// No description provided for @settingsDisplay.
  ///
  /// In ja, this message translates to:
  /// **'表示'**
  String get settingsDisplay;

  /// No description provided for @settingsFont.
  ///
  /// In ja, this message translates to:
  /// **'フォント'**
  String get settingsFont;

  /// No description provided for @settingsFontPickerTitle.
  ///
  /// In ja, this message translates to:
  /// **'フォントを選択'**
  String get settingsFontPickerTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In ja, this message translates to:
  /// **'言語（dev専用）'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguagePickerTitle.
  ///
  /// In ja, this message translates to:
  /// **'言語を選択'**
  String get settingsLanguagePickerTitle;

  /// dev限定の言語切替ダイアログの補足。履歴が書き換わらないことを伝える
  ///
  /// In ja, this message translates to:
  /// **'dev ビルドの動作確認用です。切り替えても、すでに作った例文の訳は作成時の言語のまま残ります。'**
  String get settingsLanguageNote;

  /// No description provided for @navLearn.
  ///
  /// In ja, this message translates to:
  /// **'学習'**
  String get navLearn;

  /// No description provided for @navHistory.
  ///
  /// In ja, this message translates to:
  /// **'履歴'**
  String get navHistory;

  /// No description provided for @navSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get navSettings;

  /// No description provided for @learnQuizTitle.
  ///
  /// In ja, this message translates to:
  /// **'クイズ'**
  String get learnQuizTitle;

  /// No description provided for @learnSummaryQuizTitle.
  ///
  /// In ja, this message translates to:
  /// **'まとめクイズ'**
  String get learnSummaryQuizTitle;

  /// No description provided for @learnNextSentence.
  ///
  /// In ja, this message translates to:
  /// **'次の例文へ'**
  String get learnNextSentence;

  /// No description provided for @firstGuideTitle.
  ///
  /// In ja, this message translates to:
  /// **'まずは体験してみましょう'**
  String get firstGuideTitle;

  /// No description provided for @firstGuideBody.
  ///
  /// In ja, this message translates to:
  /// **'実際に1回、例文からクイズまで通して学習します。\n押すボタンはこのあと順番にご案内します。'**
  String get firstGuideBody;

  /// 初回ガイドで強調する体験期間。日数は PREMIUM_TRIAL_DAYS（constants.py / quota.ts）と揃えること
  ///
  /// In ja, this message translates to:
  /// **'最初の2日間はプレミアムの内容で学べます'**
  String get firstGuideTrial;

  /// No description provided for @commonOk.
  ///
  /// In ja, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonRetry.
  ///
  /// In ja, this message translates to:
  /// **'再試行'**
  String get commonRetry;

  /// No description provided for @coachDetailTitle.
  ///
  /// In ja, this message translates to:
  /// **'まずは例文をタップ'**
  String get coachDetailTitle;

  /// No description provided for @coachDetailMessage.
  ///
  /// In ja, this message translates to:
  /// **'カードをタップすると、単語ごとの意味と発音を確認できます。'**
  String get coachDetailMessage;

  /// No description provided for @coachQuizTitle.
  ///
  /// In ja, this message translates to:
  /// **'次はクイズに挑戦'**
  String get coachQuizTitle;

  /// No description provided for @coachQuizMessage.
  ///
  /// In ja, this message translates to:
  /// **'例文を読んだら、確認クイズに進みましょう。'**
  String get coachQuizMessage;

  /// No description provided for @coachPronunciationTitle.
  ///
  /// In ja, this message translates to:
  /// **'声に出して確かめる'**
  String get coachPronunciationTitle;

  /// No description provided for @coachPronunciationMessage.
  ///
  /// In ja, this message translates to:
  /// **'ボタンを押したまま読んでみましょう。声調が合っているか、その場で判定します。'**
  String get coachPronunciationMessage;

  /// No description provided for @sentencePreparing.
  ///
  /// In ja, this message translates to:
  /// **'次の例文を準備中...'**
  String get sentencePreparing;

  /// No description provided for @todaysWords.
  ///
  /// In ja, this message translates to:
  /// **'今日の学習単語'**
  String get todaysWords;

  /// No description provided for @playPronunciation.
  ///
  /// In ja, this message translates to:
  /// **'発音を再生'**
  String get playPronunciation;

  /// No description provided for @sentenceUsingWord.
  ///
  /// In ja, this message translates to:
  /// **'この単語を使った例文'**
  String get sentenceUsingWord;

  /// No description provided for @badgePremiumSentence.
  ///
  /// In ja, this message translates to:
  /// **'Premium例文'**
  String get badgePremiumSentence;

  /// No description provided for @badgeFreeSentence.
  ///
  /// In ja, this message translates to:
  /// **'Free例文'**
  String get badgeFreeSentence;

  /// No description provided for @sampleSentenceNotice.
  ///
  /// In ja, this message translates to:
  /// **'サンプル例文（履歴には保存されません）'**
  String get sampleSentenceNotice;

  /// No description provided for @sampleGreetingTranslation.
  ///
  /// In ja, this message translates to:
  /// **'こんにちは（男性の場合）'**
  String get sampleGreetingTranslation;

  /// No description provided for @sampleGreetingWord1Meaning.
  ///
  /// In ja, this message translates to:
  /// **'こんにちは、さようなら'**
  String get sampleGreetingWord1Meaning;

  /// No description provided for @sampleGreetingWord1Role.
  ///
  /// In ja, this message translates to:
  /// **'挨拶語'**
  String get sampleGreetingWord1Role;

  /// No description provided for @sampleGreetingWord2Meaning.
  ///
  /// In ja, this message translates to:
  /// **'〜です（男性の丁寧な語尾）'**
  String get sampleGreetingWord2Meaning;

  /// No description provided for @sampleGreetingWord2Role.
  ///
  /// In ja, this message translates to:
  /// **'語尾詞'**
  String get sampleGreetingWord2Role;

  /// No description provided for @sampleGreetingTopic.
  ///
  /// In ja, this message translates to:
  /// **'日常的な挨拶'**
  String get sampleGreetingTopic;

  /// No description provided for @sampleGreetingStyle.
  ///
  /// In ja, this message translates to:
  /// **'口語体'**
  String get sampleGreetingStyle;

  /// No description provided for @sampleGreetingEmotion.
  ///
  /// In ja, this message translates to:
  /// **'丁寧、フォーマル'**
  String get sampleGreetingEmotion;

  /// No description provided for @sampleGreetingUsage.
  ///
  /// In ja, this message translates to:
  /// **'朝昼晩いつでも使える基本的な挨拶。女性の場合は「ค่ะ」を使います。'**
  String get sampleGreetingUsage;

  /// No description provided for @quizTodayTitle.
  ///
  /// In ja, this message translates to:
  /// **'今日のクイズ'**
  String get quizTodayTitle;

  /// No description provided for @quizOptionalChallenge.
  ///
  /// In ja, this message translates to:
  /// **'5問チャレンジする'**
  String get quizOptionalChallenge;

  /// No description provided for @quizGenerating.
  ///
  /// In ja, this message translates to:
  /// **'クイズを生成中...'**
  String get quizGenerating;

  /// No description provided for @quizOpenSentenceFirst.
  ///
  /// In ja, this message translates to:
  /// **'まず例文を開きましょう'**
  String get quizOpenSentenceFirst;

  /// No description provided for @quizFromLearningSentence.
  ///
  /// In ja, this message translates to:
  /// **'クイズは学習中の例文から出題されます'**
  String get quizFromLearningSentence;

  /// No description provided for @quizBackToSentence.
  ///
  /// In ja, this message translates to:
  /// **'例文に戻る'**
  String get quizBackToSentence;

  /// No description provided for @quizCorrect.
  ///
  /// In ja, this message translates to:
  /// **'正解！'**
  String get quizCorrect;

  /// No description provided for @quizIncorrect.
  ///
  /// In ja, this message translates to:
  /// **'不正解'**
  String get quizIncorrect;

  /// No description provided for @quizCorrectAnswer.
  ///
  /// In ja, this message translates to:
  /// **'正解: {answer}'**
  String quizCorrectAnswer(String answer);

  /// No description provided for @quizPrompt.
  ///
  /// In ja, this message translates to:
  /// **'下線部に入る単語を選んでください'**
  String get quizPrompt;

  /// No description provided for @quizProgress.
  ///
  /// In ja, this message translates to:
  /// **'問題 {index} / {total}'**
  String quizProgress(int index, int total);

  /// No description provided for @quizSentenceReviewed.
  ///
  /// In ja, this message translates to:
  /// **'例文を復習済み'**
  String get quizSentenceReviewed;

  /// No description provided for @quizReviewSentence.
  ///
  /// In ja, this message translates to:
  /// **'例文を復習する'**
  String get quizReviewSentence;

  /// No description provided for @quizHint.
  ///
  /// In ja, this message translates to:
  /// **'ヒント'**
  String get quizHint;

  /// No description provided for @quizCheckSentence.
  ///
  /// In ja, this message translates to:
  /// **'例文を確認'**
  String get quizCheckSentence;

  /// No description provided for @quizPlaySentence.
  ///
  /// In ja, this message translates to:
  /// **'例文を再生'**
  String get quizPlaySentence;

  /// No description provided for @quizPlayWord.
  ///
  /// In ja, this message translates to:
  /// **'単語を再生'**
  String get quizPlayWord;

  /// No description provided for @quizWhyCorrect.
  ///
  /// In ja, this message translates to:
  /// **'正解理由'**
  String get quizWhyCorrect;

  /// No description provided for @quizWhyIncorrect.
  ///
  /// In ja, this message translates to:
  /// **'不正解理由'**
  String get quizWhyIncorrect;

  /// No description provided for @quizSeeResults.
  ///
  /// In ja, this message translates to:
  /// **'結果を見る'**
  String get quizSeeResults;

  /// No description provided for @quizNextQuestion.
  ///
  /// In ja, this message translates to:
  /// **'次の問題へ'**
  String get quizNextQuestion;

  /// No description provided for @commonTryAgain.
  ///
  /// In ja, this message translates to:
  /// **'もう一度試す'**
  String get commonTryAgain;

  /// No description provided for @coachQuizReviewTitle.
  ///
  /// In ja, this message translates to:
  /// **'迷ったら例文に戻れます'**
  String get coachQuizReviewTitle;

  /// No description provided for @coachQuizReviewMessage.
  ///
  /// In ja, this message translates to:
  /// **'答えに自信がないときは、ここから例文を見直してから回答できます。'**
  String get coachQuizReviewMessage;

  /// No description provided for @coachSummaryQuizTitle.
  ///
  /// In ja, this message translates to:
  /// **'まとめクイズに挑戦'**
  String get coachSummaryQuizTitle;

  /// No description provided for @coachSummaryQuizEmphasis.
  ///
  /// In ja, this message translates to:
  /// **'例文5つごと'**
  String get coachSummaryQuizEmphasis;

  /// No description provided for @coachSummaryQuizMessage.
  ///
  /// In ja, this message translates to:
  /// **'学習した内容をまとめて確認するクイズです。本来は例文5つごとに出ます。スキップして次の例文に進むこともできます。'**
  String get coachSummaryQuizMessage;

  /// No description provided for @coachTopicTitle.
  ///
  /// In ja, this message translates to:
  /// **'次の例文のテーマを選べます'**
  String get coachTopicTitle;

  /// No description provided for @coachTopicMessage.
  ///
  /// In ja, this message translates to:
  /// **'ここをタップすると、次に生成する例文のテーマ（旅行・恋愛など）を変更できます。気分に合わせて学習内容を選びましょう。'**
  String get coachTopicMessage;

  /// No description provided for @vocabScore.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコア'**
  String get vocabScore;

  /// No description provided for @vocabScoreCalculating.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコアを計算中...'**
  String get vocabScoreCalculating;

  /// No description provided for @vocabScoreUp.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコアアップ！'**
  String get vocabScoreUp;

  /// No description provided for @vocabScoreCapped.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコアが上限に達しました'**
  String get vocabScoreCapped;

  /// No description provided for @vocabScorePremiumPitch.
  ///
  /// In ja, this message translates to:
  /// **'Premiumで続きの成長を記録しよう'**
  String get vocabScorePremiumPitch;

  /// 語彙スコアの語数表示
  ///
  /// In ja, this message translates to:
  /// **'{count}語'**
  String vocabWords(int count);

  /// 増減つきの語数。delta は符号込みの文字列
  ///
  /// In ja, this message translates to:
  /// **'{delta}語'**
  String vocabWordsDelta(String delta);

  /// No description provided for @historyTitle.
  ///
  /// In ja, this message translates to:
  /// **'履歴'**
  String get historyTitle;

  /// No description provided for @historyFavoritesOnly.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りのみ表示'**
  String get historyFavoritesOnly;

  /// No description provided for @historyDeleteAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて削除'**
  String get historyDeleteAll;

  /// No description provided for @historySearchHint.
  ///
  /// In ja, this message translates to:
  /// **'タイ語または日本語で検索'**
  String get historySearchHint;

  /// No description provided for @historyEmptyFavorites.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りの例文がありません'**
  String get historyEmptyFavorites;

  /// No description provided for @historyEmptySearch.
  ///
  /// In ja, this message translates to:
  /// **'検索結果が見つかりませんでした'**
  String get historyEmptySearch;

  /// No description provided for @historyEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだ例文がありません'**
  String get historyEmpty;

  /// No description provided for @historyEmptyFavoritesHint.
  ///
  /// In ja, this message translates to:
  /// **'例文のハートアイコンをタップしてお気に入りに追加できます'**
  String get historyEmptyFavoritesHint;

  /// No description provided for @historyEmptySearchHint.
  ///
  /// In ja, this message translates to:
  /// **'別のキーワードで検索してみてください'**
  String get historyEmptySearchHint;

  /// No description provided for @historyEmptyHint.
  ///
  /// In ja, this message translates to:
  /// **'新しい例文を生成してみましょう'**
  String get historyEmptyHint;

  /// No description provided for @historyDeleteAllConfirm.
  ///
  /// In ja, this message translates to:
  /// **'すべての例文履歴を削除しますか？この操作は取り消せません。'**
  String get historyDeleteAllConfirm;

  /// No description provided for @historyDeletedAll.
  ///
  /// In ja, this message translates to:
  /// **'すべての例文を削除しました'**
  String get historyDeletedAll;

  /// No description provided for @historyDeleteFailed.
  ///
  /// In ja, this message translates to:
  /// **'削除に失敗しました: {error}'**
  String historyDeleteFailed(String error);

  /// No description provided for @historyDeleteConfirmTitle.
  ///
  /// In ja, this message translates to:
  /// **'削除の確認'**
  String get historyDeleteConfirmTitle;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In ja, this message translates to:
  /// **'この例文を削除しますか？'**
  String get historyDeleteConfirm;

  /// No description provided for @historyDeletedOne.
  ///
  /// In ja, this message translates to:
  /// **'例文を削除しました'**
  String get historyDeletedOne;

  /// No description provided for @historyWordCount.
  ///
  /// In ja, this message translates to:
  /// **'{count} 単語'**
  String historyWordCount(int count);

  /// No description provided for @commonError.
  ///
  /// In ja, this message translates to:
  /// **'エラーが発生しました'**
  String get commonError;

  /// No description provided for @commonCancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get commonDelete;

  /// No description provided for @commonUnknown.
  ///
  /// In ja, this message translates to:
  /// **'不明'**
  String get commonUnknown;

  /// No description provided for @detailTitle.
  ///
  /// In ja, this message translates to:
  /// **'例文の詳細'**
  String get detailTitle;

  /// No description provided for @detailShare.
  ///
  /// In ja, this message translates to:
  /// **'共有'**
  String get detailShare;

  /// No description provided for @detailWordBreakdown.
  ///
  /// In ja, this message translates to:
  /// **'単語の分解 ({count})'**
  String detailWordBreakdown(int count);

  /// No description provided for @detailQuizTarget.
  ///
  /// In ja, this message translates to:
  /// **'→ クイズで出題'**
  String get detailQuizTarget;

  /// No description provided for @detailTapForTone.
  ///
  /// In ja, this message translates to:
  /// **'タップして声調を確認'**
  String get detailTapForTone;

  /// No description provided for @detailContextSection.
  ///
  /// In ja, this message translates to:
  /// **'文脈・使い方'**
  String get detailContextSection;

  /// No description provided for @detailContextTopic.
  ///
  /// In ja, this message translates to:
  /// **'場面'**
  String get detailContextTopic;

  /// No description provided for @detailContextStyle.
  ///
  /// In ja, this message translates to:
  /// **'文体'**
  String get detailContextStyle;

  /// No description provided for @detailContextEmotion.
  ///
  /// In ja, this message translates to:
  /// **'感情・トーン'**
  String get detailContextEmotion;

  /// No description provided for @detailContextUsage.
  ///
  /// In ja, this message translates to:
  /// **'使用シーン'**
  String get detailContextUsage;

  /// No description provided for @detailContextCulture.
  ///
  /// In ja, this message translates to:
  /// **'文化的背景'**
  String get detailContextCulture;

  /// No description provided for @detailCreatedAt.
  ///
  /// In ja, this message translates to:
  /// **'作成日: {date}'**
  String detailCreatedAt(String date);

  /// No description provided for @detailCopied.
  ///
  /// In ja, this message translates to:
  /// **'クリップボードにコピーしました'**
  String get detailCopied;

  /// No description provided for @settingsTitle.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settingsTitle;

  /// No description provided for @settingsAccount.
  ///
  /// In ja, this message translates to:
  /// **'アカウント'**
  String get settingsAccount;

  /// No description provided for @settingsUser.
  ///
  /// In ja, this message translates to:
  /// **'ユーザー'**
  String get settingsUser;

  /// No description provided for @settingsGuest.
  ///
  /// In ja, this message translates to:
  /// **'ゲスト'**
  String get settingsGuest;

  /// No description provided for @settingsNotSignedIn.
  ///
  /// In ja, this message translates to:
  /// **'サインインしていません'**
  String get settingsNotSignedIn;

  /// No description provided for @settingsPlan.
  ///
  /// In ja, this message translates to:
  /// **'プラン'**
  String get settingsPlan;

  /// No description provided for @settingsPlanTrial.
  ///
  /// In ja, this message translates to:
  /// **'プレミアム体験中'**
  String get settingsPlanTrial;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In ja, this message translates to:
  /// **'アカウントを削除'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsSignOut.
  ///
  /// In ja, this message translates to:
  /// **'サインアウト'**
  String get settingsSignOut;

  /// No description provided for @settingsSignInToSave.
  ///
  /// In ja, this message translates to:
  /// **'サインインして進捗を保存'**
  String get settingsSignInToSave;

  /// No description provided for @settingsSignOutConfirm.
  ///
  /// In ja, this message translates to:
  /// **'サインアウトしますか？'**
  String get settingsSignOutConfirm;

  /// No description provided for @settingsDeleteAccountTitle.
  ///
  /// In ja, this message translates to:
  /// **'アカウント削除'**
  String get settingsDeleteAccountTitle;

  /// No description provided for @settingsDeleteAccountConfirm.
  ///
  /// In ja, this message translates to:
  /// **'アカウントを削除すると、サーバーおよび端末のすべての学習データが完全に削除されます。この操作は元に戻せません。'**
  String get settingsDeleteAccountConfirm;

  /// No description provided for @settingsAccountDeleted.
  ///
  /// In ja, this message translates to:
  /// **'アカウントとすべてのデータを削除しました'**
  String get settingsAccountDeleted;

  /// No description provided for @settingsFontSample.
  ///
  /// In ja, this message translates to:
  /// **'例文'**
  String get settingsFontSample;

  /// No description provided for @settingsLearningStatus.
  ///
  /// In ja, this message translates to:
  /// **'学習状況'**
  String get settingsLearningStatus;

  /// No description provided for @settingsLearningSection.
  ///
  /// In ja, this message translates to:
  /// **'学習設定'**
  String get settingsLearningSection;

  /// No description provided for @settingsToneGuide.
  ///
  /// In ja, this message translates to:
  /// **'声調ガイド'**
  String get settingsToneGuide;

  /// No description provided for @settingsToneGuideSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'タイ語の声調ルールを学ぶ'**
  String get settingsToneGuideSubtitle;

  /// No description provided for @settingsResetLearningData.
  ///
  /// In ja, this message translates to:
  /// **'学習データをリセット'**
  String get settingsResetLearningData;

  /// No description provided for @settingsResetLearningDataSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'端末の例文・クイズ履歴を削除'**
  String get settingsResetLearningDataSubtitle;

  /// No description provided for @settingsResetTitle.
  ///
  /// In ja, this message translates to:
  /// **'学習データのリセット'**
  String get settingsResetTitle;

  /// No description provided for @settingsResetConfirm.
  ///
  /// In ja, this message translates to:
  /// **'端末に保存されている例文・クイズ履歴・学習進捗がすべて削除されます。アカウントは維持されます。'**
  String get settingsResetConfirm;

  /// No description provided for @settingsResetDone.
  ///
  /// In ja, this message translates to:
  /// **'学習データをリセットしました'**
  String get settingsResetDone;

  /// No description provided for @settingsResetFailed.
  ///
  /// In ja, this message translates to:
  /// **'リセットに失敗しました'**
  String get settingsResetFailed;

  /// No description provided for @commonReset.
  ///
  /// In ja, this message translates to:
  /// **'リセット'**
  String get commonReset;

  /// No description provided for @settingsDailyNotification.
  ///
  /// In ja, this message translates to:
  /// **'毎日の例文通知'**
  String get settingsDailyNotification;

  /// No description provided for @settingsDailyNotificationSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'その日の例文をお知らせします'**
  String get settingsDailyNotificationSubtitle;

  /// No description provided for @settingsAllowNotificationInOsSettings.
  ///
  /// In ja, this message translates to:
  /// **'端末の設定で通知を許可してください'**
  String get settingsAllowNotificationInOsSettings;

  /// No description provided for @settingsNotificationTime.
  ///
  /// In ja, this message translates to:
  /// **'通知する時刻'**
  String get settingsNotificationTime;

  /// No description provided for @settingsTopic.
  ///
  /// In ja, this message translates to:
  /// **'テーマ'**
  String get settingsTopic;

  /// No description provided for @settingsTopicRandom.
  ///
  /// In ja, this message translates to:
  /// **'おまかせ'**
  String get settingsTopicRandom;

  /// No description provided for @settingsNextLevelIn.
  ///
  /// In ja, this message translates to:
  /// **'次のレベルまで あと{count}語'**
  String settingsNextLevelIn(int count);

  /// No description provided for @settingsFreeVocabLimit.
  ///
  /// In ja, this message translates to:
  /// **'Freeプランは{limit}語が上限です'**
  String settingsFreeVocabLimit(int limit);

  /// No description provided for @settingsCouldNotOpenUrl.
  ///
  /// In ja, this message translates to:
  /// **'URLを開けませんでした'**
  String get settingsCouldNotOpenUrl;

  /// No description provided for @settingsAbout.
  ///
  /// In ja, this message translates to:
  /// **'アプリについて'**
  String get settingsAbout;

  /// No description provided for @settingsTagline.
  ///
  /// In ja, this message translates to:
  /// **'毎日タイ語を学習しましょう'**
  String get settingsTagline;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In ja, this message translates to:
  /// **'プライバシーポリシー'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTerms.
  ///
  /// In ja, this message translates to:
  /// **'利用規約'**
  String get settingsTerms;

  /// No description provided for @settingsContact.
  ///
  /// In ja, this message translates to:
  /// **'お問い合わせ'**
  String get settingsContact;

  /// No description provided for @trialEndedTitle.
  ///
  /// In ja, this message translates to:
  /// **'プレミアム体験が終了しました'**
  String get trialEndedTitle;

  /// No description provided for @trialEndedBody.
  ///
  /// In ja, this message translates to:
  /// **'今日から無料プランになります。'**
  String get trialEndedBody;

  /// No description provided for @trialEndedChangeQuota.
  ///
  /// In ja, this message translates to:
  /// **'例文　1日{premium}回 → {free}回'**
  String trialEndedChangeQuota(int premium, int free);

  /// No description provided for @trialEndedChangePronunciation.
  ///
  /// In ja, this message translates to:
  /// **'発音チェック　無制限 → 1日{count}回'**
  String trialEndedChangePronunciation(int count);

  /// No description provided for @trialEndedLater.
  ///
  /// In ja, this message translates to:
  /// **'あとで'**
  String get trialEndedLater;

  /// No description provided for @trialEndedSeePremium.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムを見る'**
  String get trialEndedSeePremium;

  /// No description provided for @topicPickerTitle.
  ///
  /// In ja, this message translates to:
  /// **'テーマを選択'**
  String get topicPickerTitle;

  /// No description provided for @nextTopicPrefix.
  ///
  /// In ja, this message translates to:
  /// **'次のテーマ: '**
  String get nextTopicPrefix;

  /// No description provided for @topicName_blDrama.
  ///
  /// In ja, this message translates to:
  /// **'タイBLドラマ'**
  String get topicName_blDrama;

  /// No description provided for @topicSub_blDrama.
  ///
  /// In ja, this message translates to:
  /// **'告白、すれ違い、再会、嫉妬、裏切り、仲直り、壁ドン、あだ名呼び'**
  String get topicSub_blDrama;

  /// No description provided for @topicName_romance.
  ///
  /// In ja, this message translates to:
  /// **'恋愛・男女関係'**
  String get topicName_romance;

  /// No description provided for @topicSub_romance.
  ///
  /// In ja, this message translates to:
  /// **'告白、デート、甘い言葉、遠距離、別れ、仲直り'**
  String get topicSub_romance;

  /// No description provided for @topicName_work.
  ///
  /// In ja, this message translates to:
  /// **'仕事'**
  String get topicName_work;

  /// No description provided for @topicSub_work.
  ///
  /// In ja, this message translates to:
  /// **'報告・連絡・相談、打ち合わせ、残業申請、同僚雑談'**
  String get topicSub_work;

  /// No description provided for @topicName_greetings.
  ///
  /// In ja, this message translates to:
  /// **'あいさつ'**
  String get topicName_greetings;

  /// No description provided for @topicSub_greetings.
  ///
  /// In ja, this message translates to:
  /// **'朝・昼・夜、初対面、再会、別れ、電話'**
  String get topicSub_greetings;

  /// No description provided for @topicName_food.
  ///
  /// In ja, this message translates to:
  /// **'食べ物'**
  String get topicName_food;

  /// No description provided for @topicSub_food.
  ///
  /// In ja, this message translates to:
  /// **'注文、感想、屋台、辛さ調整、アレルギー'**
  String get topicSub_food;

  /// No description provided for @topicName_travel.
  ///
  /// In ja, this message translates to:
  /// **'旅行'**
  String get topicName_travel;

  /// No description provided for @topicSub_travel.
  ///
  /// In ja, this message translates to:
  /// **'ホテル、道案内、観光地、空港、ツアー'**
  String get topicSub_travel;

  /// No description provided for @topicName_family.
  ///
  /// In ja, this message translates to:
  /// **'家族'**
  String get topicName_family;

  /// No description provided for @topicSub_family.
  ///
  /// In ja, this message translates to:
  /// **'家族紹介、子育て、親への感謝、兄弟、家族行事'**
  String get topicSub_family;

  /// No description provided for @topicName_shopping.
  ///
  /// In ja, this message translates to:
  /// **'買い物'**
  String get topicName_shopping;

  /// No description provided for @topicSub_shopping.
  ///
  /// In ja, this message translates to:
  /// **'値段交渉、サイズ・色の確認、返品、ナイトマーケット'**
  String get topicSub_shopping;

  /// No description provided for @topicName_transport.
  ///
  /// In ja, this message translates to:
  /// **'交通'**
  String get topicName_transport;

  /// No description provided for @topicSub_transport.
  ///
  /// In ja, this message translates to:
  /// **'Grab、BTS、バイタク、ソンテウ、渋滞'**
  String get topicSub_transport;

  /// No description provided for @topicName_health.
  ///
  /// In ja, this message translates to:
  /// **'健康'**
  String get topicName_health;

  /// No description provided for @topicSub_health.
  ///
  /// In ja, this message translates to:
  /// **'症状説明、薬局、マッサージ、健康診断'**
  String get topicSub_health;

  /// No description provided for @topicName_weather.
  ///
  /// In ja, this message translates to:
  /// **'天気'**
  String get topicName_weather;

  /// No description provided for @topicSub_weather.
  ///
  /// In ja, this message translates to:
  /// **'暑さ、雨季、台風、日焼け対策'**
  String get topicSub_weather;

  /// No description provided for @topicName_hobbies.
  ///
  /// In ja, this message translates to:
  /// **'趣味'**
  String get topicName_hobbies;

  /// No description provided for @topicSub_hobbies.
  ///
  /// In ja, this message translates to:
  /// **'ムエタイ、音楽、映画、ゴルフ、SNS、ゲーム'**
  String get topicSub_hobbies;

  /// No description provided for @topicName_school.
  ///
  /// In ja, this message translates to:
  /// **'学校'**
  String get topicName_school;

  /// No description provided for @topicSub_school.
  ///
  /// In ja, this message translates to:
  /// **'授業中、宿題、試験、放課後、語学学校'**
  String get topicSub_school;

  /// No description provided for @topicName_religion.
  ///
  /// In ja, this message translates to:
  /// **'宗教・信仰'**
  String get topicName_religion;

  /// No description provided for @topicSub_religion.
  ///
  /// In ja, this message translates to:
  /// **'寺院マナー、托鉢、お守り、僧侶への話し方、仏教行事'**
  String get topicSub_religion;

  /// No description provided for @topicName_festivals.
  ///
  /// In ja, this message translates to:
  /// **'伝統・祭り'**
  String get topicName_festivals;

  /// No description provided for @topicSub_festivals.
  ///
  /// In ja, this message translates to:
  /// **'ソンクラーン、ロイクラトン、王室行事、地域の伝統料理'**
  String get topicSub_festivals;

  /// No description provided for @topicName_etiquette.
  ///
  /// In ja, this message translates to:
  /// **'礼儀作法'**
  String get topicName_etiquette;

  /// No description provided for @topicSub_etiquette.
  ///
  /// In ja, this message translates to:
  /// **'ワイの使い分け、敬語、タブー、食事マナー、贈り物'**
  String get topicSub_etiquette;

  /// 文体ラベル。値は constants.STYLES の識別子で、表示だけ差し替える
  ///
  /// In ja, this message translates to:
  /// **'ニュース記事体'**
  String get styleName_news;

  /// No description provided for @styleName_spoken.
  ///
  /// In ja, this message translates to:
  /// **'口語体'**
  String get styleName_spoken;

  /// No description provided for @styleName_polite.
  ///
  /// In ja, this message translates to:
  /// **'丁寧語'**
  String get styleName_polite;

  /// No description provided for @styleName_sns.
  ///
  /// In ja, this message translates to:
  /// **'SNS・テキストメッセージ'**
  String get styleName_sns;

  /// No description provided for @styleName_narrative.
  ///
  /// In ja, this message translates to:
  /// **'物語・文学体'**
  String get styleName_narrative;

  /// No description provided for @vocabLevelIntro.
  ///
  /// In ja, this message translates to:
  /// **'入門'**
  String get vocabLevelIntro;

  /// No description provided for @vocabLevelBeginner.
  ///
  /// In ja, this message translates to:
  /// **'初級'**
  String get vocabLevelBeginner;

  /// No description provided for @vocabLevelUpperBeginner.
  ///
  /// In ja, this message translates to:
  /// **'初中級'**
  String get vocabLevelUpperBeginner;

  /// No description provided for @vocabLevelIntermediate.
  ///
  /// In ja, this message translates to:
  /// **'中級'**
  String get vocabLevelIntermediate;

  /// No description provided for @vocabLevelAdvanced.
  ///
  /// In ja, this message translates to:
  /// **'上級'**
  String get vocabLevelAdvanced;

  /// No description provided for @vocabDialogTitle.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコア（{level}）'**
  String vocabDialogTitle(String level);

  /// No description provided for @vocabDialogTitleFree.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコア（Free・{level}）'**
  String vocabDialogTitleFree(String level);

  /// No description provided for @vocabProgressOf.
  ///
  /// In ja, this message translates to:
  /// **'{current} / {threshold} 語'**
  String vocabProgressOf(int current, int threshold);

  /// No description provided for @vocabFreeCap.
  ///
  /// In ja, this message translates to:
  /// **'Free上限'**
  String get vocabFreeCap;

  /// No description provided for @vocabRemaining.
  ///
  /// In ja, this message translates to:
  /// **'残り{count}語'**
  String vocabRemaining(int count);

  /// No description provided for @vocabCurrentTopics.
  ///
  /// In ja, this message translates to:
  /// **'現在のテーマ数（{count}件）'**
  String vocabCurrentTopics(int count);

  /// No description provided for @vocabFreeTopics.
  ///
  /// In ja, this message translates to:
  /// **'Freeのテーマ数（{count}件）'**
  String vocabFreeTopics(int count);

  /// No description provided for @vocabNextUnlock.
  ///
  /// In ja, this message translates to:
  /// **'次の開放（+{count}件）'**
  String vocabNextUnlock(int count);

  /// No description provided for @vocabNextUnlockIn.
  ///
  /// In ja, this message translates to:
  /// **'あと{words}語で開放（+{count}件）'**
  String vocabNextUnlockIn(int words, int count);

  /// No description provided for @vocabSeePremium.
  ///
  /// In ja, this message translates to:
  /// **'Premiumを見る'**
  String get vocabSeePremium;

  /// No description provided for @commonClose.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get commonClose;

  /// No description provided for @vocabFreeLimitTitle.
  ///
  /// In ja, this message translates to:
  /// **'Freeは100語が上限です'**
  String get vocabFreeLimitTitle;

  /// No description provided for @vocabFreeLimitBody.
  ///
  /// In ja, this message translates to:
  /// **'Premiumでは100語以上学べます。また例文のテーマが増え、より多様なタイ語が学べます。'**
  String get vocabFreeLimitBody;

  /// No description provided for @vocabUnlockMore.
  ///
  /// In ja, this message translates to:
  /// **'語彙スコアが増えると次の例文テーマが開放されます。'**
  String get vocabUnlockMore;

  /// No description provided for @vocabTopicCountNow.
  ///
  /// In ja, this message translates to:
  /// **'例文テーマ候補は現在{count}件です。'**
  String vocabTopicCountNow(int count);

  /// No description provided for @vocabPremiumAddsTopics.
  ///
  /// In ja, this message translates to:
  /// **'Premiumで追加されるテーマ数（{count}件）'**
  String vocabPremiumAddsTopics(int count);

  /// No description provided for @listSeparator.
  ///
  /// In ja, this message translates to:
  /// **'、'**
  String get listSeparator;

  /// No description provided for @paywallTitle.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムプラン'**
  String get paywallTitle;

  /// No description provided for @paywallTagline.
  ///
  /// In ja, this message translates to:
  /// **'推しの言葉が、わかる日が来る。'**
  String get paywallTagline;

  /// No description provided for @paywallSignInRequired.
  ///
  /// In ja, this message translates to:
  /// **'サインインが必要です'**
  String get paywallSignInRequired;

  /// No description provided for @paywallSignInForPurchase.
  ///
  /// In ja, this message translates to:
  /// **'購入を機種変更後も引き継ぐため、サインインしてください。'**
  String get paywallSignInForPurchase;

  /// No description provided for @paywallSignInForRestore.
  ///
  /// In ja, this message translates to:
  /// **'購入を復元するには、購入時のアカウントでサインインしてください。'**
  String get paywallSignInForRestore;

  /// No description provided for @paywallActive.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムプランに加入中です'**
  String get paywallActive;

  /// No description provided for @paywallSubscribe.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムに登録'**
  String get paywallSubscribe;

  /// No description provided for @paywallLegal.
  ///
  /// In ja, this message translates to:
  /// **'サブスクリプションは自動更新です。期間終了24時間前までにキャンセルできます。更新料金は終了24時間以内に請求され、管理・キャンセルはApp Storeのアカウント設定から行えます。'**
  String get paywallLegal;

  /// No description provided for @paywallRestore.
  ///
  /// In ja, this message translates to:
  /// **'購入を復元'**
  String get paywallRestore;

  /// No description provided for @paywallPriceYen.
  ///
  /// In ja, this message translates to:
  /// **'¥{amount} / 月'**
  String paywallPriceYen(String amount);

  /// No description provided for @paywallPrice.
  ///
  /// In ja, this message translates to:
  /// **'{currency} {amount} / 月'**
  String paywallPrice(String currency, String amount);

  /// No description provided for @paywallFeatureQuotaTitle.
  ///
  /// In ja, this message translates to:
  /// **'例文をたくさん学べる'**
  String get paywallFeatureQuotaTitle;

  /// No description provided for @paywallFeatureQuotaCount.
  ///
  /// In ja, this message translates to:
  /// **'例文{count}回/日'**
  String paywallFeatureQuotaCount(int count);

  /// No description provided for @paywallFeature1Title.
  ///
  /// In ja, this message translates to:
  /// **'タイ人が使う言い回しで学べる'**
  String get paywallFeature1Title;

  /// No description provided for @paywallFeature1Free.
  ///
  /// In ja, this message translates to:
  /// **'教科書的な基礎文'**
  String get paywallFeature1Free;

  /// No description provided for @paywallFeature1Premium.
  ///
  /// In ja, this message translates to:
  /// **'タイ人の自然な言い回し'**
  String get paywallFeature1Premium;

  /// No description provided for @paywallFeaturePronunciationTitle.
  ///
  /// In ja, this message translates to:
  /// **'発音を繰り返し確認できる'**
  String get paywallFeaturePronunciationTitle;

  /// No description provided for @paywallFeaturePronunciationFree.
  ///
  /// In ja, this message translates to:
  /// **'発音チェック{count}回/日'**
  String paywallFeaturePronunciationFree(int count);

  /// No description provided for @paywallFeaturePronunciationPremium.
  ///
  /// In ja, this message translates to:
  /// **'無制限'**
  String get paywallFeaturePronunciationPremium;

  /// No description provided for @paywallFeatureOtherTitle.
  ///
  /// In ja, this message translates to:
  /// **'その他のプレミアム特典'**
  String get paywallFeatureOtherTitle;

  /// No description provided for @paywallFeatureOtherTopic.
  ///
  /// In ja, this message translates to:
  /// **'学びたいテーマを自由に選べる'**
  String get paywallFeatureOtherTopic;

  /// No description provided for @paywallFeatureOtherVocab.
  ///
  /// In ja, this message translates to:
  /// **'単語数の上限（Freeは{limit}語）が外れ、ドラマのセリフも理解できる'**
  String paywallFeatureOtherVocab(int limit);

  /// No description provided for @paywallTrialActive.
  ///
  /// In ja, this message translates to:
  /// **'いまはプレミアム体験中です。期間が終わると、ここは元の内容に戻ります。'**
  String get paywallTrialActive;

  /// No description provided for @paywallTrialEnded.
  ///
  /// In ja, this message translates to:
  /// **'体験期間中に使えていた機能です。'**
  String get paywallTrialEnded;

  /// No description provided for @onboarding1Title.
  ///
  /// In ja, this message translates to:
  /// **'AIがタイ語例文を毎日生成'**
  String get onboarding1Title;

  /// No description provided for @onboarding1Body.
  ///
  /// In ja, this message translates to:
  /// **'毎日新しい例文が届きます。\nカードをタップで単語・意味を確認。'**
  String get onboarding1Body;

  /// No description provided for @onboarding2Title.
  ///
  /// In ja, this message translates to:
  /// **'声調を含めた発音練習'**
  String get onboarding2Title;

  /// No description provided for @onboarding2Body.
  ///
  /// In ja, this message translates to:
  /// **'お手本を聞いて自分の声を録音。\n声調のズレをその場で確認できます。'**
  String get onboarding2Body;

  /// No description provided for @onboarding3Title.
  ///
  /// In ja, this message translates to:
  /// **'クイズで語彙スコアUP'**
  String get onboarding3Title;

  /// No description provided for @onboarding3Body.
  ///
  /// In ja, this message translates to:
  /// **'間違えた単語はくり返し出題。\nスコアに応じて例文のレベルが上がります。'**
  String get onboarding3Body;

  /// No description provided for @onboardingSkip.
  ///
  /// In ja, this message translates to:
  /// **'スキップ'**
  String get onboardingSkip;

  /// No description provided for @onboardingStart.
  ///
  /// In ja, this message translates to:
  /// **'はじめる'**
  String get onboardingStart;

  /// No description provided for @onboardingNext.
  ///
  /// In ja, this message translates to:
  /// **'次へ'**
  String get onboardingNext;

  /// No description provided for @notifCoachTitle.
  ///
  /// In ja, this message translates to:
  /// **'例文を毎日の習慣に'**
  String get notifCoachTitle;

  /// No description provided for @notifCoachStep1.
  ///
  /// In ja, this message translates to:
  /// **'通勤中や寝る前など、学習を続けやすい時刻を決めます'**
  String get notifCoachStep1;

  /// No description provided for @notifCoachStep2.
  ///
  /// In ja, this message translates to:
  /// **'その時刻に、あなた向けの1例文が自動で届きます'**
  String get notifCoachStep2;

  /// No description provided for @notifCoachHabit.
  ///
  /// In ja, this message translates to:
  /// **'毎日同じ時間に開くので、習慣になります'**
  String get notifCoachHabit;

  /// No description provided for @notifCoachPreviewLabel.
  ///
  /// In ja, this message translates to:
  /// **'通知の例）'**
  String get notifCoachPreviewLabel;

  /// No description provided for @notifCoachFooter.
  ///
  /// In ja, this message translates to:
  /// **'通知をタップで学習画面へ。時刻は設定で変更できます。'**
  String get notifCoachFooter;

  /// No description provided for @notifCoachNow.
  ///
  /// In ja, this message translates to:
  /// **'今'**
  String get notifCoachNow;

  /// No description provided for @notifCoachSampleTitle.
  ///
  /// In ja, this message translates to:
  /// **'🇹🇭 今日のタイ語 · ขอบคุณ（ありがとう）'**
  String get notifCoachSampleTitle;

  /// No description provided for @notifCoachSampleBody.
  ///
  /// In ja, this message translates to:
  /// **'→ コーヒーをありがとうございます'**
  String get notifCoachSampleBody;

  /// No description provided for @notifCoachEnable.
  ///
  /// In ja, this message translates to:
  /// **'通知をオンにする'**
  String get notifCoachEnable;

  /// No description provided for @notifCoachLater.
  ///
  /// In ja, this message translates to:
  /// **'あとで'**
  String get notifCoachLater;

  /// No description provided for @notifCoachEnabled.
  ///
  /// In ja, this message translates to:
  /// **'毎日この時間に例文をお届けします。時刻は設定で変更できます。'**
  String get notifCoachEnabled;

  /// No description provided for @commonGotIt.
  ///
  /// In ja, this message translates to:
  /// **'わかった'**
  String get commonGotIt;

  /// No description provided for @premiumHint1Title.
  ///
  /// In ja, this message translates to:
  /// **'学びたいテーマを自由に選べる'**
  String get premiumHint1Title;

  /// No description provided for @premiumHint1Body.
  ///
  /// In ja, this message translates to:
  /// **'タイドラマ・恋愛・旅行など、次の例文のテーマを指定できます'**
  String get premiumHint1Body;

  /// No description provided for @premiumHint2Title.
  ///
  /// In ja, this message translates to:
  /// **'タイ人が使う言い回しで学べる'**
  String get premiumHint2Title;

  /// No description provided for @premiumHint2Body.
  ///
  /// In ja, this message translates to:
  /// **'教科書的な基礎文から、タイ人の自然な言い回しへ'**
  String get premiumHint2Body;

  /// No description provided for @premiumHint3Title.
  ///
  /// In ja, this message translates to:
  /// **'単語数の上限が外れる'**
  String get premiumHint3Title;

  /// No description provided for @premiumHint3Body.
  ///
  /// In ja, this message translates to:
  /// **'基礎100語の先へ。ドラマのセリフも理解できる'**
  String get premiumHint3Body;

  /// No description provided for @signInReminderTitle.
  ///
  /// In ja, this message translates to:
  /// **'学習の進捗を保護'**
  String get signInReminderTitle;

  /// No description provided for @signInReminderMessage.
  ///
  /// In ja, this message translates to:
  /// **'サインインすると進捗が保存され、機種変更後も学習を続けられます。サインインしない場合、3日間ご利用がないと学習の進捗は削除されます。'**
  String get signInReminderMessage;

  /// No description provided for @signInReminderBanner.
  ///
  /// In ja, this message translates to:
  /// **'学習データを保護しましょう\nサインインしないと、3日間ご利用がない場合に学習の進捗が削除されます。'**
  String get signInReminderBanner;

  /// No description provided for @commonLater.
  ///
  /// In ja, this message translates to:
  /// **'あとで'**
  String get commonLater;

  /// No description provided for @signIn.
  ///
  /// In ja, this message translates to:
  /// **'サインイン'**
  String get signIn;

  /// No description provided for @signInSheetMessage.
  ///
  /// In ja, this message translates to:
  /// **'進捗を保存し、機種変更後も学習を続けられます。'**
  String get signInSheetMessage;

  /// No description provided for @signInWithApple.
  ///
  /// In ja, this message translates to:
  /// **'Appleでサインイン'**
  String get signInWithApple;

  /// No description provided for @signInWithGoogle.
  ///
  /// In ja, this message translates to:
  /// **'Googleでサインイン'**
  String get signInWithGoogle;

  /// No description provided for @quizOfferToQuiz.
  ///
  /// In ja, this message translates to:
  /// **'確認クイズへ'**
  String get quizOfferToQuiz;

  /// No description provided for @quizOfferOneQuestion.
  ///
  /// In ja, this message translates to:
  /// **'覚えたか確認'**
  String get quizOfferOneQuestion;

  /// No description provided for @quizOfferBody.
  ///
  /// In ja, this message translates to:
  /// **'この例文の単語を覚えたか、すぐ確認できます。'**
  String get quizOfferBody;

  /// No description provided for @quizOfferTryOne.
  ///
  /// In ja, this message translates to:
  /// **'確認する'**
  String get quizOfferTryOne;

  /// No description provided for @audioRepeat.
  ///
  /// In ja, this message translates to:
  /// **'リピート'**
  String get audioRepeat;

  /// No description provided for @audioOnce.
  ///
  /// In ja, this message translates to:
  /// **'1回だけ'**
  String get audioOnce;

  /// No description provided for @audioPause.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get audioPause;

  /// No description provided for @audioPlay.
  ///
  /// In ja, this message translates to:
  /// **'再生'**
  String get audioPlay;

  /// No description provided for @audioModeHint.
  ///
  /// In ja, this message translates to:
  /// **'現在は{mode}。長押しで再生モードを変更'**
  String audioModeHint(String mode);

  /// No description provided for @audioModeRepeat.
  ///
  /// In ja, this message translates to:
  /// **'リピート再生'**
  String get audioModeRepeat;

  /// No description provided for @audioModeOnce.
  ///
  /// In ja, this message translates to:
  /// **'1回だけ再生'**
  String get audioModeOnce;

  /// No description provided for @audioPosition.
  ///
  /// In ja, this message translates to:
  /// **'再生位置'**
  String get audioPosition;

  /// No description provided for @pronunciationTitle.
  ///
  /// In ja, this message translates to:
  /// **'発音してみる'**
  String get pronunciationTitle;

  /// No description provided for @pronunciationHoldToSpeak.
  ///
  /// In ja, this message translates to:
  /// **'押したまま話す'**
  String get pronunciationHoldToSpeak;

  /// No description provided for @pronunciationRecording.
  ///
  /// In ja, this message translates to:
  /// **'録音中… 指を離すと判定'**
  String get pronunciationRecording;

  /// No description provided for @pronunciationAnalyzing.
  ///
  /// In ja, this message translates to:
  /// **'判定中…'**
  String get pronunciationAnalyzing;

  /// No description provided for @pronunciationRetry.
  ///
  /// In ja, this message translates to:
  /// **'もう一度'**
  String get pronunciationRetry;

  /// No description provided for @pronunciationReference.
  ///
  /// In ja, this message translates to:
  /// **'お手本'**
  String get pronunciationReference;

  /// No description provided for @pronunciationYours.
  ///
  /// In ja, this message translates to:
  /// **'あなた'**
  String get pronunciationYours;

  /// No description provided for @pronunciationTapWordHint.
  ///
  /// In ja, this message translates to:
  /// **'語をタップすると、どこがずれたか見られます'**
  String get pronunciationTapWordHint;

  /// No description provided for @pronunciationScore.
  ///
  /// In ja, this message translates to:
  /// **'{score}点'**
  String pronunciationScore(int score);

  /// No description provided for @pronunciationVerdictCorrect.
  ///
  /// In ja, this message translates to:
  /// **'合っています'**
  String get pronunciationVerdictCorrect;

  /// No description provided for @pronunciationVerdictClose.
  ///
  /// In ja, this message translates to:
  /// **'惜しい'**
  String get pronunciationVerdictClose;

  /// No description provided for @pronunciationVerdictWrong.
  ///
  /// In ja, this message translates to:
  /// **'ずれています'**
  String get pronunciationVerdictWrong;

  /// No description provided for @pronunciationVerdictUnscored.
  ///
  /// In ja, this message translates to:
  /// **'判定できず'**
  String get pronunciationVerdictUnscored;

  /// No description provided for @pronunciationTooQuiet.
  ///
  /// In ja, this message translates to:
  /// **'声が拾えませんでした。静かな場所でもう一度お試しください'**
  String get pronunciationTooQuiet;

  /// No description provided for @pronunciationNoSpeakerRange.
  ///
  /// In ja, this message translates to:
  /// **'声の高さが読み取れませんでした。もう一度お試しください'**
  String get pronunciationNoSpeakerRange;

  /// No description provided for @pronunciationNoSyllables.
  ///
  /// In ja, this message translates to:
  /// **'この例文は発音練習に対応していません'**
  String get pronunciationNoSyllables;

  /// No description provided for @pronunciationMonotone.
  ///
  /// In ja, this message translates to:
  /// **'声の高さがほとんど動いていません。お手本を聞いて、上げ下げを付けてもう一度'**
  String get pronunciationMonotone;

  /// No description provided for @pronunciationCaptureFailed.
  ///
  /// In ja, this message translates to:
  /// **'マイクから音声を取得できませんでした。もう一度お試しください'**
  String get pronunciationCaptureFailed;

  /// No description provided for @pronunciationPermissionTitle.
  ///
  /// In ja, this message translates to:
  /// **'マイクの使用を許可してください'**
  String get pronunciationPermissionTitle;

  /// No description provided for @pronunciationPermissionBody.
  ///
  /// In ja, this message translates to:
  /// **'発音を判定するためにマイクを使います。録音した音声は端末の中だけで処理され、どこにも送信されません。'**
  String get pronunciationPermissionBody;

  /// No description provided for @pronunciationPermissionOpenSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定を開く'**
  String get pronunciationPermissionOpenSettings;

  /// No description provided for @pronunciationBandCombined.
  ///
  /// In ja, this message translates to:
  /// **'線の色＝声調と発音を合わせた判定'**
  String get pronunciationBandCombined;

  /// No description provided for @pronunciationSpeechRecognized.
  ///
  /// In ja, this message translates to:
  /// **'発音（子音・母音）：通じました'**
  String get pronunciationSpeechRecognized;

  /// No description provided for @pronunciationSpeechMissing.
  ///
  /// In ja, this message translates to:
  /// **'発音（子音・母音）：通じませんでした'**
  String get pronunciationSpeechMissing;

  /// No description provided for @pronunciationSpeechUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'いまは発音（子音・母音）を判定できません。声調だけを見ています'**
  String get pronunciationSpeechUnavailable;

  /// No description provided for @pronunciationSpeechNoAsset.
  ///
  /// In ja, this message translates to:
  /// **'この端末にタイ語の音声入力が入っていないため、発音（子音・母音）は判定できません。声調だけを見ています'**
  String get pronunciationSpeechNoAsset;

  /// No description provided for @pronunciationSpeechNoAssetHow.
  ///
  /// In ja, this message translates to:
  /// **'「設定」→「一般」→「キーボード」でタイ語のキーボードを追加し、音声入力をオンにすると使えるようになります。'**
  String get pronunciationSpeechNoAssetHow;

  /// No description provided for @pronunciationSpeechAuthDenied.
  ///
  /// In ja, this message translates to:
  /// **'音声認識が許可されていないため、発音（子音・母音）は判定できません。声調だけを見ています'**
  String get pronunciationSpeechAuthDenied;

  /// No description provided for @pronunciationSpeechAndroid.
  ///
  /// In ja, this message translates to:
  /// **'Android では発音（子音・母音）の判定に対応していません。声調だけを見ています'**
  String get pronunciationSpeechAndroid;

  /// No description provided for @pronunciationCoachLead.
  ///
  /// In ja, this message translates to:
  /// **'次はここを直す'**
  String get pronunciationCoachLead;

  /// No description provided for @pronunciationCoachShapeMid.
  ///
  /// In ja, this message translates to:
  /// **'平声は、高さを変えずに平らに伸ばす'**
  String get pronunciationCoachShapeMid;

  /// No description provided for @pronunciationCoachShapeLow.
  ///
  /// In ja, this message translates to:
  /// **'低声は、低いところで下げ気味のまま保つ'**
  String get pronunciationCoachShapeLow;

  /// No description provided for @pronunciationCoachShapeFalling.
  ///
  /// In ja, this message translates to:
  /// **'下降声は、高いところから始めて最後まで下げ切る'**
  String get pronunciationCoachShapeFalling;

  /// No description provided for @pronunciationCoachShapeHigh.
  ///
  /// In ja, this message translates to:
  /// **'高声は、上げたところで止めずに最後まで上げ続ける'**
  String get pronunciationCoachShapeHigh;

  /// No description provided for @pronunciationCoachShapeRising.
  ///
  /// In ja, this message translates to:
  /// **'上昇声は、一度下げてから上げ切る'**
  String get pronunciationCoachShapeRising;

  /// No description provided for @pronunciationCoachStepUp.
  ///
  /// In ja, this message translates to:
  /// **'{tone}は、直前の音より高いところから入る'**
  String pronunciationCoachStepUp(String tone);

  /// No description provided for @pronunciationCoachStepDown.
  ///
  /// In ja, this message translates to:
  /// **'{tone}は、直前の音より低いところから入る'**
  String pronunciationCoachStepDown(String tone);

  /// No description provided for @pronunciationCoachNotRecognized.
  ///
  /// In ja, this message translates to:
  /// **'「{word}」が聞き取れませんでした。もう少しはっきり言ってみる'**
  String pronunciationCoachNotRecognized(String word);

  /// No description provided for @pronunciationLimitTitle.
  ///
  /// In ja, this message translates to:
  /// **'今日の無料の発音チェックは終わりました'**
  String get pronunciationLimitTitle;

  /// No description provided for @pronunciationLimitBody.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムなら回数を気にせず、何度でも発音を確かめられます。'**
  String get pronunciationLimitBody;

  /// No description provided for @pronunciationFreeRemaining.
  ///
  /// In ja, this message translates to:
  /// **'無料の発音チェック 残り{count}回'**
  String pronunciationFreeRemaining(int count);

  /// No description provided for @tipWithExample.
  ///
  /// In ja, this message translates to:
  /// **'{content}\n例: {example}'**
  String tipWithExample(String content, String example);

  /// No description provided for @errQuizGenerationFailed.
  ///
  /// In ja, this message translates to:
  /// **'クイズの生成に失敗しました。もう一度お試しください。'**
  String get errQuizGenerationFailed;

  /// No description provided for @quotaQuizReached.
  ///
  /// In ja, this message translates to:
  /// **'本日のクイズ生成上限に達しました。'**
  String get quotaQuizReached;

  /// 上限回数は tier で異なる（free 5 / premium 10）ため文言に数字を含めない
  ///
  /// In ja, this message translates to:
  /// **'本日の例文生成上限に達しました。\nまた明日ご利用ください。'**
  String get quotaSentenceReached;

  /// No description provided for @errAuth.
  ///
  /// In ja, this message translates to:
  /// **'認証エラーが発生しました。アプリを再起動してください。'**
  String get errAuth;

  /// No description provided for @errNetwork.
  ///
  /// In ja, this message translates to:
  /// **'ネットワーク接続エラーが発生しました。インターネット接続を確認してください。'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In ja, this message translates to:
  /// **'リクエストがタイムアウトしました。もう一度お試しください。'**
  String get errTimeout;

  /// No description provided for @errServer.
  ///
  /// In ja, this message translates to:
  /// **'サーバーエラーが発生しました。しばらく待ってから再試行してください。'**
  String get errServer;

  /// No description provided for @errSentenceGenerationFailed.
  ///
  /// In ja, this message translates to:
  /// **'例文の生成に失敗しました。もう一度お試しください。'**
  String get errSentenceGenerationFailed;

  /// No description provided for @errLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'データの読み込みに失敗しました'**
  String get errLoadFailed;

  /// No description provided for @errLoadFailedRetry.
  ///
  /// In ja, this message translates to:
  /// **'データの読み込みに失敗しました。もう一度お試しください。'**
  String get errLoadFailedRetry;

  /// No description provided for @errUnexpected.
  ///
  /// In ja, this message translates to:
  /// **'予期しないエラーが発生しました: {error}'**
  String errUnexpected(String error);

  /// No description provided for @errSignInRequiredForPremium.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムのご利用にはサインインが必要です'**
  String get errSignInRequiredForPremium;

  /// No description provided for @errProductLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'課金商品を取得できませんでした'**
  String get errProductLoadFailed;

  /// No description provided for @errPurchaseStartFailed.
  ///
  /// In ja, this message translates to:
  /// **'購入を開始できませんでした'**
  String get errPurchaseStartFailed;

  /// No description provided for @errStoreUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'App Storeに接続できませんでした'**
  String get errStoreUnavailable;

  /// No description provided for @errNothingToRestore.
  ///
  /// In ja, this message translates to:
  /// **'復元できる購入が見つかりませんでした'**
  String get errNothingToRestore;

  /// No description provided for @errRestoreFailed.
  ///
  /// In ja, this message translates to:
  /// **'復元に失敗しました'**
  String get errRestoreFailed;

  /// No description provided for @errGoogleSignInFailed.
  ///
  /// In ja, this message translates to:
  /// **'Googleサインインに失敗しました'**
  String get errGoogleSignInFailed;

  /// No description provided for @errAppleSignInFailed.
  ///
  /// In ja, this message translates to:
  /// **'Appleサインインに失敗しました'**
  String get errAppleSignInFailed;

  /// No description provided for @errSignOutFailed.
  ///
  /// In ja, this message translates to:
  /// **'サインアウトに失敗しました'**
  String get errSignOutFailed;

  /// No description provided for @errDeleteAccountFailed.
  ///
  /// In ja, this message translates to:
  /// **'アカウント削除に失敗しました'**
  String get errDeleteAccountFailed;

  /// No description provided for @quotaResetInHours.
  ///
  /// In ja, this message translates to:
  /// **'次のリセットまで {hours}時間{minutes}分'**
  String quotaResetInHours(int hours, int minutes);

  /// No description provided for @quotaResetInMinutes.
  ///
  /// In ja, this message translates to:
  /// **'次のリセットまで {minutes}分'**
  String quotaResetInMinutes(int minutes);

  /// No description provided for @shareTopic.
  ///
  /// In ja, this message translates to:
  /// **'【場面】{value}'**
  String shareTopic(String value);

  /// No description provided for @shareStyle.
  ///
  /// In ja, this message translates to:
  /// **'【文体】{value}'**
  String shareStyle(String value);

  /// No description provided for @shareEmotion.
  ///
  /// In ja, this message translates to:
  /// **'【トーン】{value}'**
  String shareEmotion(String value);

  /// No description provided for @shareUsage.
  ///
  /// In ja, this message translates to:
  /// **'【使用シーン】{value}'**
  String shareUsage(String value);

  /// No description provided for @shareCulture.
  ///
  /// In ja, this message translates to:
  /// **'【文化的背景】{value}'**
  String shareCulture(String value);

  /// No description provided for @contactSent.
  ///
  /// In ja, this message translates to:
  /// **'お問い合わせを送信しました。ありがとうございます。'**
  String get contactSent;

  /// No description provided for @contactFailed.
  ///
  /// In ja, this message translates to:
  /// **'送信に失敗しました。しばらくしてから再度お試しください。'**
  String get contactFailed;

  /// No description provided for @contactName.
  ///
  /// In ja, this message translates to:
  /// **'お名前'**
  String get contactName;

  /// No description provided for @contactNameRequired.
  ///
  /// In ja, this message translates to:
  /// **'お名前を入力してください'**
  String get contactNameRequired;

  /// No description provided for @contactEmail.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレス'**
  String get contactEmail;

  /// No description provided for @contactEmailRequired.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスを入力してください'**
  String get contactEmailRequired;

  /// No description provided for @contactEmailInvalid.
  ///
  /// In ja, this message translates to:
  /// **'正しいメールアドレスを入力してください'**
  String get contactEmailInvalid;

  /// No description provided for @contactBody.
  ///
  /// In ja, this message translates to:
  /// **'お問い合わせ内容'**
  String get contactBody;

  /// No description provided for @contactBodyRequired.
  ///
  /// In ja, this message translates to:
  /// **'お問い合わせ内容を入力してください'**
  String get contactBodyRequired;

  /// No description provided for @contactSubmit.
  ///
  /// In ja, this message translates to:
  /// **'送信する'**
  String get contactSubmit;

  /// No description provided for @consonantClassHigh.
  ///
  /// In ja, this message translates to:
  /// **'高子音'**
  String get consonantClassHigh;

  /// No description provided for @consonantClassMiddle.
  ///
  /// In ja, this message translates to:
  /// **'中子音'**
  String get consonantClassMiddle;

  /// No description provided for @consonantClassLow.
  ///
  /// In ja, this message translates to:
  /// **'低子音'**
  String get consonantClassLow;

  /// No description provided for @commonUnknownShort.
  ///
  /// In ja, this message translates to:
  /// **'不明'**
  String get commonUnknownShort;

  /// No description provided for @toneMarkNone.
  ///
  /// In ja, this message translates to:
  /// **'声調記号なし'**
  String get toneMarkNone;

  /// No description provided for @toneMarkMaiEk.
  ///
  /// In ja, this message translates to:
  /// **'マイエーク'**
  String get toneMarkMaiEk;

  /// No description provided for @toneMarkMaiTho.
  ///
  /// In ja, this message translates to:
  /// **'マイトー'**
  String get toneMarkMaiTho;

  /// No description provided for @toneMarkMaiTri.
  ///
  /// In ja, this message translates to:
  /// **'マイトリー'**
  String get toneMarkMaiTri;

  /// No description provided for @toneMarkMaiChattawa.
  ///
  /// In ja, this message translates to:
  /// **'マイチャッタワー'**
  String get toneMarkMaiChattawa;

  /// No description provided for @toneMarkSymbolNone.
  ///
  /// In ja, this message translates to:
  /// **'なし'**
  String get toneMarkSymbolNone;

  /// No description provided for @syllableLive.
  ///
  /// In ja, this message translates to:
  /// **'生音節'**
  String get syllableLive;

  /// No description provided for @syllableDead.
  ///
  /// In ja, this message translates to:
  /// **'死音節'**
  String get syllableDead;

  /// No description provided for @syllableDeadShort.
  ///
  /// In ja, this message translates to:
  /// **'死音節（短母音）'**
  String get syllableDeadShort;

  /// No description provided for @syllableDeadLong.
  ///
  /// In ja, this message translates to:
  /// **'死音節（長母音・複合母音）'**
  String get syllableDeadLong;

  /// No description provided for @syllableLiveDesc.
  ///
  /// In ja, this message translates to:
  /// **'長母音 または -m, -n, -ng, -y, -w で終わる'**
  String get syllableLiveDesc;

  /// No description provided for @syllableDeadDesc.
  ///
  /// In ja, this message translates to:
  /// **'短母音で末子音なし または -p, -t, -k で終わる'**
  String get syllableDeadDesc;

  /// No description provided for @toneMid.
  ///
  /// In ja, this message translates to:
  /// **'平声'**
  String get toneMid;

  /// No description provided for @toneLow.
  ///
  /// In ja, this message translates to:
  /// **'低声'**
  String get toneLow;

  /// No description provided for @toneFalling.
  ///
  /// In ja, this message translates to:
  /// **'下降声'**
  String get toneFalling;

  /// No description provided for @toneHigh.
  ///
  /// In ja, this message translates to:
  /// **'高声'**
  String get toneHigh;

  /// No description provided for @toneRising.
  ///
  /// In ja, this message translates to:
  /// **'上昇声'**
  String get toneRising;

  /// No description provided for @toneAnalyzerEmptyWord.
  ///
  /// In ja, this message translates to:
  /// **'単語が空です'**
  String get toneAnalyzerEmptyWord;

  /// No description provided for @toneDialogTitle.
  ///
  /// In ja, this message translates to:
  /// **'声調の解説'**
  String get toneDialogTitle;

  /// No description provided for @toneSyllableBreakdown.
  ///
  /// In ja, this message translates to:
  /// **'音節分解'**
  String get toneSyllableBreakdown;

  /// No description provided for @toneSyllableNumber.
  ///
  /// In ja, this message translates to:
  /// **'音節 {number}'**
  String toneSyllableNumber(int number);

  /// No description provided for @toneMainConsonant.
  ///
  /// In ja, this message translates to:
  /// **'主子音'**
  String get toneMainConsonant;

  /// No description provided for @toneSyllableType.
  ///
  /// In ja, this message translates to:
  /// **'音節タイプ'**
  String get toneSyllableType;

  /// No description provided for @toneResultPrefix.
  ///
  /// In ja, this message translates to:
  /// **'結果: '**
  String get toneResultPrefix;

  /// No description provided for @toneMarkLabel.
  ///
  /// In ja, this message translates to:
  /// **'声調記号'**
  String get toneMarkLabel;

  /// No description provided for @toneMarkPrefix.
  ///
  /// In ja, this message translates to:
  /// **'声調記号: '**
  String get toneMarkPrefix;

  /// No description provided for @toneResultTone.
  ///
  /// In ja, this message translates to:
  /// **'結果の声調'**
  String get toneResultTone;

  /// No description provided for @toneShiftFor.
  ///
  /// In ja, this message translates to:
  /// **'{consonantClass}の声調変化'**
  String toneShiftFor(String consonantClass);

  /// No description provided for @toneShiftTableFor.
  ///
  /// In ja, this message translates to:
  /// **'{consonantClass}の声調変化表'**
  String toneShiftTableFor(String consonantClass);

  /// No description provided for @toneRareUsage.
  ///
  /// In ja, this message translates to:
  /// **'例外的な使用（現代では稀）'**
  String get toneRareUsage;

  /// No description provided for @toneAppliedRule.
  ///
  /// In ja, this message translates to:
  /// **'= この単語に適用されている規則'**
  String get toneAppliedRule;

  /// No description provided for @toneLearnMore.
  ///
  /// In ja, this message translates to:
  /// **'声調について詳しく学ぶ'**
  String get toneLearnMore;

  /// No description provided for @toneExamplePrefix.
  ///
  /// In ja, this message translates to:
  /// **'例: {value}'**
  String toneExamplePrefix(String value);

  /// No description provided for @toneGuideTitle.
  ///
  /// In ja, this message translates to:
  /// **'タイ語の声調ガイド'**
  String get toneGuideTitle;

  /// No description provided for @toneGuideHeading.
  ///
  /// In ja, this message translates to:
  /// **'タイ語の声調について'**
  String get toneGuideHeading;

  /// No description provided for @toneGuideIntro.
  ///
  /// In ja, this message translates to:
  /// **'タイ語には5つの声調があり、同じ綴りでも声調によって意味が変わります。声調は、主子音（声調を決める子音）のクラス、声調記号、音節タイプによって決まります。'**
  String get toneGuideIntro;

  /// No description provided for @toneGuideFiveTones.
  ///
  /// In ja, this message translates to:
  /// **'5つの声調'**
  String get toneGuideFiveTones;

  /// No description provided for @toneGuideConsonantClasses.
  ///
  /// In ja, this message translates to:
  /// **'子音クラス'**
  String get toneGuideConsonantClasses;

  /// No description provided for @toneGuideToneMarks.
  ///
  /// In ja, this message translates to:
  /// **'声調記号'**
  String get toneGuideToneMarks;

  /// No description provided for @toneGuideSyllableTypes.
  ///
  /// In ja, this message translates to:
  /// **'音節タイプ'**
  String get toneGuideSyllableTypes;

  /// No description provided for @toneGuideShiftTable.
  ///
  /// In ja, this message translates to:
  /// **'声調変化表'**
  String get toneGuideShiftTable;

  /// No description provided for @toneGuideShiftTableIntro.
  ///
  /// In ja, this message translates to:
  /// **'子音クラスごとに、声調記号と音節タイプの組み合わせで決まる声調を示します。'**
  String get toneGuideShiftTableIntro;

  /// No description provided for @toneGuideLetterCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}文字'**
  String toneGuideLetterCount(int count);

  /// No description provided for @toneMidDesc.
  ///
  /// In ja, this message translates to:
  /// **'音の高さが平らで変化しない声調です。'**
  String get toneMidDesc;

  /// No description provided for @toneMidExample.
  ///
  /// In ja, this message translates to:
  /// **'กา (gaa) カラス'**
  String get toneMidExample;

  /// No description provided for @toneLowDesc.
  ///
  /// In ja, this message translates to:
  /// **'低い音から始まり、少し下がる声調です。'**
  String get toneLowDesc;

  /// No description provided for @toneLowExample.
  ///
  /// In ja, this message translates to:
  /// **'ก่า (gàa) ガランガル'**
  String get toneLowExample;

  /// No description provided for @toneFallingDesc.
  ///
  /// In ja, this message translates to:
  /// **'高い音から低く落ちる声調です。'**
  String get toneFallingDesc;

  /// No description provided for @toneFallingExample.
  ///
  /// In ja, this message translates to:
  /// **'ก้า (gâa) 歩み'**
  String get toneFallingExample;

  /// No description provided for @toneHighDesc.
  ///
  /// In ja, this message translates to:
  /// **'高い音で始まり、さらに上がる声調です。'**
  String get toneHighDesc;

  /// No description provided for @toneHighExample.
  ///
  /// In ja, this message translates to:
  /// **'ก๊า (gáa) 〜だよ（語尾）'**
  String get toneHighExample;

  /// No description provided for @toneRisingDesc.
  ///
  /// In ja, this message translates to:
  /// **'低い音から高く上がる声調です。'**
  String get toneRisingDesc;

  /// No description provided for @toneRisingExample.
  ///
  /// In ja, this message translates to:
  /// **'ก๋า (gǎa) 〜だね（語尾）'**
  String get toneRisingExample;

  /// No description provided for @toneMarkMaiEkDesc.
  ///
  /// In ja, this message translates to:
  /// **'第1声調記号。子音クラスによって異なる声調になります。'**
  String get toneMarkMaiEkDesc;

  /// No description provided for @toneMarkMaiThoDesc.
  ///
  /// In ja, this message translates to:
  /// **'第2声調記号。子音クラスによって異なる声調になります。'**
  String get toneMarkMaiThoDesc;

  /// No description provided for @toneMarkMaiTriDesc.
  ///
  /// In ja, this message translates to:
  /// **'第3声調記号。中子音で使用。低子音・高子音では例外的です。'**
  String get toneMarkMaiTriDesc;

  /// No description provided for @toneMarkMaiChattawaDesc.
  ///
  /// In ja, this message translates to:
  /// **'第4声調記号。中子音で使用。低子音・高子音では例外的です。'**
  String get toneMarkMaiChattawaDesc;

  /// No description provided for @tipCatVowel.
  ///
  /// In ja, this message translates to:
  /// **'母音'**
  String get tipCatVowel;

  /// No description provided for @tipCatCulture.
  ///
  /// In ja, this message translates to:
  /// **'文化'**
  String get tipCatCulture;

  /// No description provided for @tipCatTone.
  ///
  /// In ja, this message translates to:
  /// **'声調'**
  String get tipCatTone;

  /// No description provided for @tipCatConsonant.
  ///
  /// In ja, this message translates to:
  /// **'子音'**
  String get tipCatConsonant;

  /// No description provided for @tipCatNumber.
  ///
  /// In ja, this message translates to:
  /// **'数字'**
  String get tipCatNumber;

  /// No description provided for @tipCatDaily.
  ///
  /// In ja, this message translates to:
  /// **'日常表現'**
  String get tipCatDaily;

  /// No description provided for @tipCatStudy.
  ///
  /// In ja, this message translates to:
  /// **'学習のコツ'**
  String get tipCatStudy;

  /// No description provided for @tip_vowelA_title.
  ///
  /// In ja, this message translates to:
  /// **'อะ / อา （a / aa）'**
  String get tip_vowelA_title;

  /// No description provided for @tip_vowelA_content.
  ///
  /// In ja, this message translates to:
  /// **'短母音 อะ は「a」、長母音 อา は「aa」。長さで意味が変わります。'**
  String get tip_vowelA_content;

  /// No description provided for @tip_vowelA_example.
  ///
  /// In ja, this message translates to:
  /// **'จะ（jà＝〜する） / จา（jaa＝皿）'**
  String get tip_vowelA_example;

  /// No description provided for @tip_vowelI_title.
  ///
  /// In ja, this message translates to:
  /// **'อิ / อี （i / ii）'**
  String get tip_vowelI_title;

  /// No description provided for @tip_vowelI_content.
  ///
  /// In ja, this message translates to:
  /// **'短母音 อิ は短い「i」、長母音 อี は長い「ii」。'**
  String get tip_vowelI_content;

  /// No description provided for @tip_vowelI_example.
  ///
  /// In ja, this message translates to:
  /// **'นิด（nít＝少し） / นี่（nîi＝これ）'**
  String get tip_vowelI_example;

  /// No description provided for @tip_vowelU_title.
  ///
  /// In ja, this message translates to:
  /// **'อุ / อู （u / uu）'**
  String get tip_vowelU_title;

  /// No description provided for @tip_vowelU_content.
  ///
  /// In ja, this message translates to:
  /// **'短母音 อุ は短い「u」、長母音 อู は長い「uu」。'**
  String get tip_vowelU_content;

  /// No description provided for @tip_vowelU_example.
  ///
  /// In ja, this message translates to:
  /// **'รุ่น（rûn＝世代） / รู้（rúu＝知る）'**
  String get tip_vowelU_example;

  /// No description provided for @tip_vowelE_title.
  ///
  /// In ja, this message translates to:
  /// **'เอ / แอ （ee / ɛɛ）'**
  String get tip_vowelE_title;

  /// No description provided for @tip_vowelE_content.
  ///
  /// In ja, this message translates to:
  /// **'เอ は「ee」、แอ は口を大きく開けた「ɛɛ」。'**
  String get tip_vowelE_content;

  /// No description provided for @tip_vowelE_example.
  ///
  /// In ja, this message translates to:
  /// **'เก่ง（kèeng＝上手） / แก่（kɛ̀ɛ＝老いた）'**
  String get tip_vowelE_example;

  /// No description provided for @tip_vowelO_title.
  ///
  /// In ja, this message translates to:
  /// **'โอ / ออ （oo / ɔɔ）'**
  String get tip_vowelO_title;

  /// No description provided for @tip_vowelO_content.
  ///
  /// In ja, this message translates to:
  /// **'โอ は口をすぼめた「oo」、ออ は口を開けた「ɔɔ」。'**
  String get tip_vowelO_content;

  /// No description provided for @tip_vowelO_example.
  ///
  /// In ja, this message translates to:
  /// **'โต（too＝大きい） / ต่อ（tɔ̀ɔ＝続ける）'**
  String get tip_vowelO_example;

  /// No description provided for @tip_vowelUea_title.
  ///
  /// In ja, this message translates to:
  /// **'เอือ （ʉa）'**
  String get tip_vowelUea_title;

  /// No description provided for @tip_vowelUea_content.
  ///
  /// In ja, this message translates to:
  /// **'เอือ は日本語にない母音。「ʉa」と表記されます。'**
  String get tip_vowelUea_content;

  /// No description provided for @tip_vowelUea_example.
  ///
  /// In ja, this message translates to:
  /// **'เมือง（mʉʉang＝街・国）'**
  String get tip_vowelUea_example;

  /// No description provided for @tip_vowelUu_title.
  ///
  /// In ja, this message translates to:
  /// **'อือ / อื （ʉ / ʉʉ）'**
  String get tip_vowelUu_title;

  /// No description provided for @tip_vowelUu_content.
  ///
  /// In ja, this message translates to:
  /// **'日本語にない音。「i」の口で「u」と発音するイメージ。'**
  String get tip_vowelUu_content;

  /// No description provided for @tip_vowelUu_example.
  ///
  /// In ja, this message translates to:
  /// **'คือ（khʉʉ＝〜である） / ฝืน（fʉ̌ʉn＝無理する）'**
  String get tip_vowelUu_example;

  /// No description provided for @tip_vowelIa_title.
  ///
  /// In ja, this message translates to:
  /// **'เอีย （ia）'**
  String get tip_vowelIa_title;

  /// No description provided for @tip_vowelIa_content.
  ///
  /// In ja, this message translates to:
  /// **'เอีย は「ia」。i から a へ滑らかにつなげます。'**
  String get tip_vowelIa_content;

  /// No description provided for @tip_vowelIa_example.
  ///
  /// In ja, this message translates to:
  /// **'เรียน（riian＝学ぶ）'**
  String get tip_vowelIa_example;

  /// No description provided for @tip_vowelUa_title.
  ///
  /// In ja, this message translates to:
  /// **'อัว （ua）'**
  String get tip_vowelUa_title;

  /// No description provided for @tip_vowelUa_content.
  ///
  /// In ja, this message translates to:
  /// **'อัว は「ua」。u から a へ滑らかにつなげます。'**
  String get tip_vowelUa_content;

  /// No description provided for @tip_vowelUa_example.
  ///
  /// In ja, this message translates to:
  /// **'ตัว（tuua＝体・匹）'**
  String get tip_vowelUa_example;

  /// No description provided for @tip_vowelAw_title.
  ///
  /// In ja, this message translates to:
  /// **'เอา （aw）'**
  String get tip_vowelAw_title;

  /// No description provided for @tip_vowelAw_content.
  ///
  /// In ja, this message translates to:
  /// **'เอา は「aw」。口を開けてからすぼめます。'**
  String get tip_vowelAw_content;

  /// No description provided for @tip_vowelAw_example.
  ///
  /// In ja, this message translates to:
  /// **'เอา（aw＝要る・取る）'**
  String get tip_vowelAw_example;

  /// No description provided for @tip_vowelAi_title.
  ///
  /// In ja, this message translates to:
  /// **'ไอ / ใอ （ai）'**
  String get tip_vowelAi_title;

  /// No description provided for @tip_vowelAi_content.
  ///
  /// In ja, this message translates to:
  /// **'ไอ と ใอ は同じ「ai」の発音。ใ を使う語は20語だけ。'**
  String get tip_vowelAi_content;

  /// No description provided for @tip_vowelAi_example.
  ///
  /// In ja, this message translates to:
  /// **'ไป（pai＝行く） / ใจ（jai＝心）'**
  String get tip_vowelAi_example;

  /// No description provided for @tip_vowelShortE_title.
  ///
  /// In ja, this message translates to:
  /// **'เอ็（短母音 e）'**
  String get tip_vowelShortE_title;

  /// No description provided for @tip_vowelShortE_content.
  ///
  /// In ja, this message translates to:
  /// **'短い「e」。เ〜็ の形で表記されます。'**
  String get tip_vowelShortE_content;

  /// No description provided for @tip_vowelShortE_example.
  ///
  /// In ja, this message translates to:
  /// **'เก็บ（kèp＝拾う・保管する）'**
  String get tip_vowelShortE_example;

  /// No description provided for @tip_vowelShortAe_title.
  ///
  /// In ja, this message translates to:
  /// **'แอ็（短母音 ɛ）'**
  String get tip_vowelShortAe_title;

  /// No description provided for @tip_vowelShortAe_content.
  ///
  /// In ja, this message translates to:
  /// **'短い「ɛ」（口を大きく開ける）。แ〜็ の形。'**
  String get tip_vowelShortAe_content;

  /// No description provided for @tip_vowelShortAe_example.
  ///
  /// In ja, this message translates to:
  /// **'แบ็ก（bɛ̀k＝バッグ）'**
  String get tip_vowelShortAe_example;

  /// No description provided for @tip_vowelOe_title.
  ///
  /// In ja, this message translates to:
  /// **'เออ （əə）'**
  String get tip_vowelOe_title;

  /// No description provided for @tip_vowelOe_content.
  ///
  /// In ja, this message translates to:
  /// **'เออ は曖昧な母音「əə」。口を半開きにして発音。'**
  String get tip_vowelOe_content;

  /// No description provided for @tip_vowelOe_example.
  ///
  /// In ja, this message translates to:
  /// **'เธอ（thəə＝あなた・彼女）'**
  String get tip_vowelOe_example;

  /// No description provided for @tip_vowelLength_title.
  ///
  /// In ja, this message translates to:
  /// **'母音の長短で意味が変わる'**
  String get tip_vowelLength_title;

  /// No description provided for @tip_vowelLength_content.
  ///
  /// In ja, this message translates to:
  /// **'タイ語は母音の長さが重要。短母音と長母音で別の単語になります。'**
  String get tip_vowelLength_content;

  /// No description provided for @tip_vowelLength_example.
  ///
  /// In ja, this message translates to:
  /// **'ปะ（pà＝出会う） / ป้า（pâa＝おばさん）'**
  String get tip_vowelLength_example;

  /// No description provided for @tip_cultureWai_title.
  ///
  /// In ja, this message translates to:
  /// **'wâi（合掌・ไหว้）'**
  String get tip_cultureWai_title;

  /// No description provided for @tip_cultureWai_content.
  ///
  /// In ja, this message translates to:
  /// **'両手を合わせるタイ式挨拶。目上の人には鼻の高さ、同年代は胸の高さで。'**
  String get tip_cultureWai_content;

  /// No description provided for @tip_cultureTemple_title.
  ///
  /// In ja, this message translates to:
  /// **'寺院参拝のマナー'**
  String get tip_cultureTemple_title;

  /// No description provided for @tip_cultureTemple_content.
  ///
  /// In ja, this message translates to:
  /// **'寺院では靴を脱ぎ、肩と膝を隠す服装で。仏像より高い位置に座らないこと。'**
  String get tip_cultureTemple_content;

  /// No description provided for @tip_cultureSongkran_title.
  ///
  /// In ja, this message translates to:
  /// **'sǒngkraan（水かけ祭り）'**
  String get tip_cultureSongkran_title;

  /// No description provided for @tip_cultureSongkran_content.
  ///
  /// In ja, this message translates to:
  /// **'毎年4月13〜15日のタイ正月。水をかけ合い新年を祝います。'**
  String get tip_cultureSongkran_content;

  /// No description provided for @tip_cultureLoyKrathong_title.
  ///
  /// In ja, this message translates to:
  /// **'lɔɔi krathong（灯篭流し）'**
  String get tip_cultureLoyKrathong_title;

  /// No description provided for @tip_cultureLoyKrathong_content.
  ///
  /// In ja, this message translates to:
  /// **'陰暦12月の満月に川へ灯篭を流す祭り。水の精霊に感謝を捧げます。'**
  String get tip_cultureLoyKrathong_content;

  /// No description provided for @tip_cultureEating_title.
  ///
  /// In ja, this message translates to:
  /// **'タイ料理の食べ方'**
  String get tip_cultureEating_title;

  /// No description provided for @tip_cultureEating_content.
  ///
  /// In ja, this message translates to:
  /// **'フォークとスプーンを使い、スプーンで口に運びます。箸は麺料理の時だけ。'**
  String get tip_cultureEating_content;

  /// No description provided for @tip_cultureMaiPenRai_title.
  ///
  /// In ja, this message translates to:
  /// **'ไม่เป็นไร（mâi pen rai）'**
  String get tip_cultureMaiPenRai_title;

  /// No description provided for @tip_cultureMaiPenRai_content.
  ///
  /// In ja, this message translates to:
  /// **'「気にしないで・大丈夫」。タイ人の寛容さを表す代表的フレーズです。'**
  String get tip_cultureMaiPenRai_content;

  /// No description provided for @tip_toneFive_title.
  ///
  /// In ja, this message translates to:
  /// **'タイ語は5つの声調'**
  String get tip_toneFive_title;

  /// No description provided for @tip_toneFive_content.
  ///
  /// In ja, this message translates to:
  /// **'平声・低声・下声・高声・上声の5つ。声調が違うと全く別の単語になります。'**
  String get tip_toneFive_content;

  /// No description provided for @tip_toneFive_example.
  ///
  /// In ja, this message translates to:
  /// **'ไหม（mǎi＝絹） / ใหม่（mài＝新しい） / ไม่（mâi＝〜ない）'**
  String get tip_toneFive_example;

  /// No description provided for @tip_toneMaiEk_title.
  ///
  /// In ja, this message translates to:
  /// **'声調記号 ่ （mái èek）'**
  String get tip_toneMaiEk_title;

  /// No description provided for @tip_toneMaiEk_content.
  ///
  /// In ja, this message translates to:
  /// **'文字の上に付く第1声調記号。中子音・高子音に付くと低声になります。'**
  String get tip_toneMaiEk_content;

  /// No description provided for @tip_toneMaiEk_example.
  ///
  /// In ja, this message translates to:
  /// **'เก่า（kàw＝古い）、ข่าว（khàaw＝ニュース）'**
  String get tip_toneMaiEk_example;

  /// No description provided for @tip_toneMaiTho_title.
  ///
  /// In ja, this message translates to:
  /// **'声調記号 ้ （mái thoo）'**
  String get tip_toneMaiTho_title;

  /// No description provided for @tip_toneMaiTho_content.
  ///
  /// In ja, this message translates to:
  /// **'文字の上に付く第2声調記号。中子音に付くと下声になります。'**
  String get tip_toneMaiTho_content;

  /// No description provided for @tip_toneMaiTho_example.
  ///
  /// In ja, this message translates to:
  /// **'น้ำ（náam＝水）、บ้าน（bâan＝家）'**
  String get tip_toneMaiTho_example;

  /// No description provided for @tip_toneMaiTriChat_title.
  ///
  /// In ja, this message translates to:
  /// **'声調記号 ๊ と ๋'**
  String get tip_toneMaiTriChat_title;

  /// No description provided for @tip_toneMaiTriChat_content.
  ///
  /// In ja, this message translates to:
  /// **'๊（mái trii）は高声、๋（mái jàttawaa）は上声を示します。使用頻度は低め。'**
  String get tip_toneMaiTriChat_content;

  /// No description provided for @tip_toneMaiTriChat_example.
  ///
  /// In ja, this message translates to:
  /// **'โน๊ต（nóot＝ノート）、จ๋า（jǎa＝はいよ）'**
  String get tip_toneMaiTriChat_example;

  /// No description provided for @tip_toneClassRelation_title.
  ///
  /// In ja, this message translates to:
  /// **'子音クラスと声調の関係'**
  String get tip_toneClassRelation_title;

  /// No description provided for @tip_toneClassRelation_content.
  ///
  /// In ja, this message translates to:
  /// **'声調は子音クラス（高・中・低）×母音の長短×末子音×声調記号で決まります。'**
  String get tip_toneClassRelation_content;

  /// No description provided for @tip_toneMistake_title.
  ///
  /// In ja, this message translates to:
  /// **'声調を間違えると…'**
  String get tip_toneMistake_title;

  /// No description provided for @tip_toneMistake_content.
  ///
  /// In ja, this message translates to:
  /// **'สวย（sǔuai＝美しい）と ซวย（suuai＝ついてない）のように声調で意味が激変。'**
  String get tip_toneMistake_content;

  /// No description provided for @tip_toneMidExplain_title.
  ///
  /// In ja, this message translates to:
  /// **'平声（sǎa-man）'**
  String get tip_toneMidExplain_title;

  /// No description provided for @tip_toneMidExplain_content.
  ///
  /// In ja, this message translates to:
  /// **'中くらいの高さで平らに発音。中子音＋長母音（声調記号なし）が基本パターン。'**
  String get tip_toneMidExplain_content;

  /// No description provided for @tip_toneMidExplain_example.
  ///
  /// In ja, this message translates to:
  /// **'กา（kaa＝カラス）、ดี（dii＝良い）'**
  String get tip_toneMidExplain_example;

  /// No description provided for @tip_toneRisingExplain_title.
  ///
  /// In ja, this message translates to:
  /// **'上声（jàttawaa）'**
  String get tip_toneRisingExplain_title;

  /// No description provided for @tip_toneRisingExplain_content.
  ///
  /// In ja, this message translates to:
  /// **'低い音から高い音へ上がる声調。日本語の疑問文の語尾上げに少し似ています。'**
  String get tip_toneRisingExplain_content;

  /// No description provided for @tip_toneRisingExplain_example.
  ///
  /// In ja, this message translates to:
  /// **'สวย（sǔuai＝美しい）、หนาว（nǎaw＝寒い）'**
  String get tip_toneRisingExplain_example;

  /// No description provided for @tip_toneRelative_title.
  ///
  /// In ja, this message translates to:
  /// **'声調は相対的な高さ'**
  String get tip_toneRelative_title;

  /// No description provided for @tip_toneRelative_content.
  ///
  /// In ja, this message translates to:
  /// **'声調の高さは前の音節で変わります。フレーズごと覚えるのが効果的。'**
  String get tip_toneRelative_content;

  /// No description provided for @tip_consonant44_title.
  ///
  /// In ja, this message translates to:
  /// **'タイ語は44の子音字'**
  String get tip_consonant44_title;

  /// No description provided for @tip_consonant44_content.
  ///
  /// In ja, this message translates to:
  /// **'44文字ありますが、現在使われるのは42文字。発音は21種類に集約されます。'**
  String get tip_consonant44_content;

  /// No description provided for @tip_consonantHigh_title.
  ///
  /// In ja, this message translates to:
  /// **'高子音（àksɔ̌ɔn sǔung）'**
  String get tip_consonantHigh_title;

  /// No description provided for @tip_consonantHigh_content.
  ///
  /// In ja, this message translates to:
  /// **'ข ฃ ข ฉ ฐ ถ ผ ฝ ศ ษ ส ห の11文字。声調ルールが中・低子音と異なります。'**
  String get tip_consonantHigh_content;

  /// No description provided for @tip_consonantMid_title.
  ///
  /// In ja, this message translates to:
  /// **'中子音（àksɔ̌ɔn klaang）'**
  String get tip_consonantMid_title;

  /// No description provided for @tip_consonantMid_content.
  ///
  /// In ja, this message translates to:
  /// **'ก จ ฎ ฏ ด ต บ ป อ の9文字。声調記号がそのまま反映される基本グループ。'**
  String get tip_consonantMid_content;

  /// No description provided for @tip_consonantLow_title.
  ///
  /// In ja, this message translates to:
  /// **'低子音（àksɔ̌ɔn tàm）'**
  String get tip_consonantLow_title;

  /// No description provided for @tip_consonantLow_content.
  ///
  /// In ja, this message translates to:
  /// **'残り24文字が低子音。対応する高子音がある「対応字」と「単独字」に分かれます。'**
  String get tip_consonantLow_content;

  /// No description provided for @tip_consonantFinal_title.
  ///
  /// In ja, this message translates to:
  /// **'末子音の発音ルール'**
  String get tip_consonantFinal_title;

  /// No description provided for @tip_consonantFinal_content.
  ///
  /// In ja, this message translates to:
  /// **'末子音は k, t, p, n, m, ng, i, o の8音のみ。元の子音と違う音になることも。'**
  String get tip_consonantFinal_content;

  /// No description provided for @tip_consonantFinal_example.
  ///
  /// In ja, this message translates to:
  /// **'บ,ป,พ,ภ,ฟ → 末子音ではすべて -p'**
  String get tip_consonantFinal_example;

  /// No description provided for @tip_consonantAspiration_title.
  ///
  /// In ja, this message translates to:
  /// **'有気音と無気音'**
  String get tip_consonantAspiration_title;

  /// No description provided for @tip_consonantAspiration_content.
  ///
  /// In ja, this message translates to:
  /// **'タイ語は息の有無で子音を区別。ป（無気音 p）と พ（有気音 ph）は別の音。'**
  String get tip_consonantAspiration_content;

  /// No description provided for @tip_consonantAspiration_example.
  ///
  /// In ja, this message translates to:
  /// **'ปลา（plaa＝魚） / พลา（phlaa＝失敗する）'**
  String get tip_consonantAspiration_example;

  /// No description provided for @tip_consonantSilent_title.
  ///
  /// In ja, this message translates to:
  /// **'黙字記号 ์（kaa-ran）'**
  String get tip_consonantSilent_title;

  /// No description provided for @tip_consonantSilent_content.
  ///
  /// In ja, this message translates to:
  /// **'文字の上に付く ์ は「この子音は読まない」という記号。外来語に多いです。'**
  String get tip_consonantSilent_content;

  /// No description provided for @tip_consonantSilent_example.
  ///
  /// In ja, this message translates to:
  /// **'จันทร์（jan＝月） ← ร์ は読まない'**
  String get tip_consonantSilent_example;

  /// No description provided for @tip_consonantCluster_title.
  ///
  /// In ja, this message translates to:
  /// **'二重子音（àksɔ̌ɔn khûap）'**
  String get tip_consonantCluster_title;

  /// No description provided for @tip_consonantCluster_content.
  ///
  /// In ja, this message translates to:
  /// **'子音が2つ連続する場合、一緒に発音します。kr, kl, pr, pl などのパターン。'**
  String get tip_consonantCluster_content;

  /// No description provided for @tip_consonantCluster_example.
  ///
  /// In ja, this message translates to:
  /// **'กรุง（krung＝都） / ปลา（plaa＝魚）'**
  String get tip_consonantCluster_example;

  /// No description provided for @tip_numberThai_title.
  ///
  /// In ja, this message translates to:
  /// **'タイ数字'**
  String get tip_numberThai_title;

  /// No description provided for @tip_numberThai_content.
  ///
  /// In ja, this message translates to:
  /// **'タイには独自の数字があります。๐๑๒๓๔๕๖๗๘๙（0〜9）。看板や公文書で使われます。'**
  String get tip_numberThai_content;

  /// No description provided for @tip_number1to5_title.
  ///
  /// In ja, this message translates to:
  /// **'1〜5の読み方'**
  String get tip_number1to5_title;

  /// No description provided for @tip_number1to5_content.
  ///
  /// In ja, this message translates to:
  /// **'๑ nʉ̀ng、๒ sɔ̌ɔng、๓ sǎam、๔ sìi、๕ hâa'**
  String get tip_number1to5_content;

  /// No description provided for @tip_number6to10_title.
  ///
  /// In ja, this message translates to:
  /// **'6〜10の読み方'**
  String get tip_number6to10_title;

  /// No description provided for @tip_number6to10_content.
  ///
  /// In ja, this message translates to:
  /// **'๖ hòk、๗ jèt、๘ pɛ̀ɛt、๙ kâw、๑๐ sìp'**
  String get tip_number6to10_content;

  /// No description provided for @tip_number11and21_title.
  ///
  /// In ja, this message translates to:
  /// **'11と21の特殊な読み方'**
  String get tip_number11and21_title;

  /// No description provided for @tip_number11and21_content.
  ///
  /// In ja, this message translates to:
  /// **'11は sìp èt、21は yîi sìp èt。1の位と2の十の位が特殊。'**
  String get tip_number11and21_content;

  /// No description provided for @tip_numberClassifier_title.
  ///
  /// In ja, this message translates to:
  /// **'類別詞（láksanànaam）'**
  String get tip_numberClassifier_title;

  /// No description provided for @tip_numberClassifier_content.
  ///
  /// In ja, this message translates to:
  /// **'数を数えるとき「数詞＋類別詞」が必要。日本語の「〜本」「〜枚」と同じ仕組み。'**
  String get tip_numberClassifier_content;

  /// No description provided for @tip_numberClassifier_example.
  ///
  /// In ja, this message translates to:
  /// **'khon（人）、tua（動物）、an（小物）'**
  String get tip_numberClassifier_example;

  /// No description provided for @tip_numberBig_title.
  ///
  /// In ja, this message translates to:
  /// **'百・千・万の位'**
  String get tip_numberBig_title;

  /// No description provided for @tip_numberBig_content.
  ///
  /// In ja, this message translates to:
  /// **'rɔ́ɔi（百）、phan（千）、mʉ̀ʉn（万）、sǎen（十万）、láan（百万）'**
  String get tip_numberBig_content;

  /// No description provided for @tip_numberPrice_title.
  ///
  /// In ja, this message translates to:
  /// **'値段の聞き方'**
  String get tip_numberPrice_title;

  /// No description provided for @tip_numberPrice_content.
  ///
  /// In ja, this message translates to:
  /// **'「いくらですか？」は thâo rài。raakhaa（価格）と合わせて覚えましょう。'**
  String get tip_numberPrice_content;

  /// No description provided for @tip_numberPrice_example.
  ///
  /// In ja, this message translates to:
  /// **'an-níi thâo rài（これいくら？）'**
  String get tip_numberPrice_example;

  /// No description provided for @tip_dailyPolite_title.
  ///
  /// In ja, this message translates to:
  /// **'ครับ / ค่ะ（khráp / khâ）'**
  String get tip_dailyPolite_title;

  /// No description provided for @tip_dailyPolite_content.
  ///
  /// In ja, this message translates to:
  /// **'男性は khráp（ครับ）、女性は khâ（ค่ะ）を文末に付けて丁寧にします。タイ語の基本マナー。'**
  String get tip_dailyPolite_content;

  /// No description provided for @tip_dailyPolite_example.
  ///
  /// In ja, this message translates to:
  /// **'khɔ̀ɔp khun khráp / khɔ̀ɔp khun khâ'**
  String get tip_dailyPolite_example;

  /// No description provided for @tip_dailyHello_title.
  ///
  /// In ja, this message translates to:
  /// **'สวัสดี（sà-wàt-dii）'**
  String get tip_dailyHello_title;

  /// No description provided for @tip_dailyHello_content.
  ///
  /// In ja, this message translates to:
  /// **'「こんにちは」朝昼夜いつでも使える万能挨拶。別れ際にも使います。'**
  String get tip_dailyHello_content;

  /// No description provided for @tip_dailyThanks_title.
  ///
  /// In ja, this message translates to:
  /// **'ขอบคุณ（khɔ̀ɔp khun）'**
  String get tip_dailyThanks_title;

  /// No description provided for @tip_dailyThanks_content.
  ///
  /// In ja, this message translates to:
  /// **'「ありがとう」。khɔ̀ɔp khun mâak で「大変ありがとう」。'**
  String get tip_dailyThanks_content;

  /// No description provided for @tip_dailySorry_title.
  ///
  /// In ja, this message translates to:
  /// **'ขอโทษ（khɔ̌ɔ thôot）'**
  String get tip_dailySorry_title;

  /// No description provided for @tip_dailySorry_content.
  ///
  /// In ja, this message translates to:
  /// **'「すみません・ごめんなさい」。謝罪にも呼びかけにも使えます。'**
  String get tip_dailySorry_content;

  /// No description provided for @tip_dailyYesNo_title.
  ///
  /// In ja, this message translates to:
  /// **'ใช่ / ไม่ใช่（châi / mâi châi）'**
  String get tip_dailyYesNo_title;

  /// No description provided for @tip_dailyYesNo_content.
  ///
  /// In ja, this message translates to:
  /// **'「はい / いいえ」。確認に対する返答に使います。'**
  String get tip_dailyYesNo_content;

  /// No description provided for @tip_dailyYesNo_example.
  ///
  /// In ja, this message translates to:
  /// **'châi mǎi（そうですか？）→ châi khráp（はい）'**
  String get tip_dailyYesNo_example;

  /// No description provided for @tip_dailyEat_title.
  ///
  /// In ja, this message translates to:
  /// **'กิน（kin）＝食べる'**
  String get tip_dailyEat_title;

  /// No description provided for @tip_dailyEat_content.
  ///
  /// In ja, this message translates to:
  /// **'「ご飯食べた？」kin khâao rʉ̌ʉ yang はタイの定番挨拶です。'**
  String get tip_dailyEat_content;

  /// No description provided for @tip_dailyDelicious_title.
  ///
  /// In ja, this message translates to:
  /// **'อร่อย（à-ròi）＝おいしい'**
  String get tip_dailyDelicious_title;

  /// No description provided for @tip_dailyDelicious_content.
  ///
  /// In ja, this message translates to:
  /// **'タイ料理を食べたら à-ròi！mâak を付けると「とてもおいしい」。'**
  String get tip_dailyDelicious_content;

  /// No description provided for @tip_dailyPronouns_title.
  ///
  /// In ja, this message translates to:
  /// **'人称代名詞の使い分け'**
  String get tip_dailyPronouns_title;

  /// No description provided for @tip_dailyPronouns_content.
  ///
  /// In ja, this message translates to:
  /// **'phǒm（僕）は男性、dì-chǎn（私）は女性のフォーマルな一人称。'**
  String get tip_dailyPronouns_content;

  /// No description provided for @tip_dailyPronouns_example.
  ///
  /// In ja, this message translates to:
  /// **'カジュアルでは rao や chǎn も使います'**
  String get tip_dailyPronouns_example;

  /// No description provided for @tip_studyThaiOnly_title.
  ///
  /// In ja, this message translates to:
  /// **'タイ語だけでクイズに挑戦'**
  String get tip_studyThaiOnly_title;

  /// No description provided for @tip_studyThaiOnly_content.
  ///
  /// In ja, this message translates to:
  /// **'例文や解説を見ずにタイ語だけで意味が分かるか、クイズで挑戦してみよう！'**
  String get tip_studyThaiOnly_content;

  /// No description provided for @errPurchaseStatusFailed.
  ///
  /// In ja, this message translates to:
  /// **'購入状態の取得に失敗しました'**
  String get errPurchaseStatusFailed;

  /// No description provided for @errPurchaseGeneric.
  ///
  /// In ja, this message translates to:
  /// **'購入エラーが発生しました'**
  String get errPurchaseGeneric;

  /// No description provided for @purchasePending.
  ///
  /// In ja, this message translates to:
  /// **'購入の承認待ちです。承認後に反映されます'**
  String get purchasePending;

  /// No description provided for @errSignInBeforePurchase.
  ///
  /// In ja, this message translates to:
  /// **'ログインしてから購入してください'**
  String get errSignInBeforePurchase;

  /// No description provided for @errPurchaseVerificationFailed.
  ///
  /// In ja, this message translates to:
  /// **'購入の検証に失敗しました'**
  String get errPurchaseVerificationFailed;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'ja':
      return L10nJa();
  }

  throw FlutterError(
      'L10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
