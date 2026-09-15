// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Daily Thai';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsFont => 'Font';

  @override
  String get settingsFontPickerTitle => 'Choose a font';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguagePickerTitle => 'Choose a language';

  @override
  String get settingsLanguageSubtitle =>
      'Changes the language of translations and explanations';

  @override
  String get settingsLanguageNote =>
      'Changes the language of translations and explanations. Translations of sentences you already created stay in the language they were created in.';

  @override
  String get navLearn => 'Learn';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get learnOpenDetail => 'Details';

  @override
  String get learnQuizTitle => 'Check quiz';

  @override
  String get learnSummaryQuizTitle => 'Summary quiz';

  @override
  String get learnNextSentence => 'Next sentence';

  @override
  String get learnNextSet => 'Next set';

  @override
  String get learnGoToSummaryQuiz => 'To the summary quiz';

  @override
  String learnDailySetRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more to the summary quiz',
      one: '1 more to the summary quiz',
    );
    return '$_temp0';
  }

  @override
  String get learnDailySetLast => 'Next is the summary quiz';

  @override
  String learnDailySetProgress(int position, int total) {
    return '$position / $total';
  }

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Retry';

  @override
  String get sentencePreparing => 'Preparing sentences...';

  @override
  String todaysWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Target words',
      one: 'Target word',
    );
    return '$_temp0';
  }

  @override
  String get playPronunciation => 'Play pronunciation';

  @override
  String get sentenceListenModel => 'Listen to the model';

  @override
  String get sentencePractice => 'Pronunciation practice';

  @override
  String get sentenceUsingWord => 'A sentence using this word';

  @override
  String get badgePremiumSentence => 'Premium sentence';

  @override
  String get badgeFreeSentence => 'Free sentence';

  @override
  String get sampleSentenceNotice =>
      'Sample sentence (not saved to your history)';

  @override
  String get sampleReload => 'Load today\'s sentence';

  @override
  String get sampleGreetingTranslation => 'Hello (said by a man)';

  @override
  String get sampleGreetingWord1Meaning => 'hello, goodbye';

  @override
  String get sampleGreetingWord1Role => 'greeting';

  @override
  String get sampleGreetingWord2Meaning => 'polite ending used by men';

  @override
  String get sampleGreetingWord2Role => 'sentence ending';

  @override
  String get sampleGreetingTopic => 'everyday greetings';

  @override
  String get sampleGreetingStyle => 'colloquial';

  @override
  String get sampleGreetingEmotion => 'polite, formal';

  @override
  String get sampleGreetingUsage =>
      'A basic greeting you can use morning, noon, or night. Women use ค่ะ instead.';

  @override
  String get quizTodayTitle => 'Quiz';

  @override
  String get quizGenerating => 'Generating the quiz...';

  @override
  String get quizOpenSentenceFirst => 'Open a sentence first';

  @override
  String get quizFromLearningSentence =>
      'Questions come from the sentence you\'re studying';

  @override
  String get quizBackToSentence => 'Back to the sentence';

  @override
  String get quizCorrect => 'Correct!';

  @override
  String get quizIncorrect => 'Incorrect';

  @override
  String quizCorrectAnswer(String answer) {
    return 'Correct answer: $answer';
  }

  @override
  String get quizPrompt => 'Choose the word that goes in the blank';

  @override
  String get quizMeaningPrompt => 'Choose the meaning of this word';

  @override
  String get quizWordExplanation => 'Word explanation';

  @override
  String quizProgress(int index, int total) {
    return 'Question $index of $total';
  }

  @override
  String get quizSentenceReviewed => 'Sentence reviewed';

  @override
  String get quizReviewSentence => 'Review the sentence';

  @override
  String get quizHint => 'Hint';

  @override
  String get quizHintPronunciation => 'Hint 1: show pronunciation';

  @override
  String get quizHintTranslation => 'Hint 2: show translation';

  @override
  String get quizHintShown => 'Hints already shown';

  @override
  String get quizCheckSentence => 'Check the sentence';

  @override
  String get quizPlaySentence => 'Play the sentence';

  @override
  String get quizPlayWord => 'Play the word';

  @override
  String get quizWhyCorrect => 'Why it\'s correct';

  @override
  String get quizWhyIncorrect => 'Why it\'s incorrect';

  @override
  String get quizSeeResults => 'See results';

  @override
  String get quizNextQuestion => 'Next question';

  @override
  String get commonTryAgain => 'Try again once more';

  @override
  String get vocabScore => 'Vocabulary score';

  @override
  String get vocabScoreCalculating => 'Calculating your vocabulary score...';

  @override
  String get vocabScoreUp => 'Vocabulary score up!';

  @override
  String get vocabScoreCapped => 'Your vocabulary score has reached its cap';

  @override
  String get vocabScorePremiumPitch =>
      'Go Premium to keep tracking your growth';

  @override
  String vocabWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String vocabWordsDelta(String delta) {
    return '$delta words';
  }

  @override
  String get historyTitle => 'History';

  @override
  String get historyFavoritesOnly => 'Show favorites only';

  @override
  String get historyDeleteAll => 'Delete all';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterFavorites => 'Favorites';

  @override
  String historyDateWithYear(int year, int month, int day) {
    return '$year/$month/$day';
  }

  @override
  String historyDate(int month, int day) {
    return '$month/$day';
  }

  @override
  String get historySearchHint => 'Search Thai or English';

  @override
  String get historyEmptyFavorites => 'No favorite sentences yet';

  @override
  String get historyEmptySearch => 'No search results found';

  @override
  String get historyEmpty => 'No sentences yet';

  @override
  String get historyEmptyFavoritesHint =>
      'Tap the heart icon on a sentence to add it to your favorites';

  @override
  String get historyEmptySearchHint => 'Try a different keyword';

  @override
  String get historyEmptyHint => 'Try generating a new sentence';

  @override
  String get historyDeleteAllConfirm =>
      'Delete your entire sentence history? This can\'t be undone.';

  @override
  String get historyDeletedAll => 'Deleted all sentences';

  @override
  String historyDeleteFailed(String error) {
    return 'Couldn\'t delete: $error';
  }

  @override
  String get historyDeleteConfirmTitle => 'Confirm deletion';

  @override
  String get historyDeleteConfirm => 'Delete this sentence?';

  @override
  String get historyDeletedOne => 'Sentence deleted';

  @override
  String historyWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get detailTitle => 'Sentence details';

  @override
  String get detailShare => 'Share';

  @override
  String detailWordBreakdown(int count) {
    return 'Word breakdown ($count)';
  }

  @override
  String get detailQuizTarget => '→ Appears in the quiz';

  @override
  String get detailTapForTone => 'Tap to see the tones';

  @override
  String get detailUsageSection => 'How to use';

  @override
  String get detailWordsSection => 'Words';

  @override
  String get detailFavoriteAdd => 'Add to favorites';

  @override
  String get detailFavoriteRemove => 'Remove from favorites';

  @override
  String get detailContextSection => 'Context and usage';

  @override
  String get detailContextTopic => 'Situation';

  @override
  String get detailContextStyle => 'Style';

  @override
  String get detailContextEmotion => 'Emotion and tone';

  @override
  String get detailContextUsage => 'When it\'s used';

  @override
  String get detailContextCulture => 'Cultural background';

  @override
  String detailCreatedAt(String date) {
    return 'Created: $date';
  }

  @override
  String get detailCopied => 'Copied to clipboard';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsUser => 'User';

  @override
  String get settingsGuest => 'Guest';

  @override
  String get settingsRankingName => 'Name shown in the ranking';

  @override
  String get settingsNotSignedIn => 'Not signed in';

  @override
  String get settingsPlan => 'Plan';

  @override
  String get settingsPlanTrial => 'Premium trial';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignInToSave => 'Sign in to save progress';

  @override
  String get settingsSignOutConfirm => 'Sign out?';

  @override
  String get settingsDeleteAccountTitle => 'Delete account';

  @override
  String get settingsDeleteAccountConfirm =>
      'Deleting your account permanently erases all of your learning data, both on our servers and on this device. This can\'t be undone.';

  @override
  String get settingsAccountDeleted =>
      'Your account and all its data have been deleted';

  @override
  String get settingsFontSample => 'Sample';

  @override
  String get settingsLearningStatus => 'Learning status';

  @override
  String get settingsGuideSection => 'Guide';

  @override
  String get settingsLearningSection => 'Learning settings';

  @override
  String get settingsToneGuide => 'Tone guide';

  @override
  String get settingsToneGuideSubtitle => 'Learn the rules of Thai tones';

  @override
  String get settingsResetLearningData => 'Reset learning data';

  @override
  String get settingsResetLearningDataSubtitle =>
      'Clear sentences and quiz history on this device';

  @override
  String get settingsResetTitle => 'Reset learning data';

  @override
  String get settingsResetConfirm =>
      'Every sentence, quiz result, and bit of progress stored on this device will be deleted. Your account stays.';

  @override
  String get settingsResetDone => 'Learning data reset';

  @override
  String get settingsResetFailed => 'Reset failed';

  @override
  String get commonReset => 'Reset';

  @override
  String get settingsDailyNotification => 'Daily sentence notification';

  @override
  String get settingsDailyNotificationSubtitle =>
      'Notifies you about the sentence';

  @override
  String get settingsAllowNotificationInOsSettings =>
      'Allow notifications in your device settings';

  @override
  String get settingsNotificationTime => 'Notification time';

  @override
  String get settingsTopic => 'Topic';

  @override
  String get settingsTopicRandom => 'Chosen for you';

  @override
  String settingsNextLevelIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words to the next level',
      one: '1 word to the next level',
    );
    return '$_temp0';
  }

  @override
  String settingsFreeVocabLimit(int limit) {
    return 'The free plan caps out at $limit words';
  }

  @override
  String get settingsCouldNotOpenUrl => 'Couldn\'t open that link';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsTagline => 'Get plenty of exposure to Thai';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsContact => 'Contact us';

  @override
  String get settingsLifetimeMigration => 'Move to lifetime plan';

  @override
  String get settingsLifetimeMigrationSubtitle => 'No additional payment';

  @override
  String get lifetimeMigrationTitle => 'We\'ve added a lifetime plan';

  @override
  String get lifetimeMigrationBody =>
      'Thank you for staying with us. For our continuing subscribers, moving to the lifetime plan is free right now.';

  @override
  String get lifetimeMigrationNoCharge => 'No additional payment';

  @override
  String get lifetimeMigrationCancelNote =>
      'After moving, please turn off monthly auto-renewal yourself in your App Store account settings. Billing continues until you do.';

  @override
  String get lifetimeMigrationProgress => 'Moving your plan…';

  @override
  String get lifetimeMigrationDoneTitle => 'Moved to the lifetime plan';

  @override
  String get lifetimeMigrationDoneBody =>
      'You can use Premium from here on, forever. Don\'t forget to stop the monthly auto-renewal.';

  @override
  String get lifetimeMigrationFailedTitle => 'Couldn\'t move your plan';

  @override
  String get lifetimeMigrationFailedBody =>
      'Please try again in a little while. Your Premium access continues as before.';

  @override
  String get lifetimeMigrationConfirm => 'Move to lifetime';

  @override
  String get lifetimeMigrationLater => 'Later';

  @override
  String get trialEndedTitle => 'Your premium trial has ended';

  @override
  String get trialEndedBody => 'You\'re on the free plan starting today.';

  @override
  String get trialEndedKeepPremium => 'See the Premium plan';

  @override
  String get trialEndedKeepFree => 'Later';

  @override
  String get trialEndedChangeQuotaLabel => 'Sentences';

  @override
  String get trialEndedChangeQuotaPremium => 'Unlimited';

  @override
  String trialEndedChangeQuotaFree(int free) {
    return '$free times a day';
  }

  @override
  String get trialEndedChangeVocabLabel => 'Vocabulary score';

  @override
  String get trialEndedChangeVocabPremium => 'No cap';

  @override
  String trialEndedChangeVocabFree(int free) {
    return 'up to $free words';
  }

  @override
  String trialStartedTitle(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'You can try Premium for $days days',
      one: 'You can try Premium for 1 day',
    );
    return '$_temp0';
  }

  @override
  String get trialStartedBody =>
      'We\'ve unlocked features that aren\'t in the free plan, just for this period.';

  @override
  String get trialStartedChangeQuotaLabel => 'Sentences';

  @override
  String get trialStartedChangeQuota => 'Unlimited';

  @override
  String get trialStartedChangeTopicLabel => 'Topic selection';

  @override
  String get trialStartedChangeTopic =>
      'You can choose the topic of your sentences yourself';

  @override
  String get trialStartedStart => 'Got it';

  @override
  String get trialStartedSeePlans => 'See Premium';

  @override
  String get topicPickerTitle => 'Choose a topic';

  @override
  String get nextTopicPrefix => 'Next topic: ';

  @override
  String get topicPrefix => 'Topic: ';

  @override
  String get topicName_blDrama => 'Thai BL dramas';

  @override
  String get topicSub_blDrama =>
      'confessions, misunderstandings, reunions, jealousy, betrayal, making up, kabedon, pet names';

  @override
  String get topicName_romance => 'Dating and romance';

  @override
  String get topicSub_romance =>
      'confessions, dates, sweet talk, long distance, breakups, making up';

  @override
  String get topicName_work => 'Work';

  @override
  String get topicSub_work =>
      'updates, meetings, overtime requests, small talk with coworkers';

  @override
  String get topicName_greetings => 'Greetings';

  @override
  String get topicSub_greetings =>
      'morning to night, first meetings, reunions, goodbyes, phone calls';

  @override
  String get topicName_food => 'Food';

  @override
  String get topicSub_food =>
      'ordering, reactions, street stalls, spice levels, allergies';

  @override
  String get topicName_travel => 'Travel';

  @override
  String get topicSub_travel => 'hotels, directions, sights, airports, tours';

  @override
  String get topicName_family => 'Family';

  @override
  String get topicSub_family =>
      'introductions, raising kids, thanking parents, siblings, family events';

  @override
  String get topicName_shopping => 'Shopping';

  @override
  String get topicSub_shopping =>
      'haggling, sizes and colors, returns, night markets';

  @override
  String get topicName_transport => 'Transport';

  @override
  String get topicSub_transport =>
      'Grab, the BTS, motorbike taxis, songthaews, traffic';

  @override
  String get topicName_health => 'Health';

  @override
  String get topicSub_health =>
      'describing symptoms, pharmacies, massage, check-ups';

  @override
  String get topicName_weather => 'Weather';

  @override
  String get topicSub_weather => 'heat, rainy season, typhoons, sun protection';

  @override
  String get topicName_hobbies => 'Hobbies';

  @override
  String get topicSub_hobbies =>
      'Muay Thai, music, movies, golf, social media, games';

  @override
  String get topicName_school => 'School';

  @override
  String get topicSub_school =>
      'in class, homework, exams, after school, language school';

  @override
  String get topicName_religion => 'Religion and faith';

  @override
  String get topicSub_religion =>
      'temple etiquette, almsgiving, amulets, speaking to monks, Buddhist holidays';

  @override
  String get topicName_festivals => 'Traditions and festivals';

  @override
  String get topicSub_festivals =>
      'Songkran, Loy Krathong, royal ceremonies, regional dishes';

  @override
  String get topicName_etiquette => 'Etiquette';

  @override
  String get topicSub_etiquette =>
      'when to wai, polite speech, taboos, table manners, gifts';

  @override
  String get styleName_news => 'News article style';

  @override
  String get styleName_spoken => 'Colloquial style';

  @override
  String get styleName_polite => 'Polite';

  @override
  String get styleName_sns => 'Texting and social media';

  @override
  String get styleName_narrative => 'Narrative and literary style';

  @override
  String get vocabLevelIntro => 'Starter';

  @override
  String get vocabLevelBeginner => 'Beginner';

  @override
  String get vocabLevelUpperBeginner => 'Upper beginner';

  @override
  String get vocabLevelIntermediate => 'Intermediate';

  @override
  String get vocabLevelAdvanced => 'Advanced';

  @override
  String get vocabSeePremium => 'See Premium';

  @override
  String get commonClose => 'Close';

  @override
  String get paywallTitle => 'Premium';

  @override
  String get paywallTagline => 'Dive into the Thai-speaking world.';

  @override
  String get paywallSignInRequired => 'Sign-in required';

  @override
  String get paywallSignInForPurchase =>
      'Please sign in so your purchase carries over after you change phones.';

  @override
  String get paywallSignInForRestore =>
      'To restore your purchase, sign in with the account you bought it on.';

  @override
  String get paywallActive => 'You\'re subscribed to the Premium plan';

  @override
  String get paywallSubscribe => 'Sign up for Premium';

  @override
  String get paywallPlanMonthlyTitle => 'Monthly';

  @override
  String get paywallPlanMonthlyNote => 'Renews monthly. Cancel anytime.';

  @override
  String paywallPlanMonthlyPrice(String price) {
    return '$price / month';
  }

  @override
  String get paywallPlanLifetimeTitle => 'Lifetime';

  @override
  String get paywallPlanLifetimeNote => 'One payment. No renewal.';

  @override
  String get paywallPurchaseCta => 'Start with this plan';

  @override
  String get paywallLifetimeNote => 'A one-time payment. No renewals.';

  @override
  String get paywallLegal =>
      'Your subscription renews automatically. You can cancel up to 24 hours before the period ends. Renewals are charged within 24 hours of the period ending, and you can manage or cancel from your App Store account settings.';

  @override
  String get paywallRestore => 'Restore purchase';

  @override
  String paywallPriceYen(String amount) {
    return '¥$amount / month';
  }

  @override
  String paywallPrice(String currency, String amount) {
    return '$currency $amount / month';
  }

  @override
  String get paywallFeatureQuotaTitle => 'Get lots of exposure to good Thai';

  @override
  String get paywallFeatureQuotaPremium => 'Unlimited sentences · no word cap';

  @override
  String get paywallFeatureTopicTitle =>
      'Choose a topic and get closer to Thai culture';

  @override
  String get paywallFeatureTopicPremium =>
      'Choose for yourself: festivals, temple etiquette, BL dramas';

  @override
  String get paywallTrialActive =>
      'You\'re on the Premium trial right now. When it ends, this goes back to how it was.';

  @override
  String get paywallTrialEnded =>
      'These are the features you could use during the trial.';

  @override
  String get onboarding1Title =>
      'AI delivers sentences made just for you, every day';

  @override
  String get onboarding1Body =>
      'Beyond the daily sentence, you can generate more on the spot.\nTap the card to check words and meanings.';

  @override
  String get onboarding2Title => 'Pronunciation practice, including tones';

  @override
  String get onboarding2Body =>
      'Listen to the model, then record your own voice.\nCheck where your tones are off, right there.';

  @override
  String get onboarding3Title => 'Raise your vocabulary score with quizzes';

  @override
  String get onboarding3Body =>
      'Words you get wrong come back again.\nSentences level up with your score.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get interviewIntroTitle => 'Four quick questions';

  @override
  String get interviewIntroBody =>
      'We\'ll match how we explain this app\'s way of learning to your answers. It\'s over quickly.';

  @override
  String get interviewIntroStart => 'Start';

  @override
  String interviewStepLabel(int current, int total) {
    return '$current / $total';
  }

  @override
  String get interviewLevelQuestion => 'How much Thai have you studied?';

  @override
  String get interviewLevelNone => 'Completely new to it';

  @override
  String get interviewLevelChars => 'I can read a few letters';

  @override
  String get interviewLevelWords => 'I know some words and greetings';

  @override
  String get interviewLevelConv => 'I can hold an everyday conversation';

  @override
  String get interviewGoalQuestion =>
      'In what situations do you want to use Thai?';

  @override
  String get interviewGoalTravel => 'For travel';

  @override
  String get interviewGoalWork => 'Needed for work';

  @override
  String get interviewGoalLive => 'Living in Thailand';

  @override
  String get interviewGoalCulture => 'Enjoying dramas and music';

  @override
  String get interviewTimeQuestion => 'How much can you study in a day?';

  @override
  String get interviewTimeShort => 'Just a few minutes';

  @override
  String get interviewTimeMedium => 'About 10 minutes';

  @override
  String get interviewTimeLong => '30 minutes or more';

  @override
  String get interviewStruggleQuestion =>
      'Have you got stuck on anything in Thai?';

  @override
  String get interviewStruggleNone => 'I\'ve only just started';

  @override
  String get interviewStruggleScript => 'I can\'t read the letters';

  @override
  String get interviewStruggleTone => 'Tones are difficult';

  @override
  String get interviewStruggleVocab => 'I can\'t remember words';

  @override
  String get philosophyHeading => 'This app\'s approach';

  @override
  String get philosophy1None =>
      'Start by learning each sentence from its **sound and meaning**. For **Thai letters**, start with a rough sense of the shapes and learn them slowly.';

  @override
  String get philosophy1Chars =>
      'Each sentence is **broken down word by word**, showing meaning and pronunciation. The more Thai letters you can read, the more you can follow on your own.';

  @override
  String get philosophy1Words =>
      'Sentences are generated to match your **vocabulary score** in the app. From the stage of greetings only, they widen out into everyday phrasing.';

  @override
  String get philosophy1Conv =>
      'How difficult your sentences are is decided by your **quiz results**. The more you get right, the wider the range of words that appears.';

  @override
  String get philosophyKeyWord =>
      'Every sentence has **one central word**. Learn how that word is actually used through the sentence.';

  @override
  String get philosophy2None =>
      'It\'s fine if you can\'t read Thai letters at first. This app also teaches **how Thai letters relate to tones**.';

  @override
  String get philosophy2Script =>
      'In Thai, **the spelling decides the tone**. In this app you can check how that works word by word.';

  @override
  String get philosophy2Tone =>
      'Make use of the **pronunciation practice**. Compare the model with your own voice to see where in a word your tone is off.';

  @override
  String get philosophy2Vocab =>
      '**Quizzes** measure how well each word has stuck. Words you\'re shaky on are asked again later.';

  @override
  String get philosophy3Travel =>
      '**With Premium**, you can choose the topic of your sentences yourself. Pick “Travel” or “Transport” and you\'ll get sentences for situations you meet on the ground.';

  @override
  String get philosophy3Work =>
      '**With Premium**, you can choose the topic of your sentences yourself. Pick “Work” and you\'ll get sentences for situations at your workplace.';

  @override
  String get philosophy3Live =>
      '**With Premium**, you can choose the topic of your sentences yourself. Pick “Shopping” or “Family” and you\'ll get sentences you use in daily life.';

  @override
  String get philosophy3Culture =>
      '**With Premium**, you can choose the topic of your sentences yourself. Pick “Thai BL dramas” or “Traditions and festivals” and you\'ll get the expressions that appear in those works and in the culture.';

  @override
  String get philosophy3TimeShort =>
      '**In a few minutes**, you can read one sentence and get through the check quiz.';

  @override
  String get philosophy3TimeMedium =>
      '**In ten minutes**, you can add sentences and get as far as pronunciation practice and reviewing the words so far.';

  @override
  String get philosophy3TimeLong =>
      '**In thirty minutes**, on top of adding sentences and pronunciation practice, you can manage reviewing past sentences and studying tones.';

  @override
  String get philosophyStart => 'See how to use it';

  @override
  String get notifCoachTitle => 'Make studying Thai a habit with notifications';

  @override
  String get notifCoachStep1 =>
      'Decide on a time that\'s easy to keep up — your commute, or before bed';

  @override
  String get notifCoachStep2 =>
      'At that time, a sentence for you arrives automatically';

  @override
  String get notifCoachHabit =>
      'Opening it at the same time every day makes it easy to keep going';

  @override
  String get notifCoachPreviewLabel => 'Example notification';

  @override
  String get notifCoachNow => 'now';

  @override
  String get notifCoachSampleTitle => '🇹🇭 Today\'s Thai · ขอบคุณ (thank you)';

  @override
  String get notifCoachSampleBody => '→ Thank you for the coffee';

  @override
  String get notifCoachEnable => 'Turn on notifications';

  @override
  String get notifCoachLater => 'Later';

  @override
  String get notifCoachEnabled =>
      'Your daily sentence will arrive at this time. You can change it in Settings.';

  @override
  String get notifCoachStillQuiet =>
      'Notifications will keep arriving quietly in Notification Center.';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get premiumHint1Title =>
      'Choose a topic and get closer to Thai culture';

  @override
  String get premiumHint1Body =>
      'Festivals, temple etiquette, BL dramas — you take in the culture along with the language';

  @override
  String get signInReminderTitle => 'Protect your learning progress';

  @override
  String get signInReminderMessage =>
      'Sign in and your progress is saved, so you can keep learning after you change phones. If you don\'t sign in, your progress is deleted after three days without using the app.';

  @override
  String get signInReminderBanner =>
      'Protect your learning data\nIf you don\'t sign in, your progress is deleted after three days without using the app.';

  @override
  String get commonLater => 'Later';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInSheetMessage =>
      'Save your progress and keep learning after you change phones.';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get quizOfferToQuiz => 'To the check quiz';

  @override
  String get quizOfferOneQuestion => 'Check if it stuck';

  @override
  String get quizOfferBody =>
      'Check with a quiz whether you\'ve learned the words.';

  @override
  String get quizOfferTryOne => 'Check';

  @override
  String get audioRepeat => 'Repeat';

  @override
  String get audioOnce => 'Once';

  @override
  String get audioPause => 'Pause';

  @override
  String get audioPlay => 'Play';

  @override
  String audioModeHint(String mode) {
    return 'Currently $mode. Long-press to change how it plays';
  }

  @override
  String get audioModeRepeat => 'on repeat';

  @override
  String get audioModeOnce => 'playing once';

  @override
  String get audioPosition => 'Playback position';

  @override
  String get pronunciationTitle => 'Try pronouncing it';

  @override
  String get pronunciationHoldToSpeak => 'Hold to speak';

  @override
  String get pronunciationRecording => 'Recording… release to check';

  @override
  String get pronunciationAnalyzing => 'Checking…';

  @override
  String get pronunciationRetry => 'Once more';

  @override
  String get pronunciationReference => 'Model';

  @override
  String get pronunciationYours => 'You';

  @override
  String pronunciationScore(int score) {
    return '$score points';
  }

  @override
  String get pronunciationVerdictCorrect => 'Correct';

  @override
  String get pronunciationVerdictClose => 'Close';

  @override
  String get pronunciationVerdictWrong => 'It\'s off';

  @override
  String get pronunciationVerdictUnscored => 'Couldn\'t check';

  @override
  String get pronunciationTooQuiet =>
      'We couldn\'t hear you. Try again somewhere quieter.';

  @override
  String get pronunciationNoSpeakerRange =>
      'We couldn\'t read your pitch. Please try again.';

  @override
  String get pronunciationNoSyllables =>
      'Pronunciation practice isn\'t available for this sentence.';

  @override
  String get pronunciationMonotone =>
      'Your pitch barely moved. Listen to the model, then say it again with the rises and falls.';

  @override
  String get pronunciationCaptureFailed =>
      'We couldn\'t get any audio from the microphone. Please try again.';

  @override
  String get pronunciationPermissionTitle => 'Microphone access needed';

  @override
  String get pronunciationPermissionBody =>
      'We use the microphone to check your pronunciation. Your audio is processed entirely on this device and is never uploaded.';

  @override
  String get pronunciationPermissionOpenSettings => 'Open settings';

  @override
  String get pronunciationSpeechRecognized =>
      'Pronunciation (consonants, vowels): came through';

  @override
  String get pronunciationSpeechMissing =>
      'Pronunciation (consonants, vowels): didn\'t come through';

  @override
  String get pronunciationSpeechUnavailable =>
      'Consonants and vowels can\'t be checked right now — showing tones only';

  @override
  String get pronunciationSpeechNoAsset =>
      'Thai dictation isn\'t installed on this device, so consonants and vowels can\'t be checked — showing tones only';

  @override
  String get pronunciationSpeechNoAssetHow =>
      'Add the Thai keyboard in Settings → General → Keyboard and turn on Dictation to enable it.';

  @override
  String get pronunciationSpeechAuthDenied =>
      'Speech recognition isn\'t allowed, so consonants and vowels can\'t be checked — showing tones only';

  @override
  String get pronunciationSpeechAndroid =>
      'Checking consonants and vowels isn\'t supported on Android — showing tones only';

  @override
  String get pronunciationCoachLead => 'Fix this next';

  @override
  String get pronunciationCoachShapeMid =>
      'Mid tone: hold it flat, at the same height throughout';

  @override
  String get pronunciationCoachShapeLow =>
      'Low tone: stay low and let it drift down slightly';

  @override
  String get pronunciationCoachShapeFalling =>
      'Falling tone: start high and fall all the way down';

  @override
  String get pronunciationCoachShapeHigh =>
      'High tone: keep pushing it up to the end instead of leveling off';

  @override
  String get pronunciationCoachShapeRising =>
      'Rising tone: dip first, then rise all the way up';

  @override
  String pronunciationCoachStepUp(String tone) {
    return '$tone: start higher than the sound before it';
  }

  @override
  String pronunciationCoachStepDown(String tone) {
    return '$tone: start lower than the sound before it';
  }

  @override
  String pronunciationCoachNotRecognized(String word) {
    return '\"$word\" wasn\'t picked up. Try saying it more clearly.';
  }

  @override
  String pronunciationSegmentUnaspirated(
      String word, String label, String aspirated) {
    return 'Say the $label in \"$word\" with no puff of air — with air it sounds like $aspirated.';
  }

  @override
  String pronunciationSegmentFinalP(String word) {
    return 'End \"$word\" with your lips closed — don\'t release it or add a vowel.';
  }

  @override
  String pronunciationSegmentFinalT(String word) {
    return 'End \"$word\" with your tongue tip in place — don\'t release it or add a vowel.';
  }

  @override
  String pronunciationSegmentFinalK(String word) {
    return 'End \"$word\" by stopping at the back of the throat — don\'t release it or add a vowel.';
  }

  @override
  String pronunciationSegmentNgInitial(String word) {
    return 'Start \"$word\" with ง humming through the nose — don\'t add an \"n\" before it.';
  }

  @override
  String pronunciationSegmentFinalNg(String word) {
    return 'End \"$word\" through the nose with your mouth open (-ng), not with closed lips.';
  }

  @override
  String pronunciationSegmentFinalN(String word) {
    return 'End \"$word\" with your tongue tip behind the teeth (-n), not through the nose.';
  }

  @override
  String pronunciationSegmentFinalM(String word) {
    return 'End \"$word\" with your lips closed (-m).';
  }

  @override
  String pronunciationSegmentVowelAe(String word) {
    return 'For the vowel in \"$word\", open your mouth wider and stretch it sideways, past \"e\" (ɛ).';
  }

  @override
  String pronunciationSegmentVowelOe(String word) {
    return 'For the vowel in \"$word\", hardly move your mouth at all — a muffled \"uh\" (ə).';
  }

  @override
  String pronunciationSegmentVowelAw(String word) {
    return 'For the vowel in \"$word\", make your lips a bigger, rounder circle than for \"o\" (ɔ).';
  }

  @override
  String pronunciationSegmentVowelUe(String word) {
    return 'For the vowel in \"$word\", say \"oo\" while keeping your lips stretched sideways, never pushed forward (ʉ).';
  }

  @override
  String pronunciationSummaryRecognized(int ok, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total words',
      one: '1 word',
    );
    return '$ok of $_temp0 came through';
  }

  @override
  String pronunciationNextFocus(String word) {
    return 'Fix \"$word\" next';
  }

  @override
  String get pronunciationCountCorrect => 'OK';

  @override
  String get pronunciationCountClose => 'Close';

  @override
  String get pronunciationCountWrong => 'Fix';

  @override
  String get pronunciationTapWordHintDetail =>
      'Tap a word to hear the model and see what to fix';

  @override
  String get pronunciationListenModelWord => 'Listen to the model';

  @override
  String tipWithExample(String content, String example) {
    return '$content\nExample: $example';
  }

  @override
  String get errQuizGenerationFailed =>
      'Failed to generate the quiz. Please try again.';

  @override
  String get quotaQuizReached => 'That\'s the last new quiz for today.';

  @override
  String get quotaSentenceReached =>
      'That\'s the last new sentence for today.\nYou can still revisit past sentences in History.';

  @override
  String get quotaSentenceUpgradeCta => 'With Premium, sentences are unlimited';

  @override
  String get errAuth =>
      'An authentication error occurred. Please restart the app.';

  @override
  String get errNetwork =>
      'A network connection error occurred. Please check your internet connection.';

  @override
  String get errTimeout => 'The request timed out. Please try again.';

  @override
  String get errServer =>
      'A server error occurred. Please wait a while and try again.';

  @override
  String get errSentenceGenerationFailed =>
      'Failed to generate a sentence. Please try again.';

  @override
  String get errLoadFailed => 'Failed to load data';

  @override
  String get errLoadFailedRetry => 'Failed to load data. Please try again.';

  @override
  String errUnexpected(String error) {
    return 'An unexpected error occurred: $error';
  }

  @override
  String get errSignInRequiredForPremium => 'Using Premium requires signing in';

  @override
  String get errProductLoadFailed => 'Couldn\'t load the purchase products';

  @override
  String get errPurchaseStartFailed => 'Couldn\'t start the purchase';

  @override
  String get errStoreUnavailable => 'Couldn\'t reach the App Store';

  @override
  String get errNothingToRestore => 'No restorable purchases were found';

  @override
  String get errRestoreFailed => 'Restore failed';

  @override
  String get errGoogleSignInFailed => 'Google sign-in failed';

  @override
  String get errAppleSignInFailed => 'Apple sign-in failed';

  @override
  String get errSignOutFailed => 'Sign-out failed';

  @override
  String get errDeleteAccountFailed => 'Account deletion failed';

  @override
  String quotaResetInHours(int hours, int minutes) {
    return '${hours}h ${minutes}m until the next reset';
  }

  @override
  String quotaResetInMinutes(int minutes) {
    return '${minutes}m until the next reset';
  }

  @override
  String shareTopic(String value) {
    return 'Situation: $value';
  }

  @override
  String shareStyle(String value) {
    return 'Style: $value';
  }

  @override
  String shareEmotion(String value) {
    return 'Tone: $value';
  }

  @override
  String shareUsage(String value) {
    return 'When it\'s used: $value';
  }

  @override
  String shareCulture(String value) {
    return 'Cultural background: $value';
  }

  @override
  String get contactSent => 'Your message has been sent. Thank you.';

  @override
  String get contactFailed =>
      'Failed to send. Please try again in a little while.';

  @override
  String get contactName => 'Your name';

  @override
  String get contactNameRequired => 'Please enter your name';

  @override
  String get contactEmail => 'Email address';

  @override
  String get contactEmailRequired => 'Please enter your email address';

  @override
  String get contactEmailInvalid => 'Please enter a valid email address';

  @override
  String get contactBody => 'Your message';

  @override
  String get contactBodyRequired => 'Please enter your message';

  @override
  String get contactSubmit => 'Send';

  @override
  String get consonantClassHigh => 'High class';

  @override
  String get consonantClassMiddle => 'Mid class';

  @override
  String get consonantClassLow => 'Low class';

  @override
  String get commonUnknownShort => 'Unknown';

  @override
  String get toneMarkNone => 'No tone mark';

  @override
  String get toneMarkMaiEk => 'Mai ek';

  @override
  String get toneMarkMaiTho => 'Mai tho';

  @override
  String get toneMarkMaiTri => 'Mai tri';

  @override
  String get toneMarkMaiChattawa => 'Mai chattawa';

  @override
  String get toneMarkSymbolNone => 'None';

  @override
  String get syllableLive => 'Live syllable';

  @override
  String get syllableDead => 'Dead syllable';

  @override
  String get syllableDeadShort => 'Dead syllable (short vowel)';

  @override
  String get syllableDeadLong => 'Dead syllable (long or compound vowel)';

  @override
  String get syllableLiveDesc =>
      'Ends in a long vowel, or in -m, -n, -ng, -y, or -w';

  @override
  String get syllableDeadDesc =>
      'A short vowel with no final consonant, or ends in -p, -t, or -k';

  @override
  String get toneMid => 'Mid tone';

  @override
  String get toneLow => 'Low tone';

  @override
  String get toneFalling => 'Falling tone';

  @override
  String get toneHigh => 'High tone';

  @override
  String get toneRising => 'Rising tone';

  @override
  String get toneAnalyzerEmptyWord => 'The word is empty';

  @override
  String get toneDialogTitle => 'Tone explanation';

  @override
  String get toneSyllableBreakdown => 'Syllable breakdown';

  @override
  String toneSyllableNumber(int number) {
    return 'Syllable $number';
  }

  @override
  String get toneMainConsonant => 'Initial consonant';

  @override
  String get toneSyllableType => 'Syllable type';

  @override
  String get toneResultPrefix => 'Result: ';

  @override
  String get toneMarkLabel => 'Tone mark';

  @override
  String get toneMarkPrefix => 'Tone mark: ';

  @override
  String get toneResultTone => 'Resulting tone';

  @override
  String toneShiftFor(String consonantClass) {
    return 'Tone shifts for $consonantClass';
  }

  @override
  String toneShiftTableFor(String consonantClass) {
    return 'Tone chart for $consonantClass';
  }

  @override
  String get toneRareUsage => 'Exceptional use (rare in modern Thai)';

  @override
  String get toneAppliedRule => '= the rule that applies to this word';

  @override
  String get toneLearnMore => 'Learn more about tones';

  @override
  String toneExamplePrefix(String value) {
    return 'Example: $value';
  }

  @override
  String get toneGuideTitle => 'Guide to Thai tones';

  @override
  String get toneGuideHeading => 'About Thai tones';

  @override
  String get toneGuideIntro =>
      'Thai has five tones, and the same spelling changes meaning depending on the tone. The tone is determined by the class of the consonant letter (high, mid, low), the tone mark, and the syllable type.';

  @override
  String get toneGuideFiveTones => 'The five tones';

  @override
  String get toneGuideConsonantClasses => 'Consonant classes';

  @override
  String get toneGuideToneMarks => 'Tone marks';

  @override
  String get toneGuideSyllableTypes => 'Syllable types';

  @override
  String get toneGuideShiftTable => 'Tone chart';

  @override
  String get toneGuideShiftTableIntro =>
      'For each consonant class, this shows the tone determined by the combination of tone mark and syllable type.';

  @override
  String toneGuideLetterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count letters',
      one: '1 letter',
    );
    return '$_temp0';
  }

  @override
  String get toneMidDesc =>
      'A tone whose pitch stays flat and doesn\'t change.';

  @override
  String get toneMidExample => 'กา (gaa) crow';

  @override
  String get toneLowDesc => 'A tone that starts low and falls slightly.';

  @override
  String get toneLowExample => 'ก่า (gàa) galangal';

  @override
  String get toneFallingDesc => 'A tone that drops from high to low.';

  @override
  String get toneFallingExample => 'ก้า (gâa) step';

  @override
  String get toneHighDesc => 'A tone that starts high and rises further.';

  @override
  String get toneHighExample => 'ก๊า (gáa) sentence-final particle';

  @override
  String get toneRisingDesc => 'A tone that rises from low to high.';

  @override
  String get toneRisingExample => 'ก๋า (gǎa) sentence-final particle';

  @override
  String get toneMarkMaiEkDesc =>
      'The first tone mark. The tone it produces depends on the consonant class.';

  @override
  String get toneMarkMaiThoDesc =>
      'The second tone mark. The tone it produces depends on the consonant class.';

  @override
  String get toneMarkMaiTriDesc =>
      'The third tone mark. Used with mid-class consonants; rare with low- or high-class ones.';

  @override
  String get toneMarkMaiChattawaDesc =>
      'The fourth tone mark. Used with mid-class consonants; rare with low- or high-class ones.';

  @override
  String get tipCatVowel => 'Vowels';

  @override
  String get tipCatCulture => 'Culture';

  @override
  String get tipCatTone => 'Tones';

  @override
  String get tipCatConsonant => 'Consonants';

  @override
  String get tipCatNumber => 'Numbers';

  @override
  String get tipCatDaily => 'Everyday phrases';

  @override
  String get tipCatStudy => 'Study tips';

  @override
  String get tip_vowelA_title => 'อะ / อา (a / aa)';

  @override
  String get tip_vowelA_content =>
      'Short อะ is \"a\"; long อา is \"aa\". Length alone changes the meaning.';

  @override
  String get tip_vowelA_example => 'จะ (jà = will) / จา (jaa = plate)';

  @override
  String get tip_vowelI_title => 'อิ / อี (i / ii)';

  @override
  String get tip_vowelI_content =>
      'Short อิ is a clipped \"i\"; long อี is a drawn-out \"ii\".';

  @override
  String get tip_vowelI_example => 'นิด (nít = a little) / นี่ (nîi = this)';

  @override
  String get tip_vowelU_title => 'อุ / อู (u / uu)';

  @override
  String get tip_vowelU_content =>
      'Short อุ is a clipped \"u\"; long อู is a drawn-out \"uu\".';

  @override
  String get tip_vowelU_example =>
      'รุ่น (rûn = generation) / รู้ (rúu = to know)';

  @override
  String get tip_vowelE_title => 'เอ / แอ (ee / ɛɛ)';

  @override
  String get tip_vowelE_content =>
      'เอ is \"ee\"; แอ is \"ɛɛ\", with your mouth open wider.';

  @override
  String get tip_vowelE_example => 'เก่ง (kèeng = skilled) / แก่ (kɛ̀ɛ = old)';

  @override
  String get tip_vowelO_title => 'โอ / ออ (oo / ɔɔ)';

  @override
  String get tip_vowelO_content =>
      'โอ is a rounded \"oo\"; ออ is an open \"ɔɔ\".';

  @override
  String get tip_vowelO_example => 'โต (too = big) / ต่อ (tɔ̀ɔ = to continue)';

  @override
  String get tip_vowelUea_title => 'เอือ (ʉa)';

  @override
  String get tip_vowelUea_content =>
      'เอือ has no English equivalent. It\'s written \"ʉa\".';

  @override
  String get tip_vowelUea_example => 'เมือง (mʉʉang = city, country)';

  @override
  String get tip_vowelUu_title => 'อือ / อื (ʉ / ʉʉ)';

  @override
  String get tip_vowelUu_content =>
      'No English equivalent: shape your mouth for \"i\" but say \"u\".';

  @override
  String get tip_vowelUu_example =>
      'คือ (khʉʉ = to be) / ฝืน (fʉ̌ʉn = to force oneself)';

  @override
  String get tip_vowelIa_title => 'เอีย (ia)';

  @override
  String get tip_vowelIa_content =>
      'เอีย is \"ia\" — glide smoothly from i to a.';

  @override
  String get tip_vowelIa_example => 'เรียน (riian = to study)';

  @override
  String get tip_vowelUa_title => 'อัว (ua)';

  @override
  String get tip_vowelUa_content =>
      'อัว is \"ua\" — glide smoothly from u to a.';

  @override
  String get tip_vowelUa_example => 'ตัว (tuua = body, classifier for animals)';

  @override
  String get tip_vowelAw_title => 'เอา (aw)';

  @override
  String get tip_vowelAw_content =>
      'เอา is \"aw\": start open, then round your lips.';

  @override
  String get tip_vowelAw_example => 'เอา (aw = to want, to take)';

  @override
  String get tip_vowelAi_title => 'ไอ / ใอ (ai)';

  @override
  String get tip_vowelAi_content =>
      'ไอ and ใอ sound identical. Only 20 words use ใ.';

  @override
  String get tip_vowelAi_example => 'ไป (pai = to go) / ใจ (jai = heart)';

  @override
  String get tip_vowelShortE_title => 'เอ็ (short e)';

  @override
  String get tip_vowelShortE_content =>
      'A clipped \"e\", written in the เ〜็ shape.';

  @override
  String get tip_vowelShortE_example => 'เก็บ (kèp = to pick up, to keep)';

  @override
  String get tip_vowelShortAe_title => 'แอ็ (short ɛ)';

  @override
  String get tip_vowelShortAe_content =>
      'A clipped \"ɛ\" with the mouth wide open, in the แ〜็ shape.';

  @override
  String get tip_vowelShortAe_example => 'แบ็ก (bɛ̀k = bag)';

  @override
  String get tip_vowelOe_title => 'เออ (əə)';

  @override
  String get tip_vowelOe_content =>
      'เออ is the neutral vowel \"əə\". Keep your mouth half open.';

  @override
  String get tip_vowelOe_example => 'เธอ (thəə = you, she)';

  @override
  String get tip_vowelLength_title => 'Vowel length changes meaning';

  @override
  String get tip_vowelLength_content =>
      'Length matters in Thai: a short vowel and a long one are different words.';

  @override
  String get tip_vowelLength_example => 'ปะ (pà = to meet) / ป้า (pâa = aunt)';

  @override
  String get tip_cultureWai_title => 'wâi (ไหว้)';

  @override
  String get tip_cultureWai_content =>
      'The Thai greeting: palms together. Raise them to your nose for elders, to your chest for peers.';

  @override
  String get tip_cultureTemple_title => 'Temple etiquette';

  @override
  String get tip_cultureTemple_content =>
      'Take off your shoes and cover your shoulders and knees. Never sit higher than a Buddha image.';

  @override
  String get tip_cultureSongkran_title => 'sǒngkraan (water festival)';

  @override
  String get tip_cultureSongkran_content =>
      'Thai New Year, 13–15 April. People splash water on each other to celebrate.';

  @override
  String get tip_cultureLoyKrathong_title =>
      'lɔɔi krathong (floating lanterns)';

  @override
  String get tip_cultureLoyKrathong_content =>
      'On the full moon of the 12th lunar month, people float lanterns down the river to thank the water spirits.';

  @override
  String get tip_cultureEating_title => 'How Thai food is eaten';

  @override
  String get tip_cultureEating_content =>
      'Fork and spoon: the fork pushes food onto the spoon, and the spoon goes in your mouth. Chopsticks are for noodles.';

  @override
  String get tip_cultureMaiPenRai_title => 'ไม่เป็นไร (mâi pen rai)';

  @override
  String get tip_cultureMaiPenRai_content =>
      '“Don\'t worry, it\'s fine.” A signature phrase that shows how easygoing Thai people are.';

  @override
  String get tip_toneFive_title => 'Thai has five tones';

  @override
  String get tip_toneFive_content =>
      'Mid, low, falling, high, and rising. Change the tone and you have a different word.';

  @override
  String get tip_toneFive_example =>
      'ไหม (mǎi = silk) / ใหม่ (mài = new) / ไม่ (mâi = not)';

  @override
  String get tip_toneMaiEk_title => 'Tone mark ่ (mái èek)';

  @override
  String get tip_toneMaiEk_content =>
      'The first tone mark, written above the letter. On mid- and high-class consonants it gives a low tone.';

  @override
  String get tip_toneMaiEk_example => 'เก่า (kàw = old), ข่าว (khàaw = news)';

  @override
  String get tip_toneMaiTho_title => 'Tone mark ้ (mái thoo)';

  @override
  String get tip_toneMaiTho_content =>
      'The second tone mark. On a mid-class consonant it gives a falling tone.';

  @override
  String get tip_toneMaiTho_example =>
      'น้ำ (náam = water), บ้าน (bâan = house)';

  @override
  String get tip_toneMaiTriChat_title => 'Tone marks ๊ and ๋';

  @override
  String get tip_toneMaiTriChat_content =>
      '๊ (mái trii) marks a high tone, ๋ (mái jàttawaa) a rising one. Both are uncommon.';

  @override
  String get tip_toneMaiTriChat_example =>
      'โน๊ต (nóot = note), จ๋า (jǎa = yes?)';

  @override
  String get tip_toneClassRelation_title => 'Consonant class and tone';

  @override
  String get tip_toneClassRelation_content =>
      'The tone comes from the consonant class (high, mid, low), vowel length, final consonant, and tone mark together.';

  @override
  String get tip_toneMistake_title => 'Get the tone wrong and…';

  @override
  String get tip_toneMistake_content =>
      'สวย (sǔuai = beautiful) and ซวย (suuai = unlucky): the tone changes the meaning completely.';

  @override
  String get tip_toneMidExplain_title => 'Mid tone (sǎa-man)';

  @override
  String get tip_toneMidExplain_content =>
      'Flat, at your normal pitch. The default for a mid-class consonant with a long vowel and no tone mark.';

  @override
  String get tip_toneMidExplain_example => 'กา (kaa = crow), ดี (dii = good)';

  @override
  String get tip_toneRisingExplain_title => 'Rising tone (jàttawaa)';

  @override
  String get tip_toneRisingExplain_content =>
      'Starts low and climbs — a bit like the way a question rises in English.';

  @override
  String get tip_toneRisingExplain_example =>
      'สวย (sǔuai = beautiful), หนาว (nǎaw = cold)';

  @override
  String get tip_toneRelative_title => 'Tone is relative';

  @override
  String get tip_toneRelative_content =>
      'How high a tone sounds depends on the syllable before it, so learn whole phrases rather than isolated words.';

  @override
  String get tip_consonant44_title => 'Thai has 44 consonants';

  @override
  String get tip_consonant44_content =>
      '44 letters, of which 42 are still in use — but they cover only 21 distinct sounds.';

  @override
  String get tip_consonantHigh_title => 'High class (àksɔ̌ɔn sǔung)';

  @override
  String get tip_consonantHigh_content =>
      'The 11 letters ข ฃ ฉ ฐ ถ ผ ฝ ศ ษ ส ห. Their tone rules differ from mid- and low-class ones.';

  @override
  String get tip_consonantMid_title => 'Mid class (àksɔ̌ɔn klaang)';

  @override
  String get tip_consonantMid_content =>
      'The 9 letters ก จ ฎ ฏ ด ต บ ป อ. The baseline group, where tone marks do exactly what they say.';

  @override
  String get tip_consonantLow_title => 'Low class (àksɔ̌ɔn tàm)';

  @override
  String get tip_consonantLow_content =>
      'The remaining 24 letters. They split into ones paired with a high-class letter and ones that stand alone.';

  @override
  String get tip_consonantFinal_title => 'Final consonant rules';

  @override
  String get tip_consonantFinal_content =>
      'Only 8 sounds can end a syllable: k, t, p, n, m, ng, i, o. A letter often changes sound in final position.';

  @override
  String get tip_consonantFinal_example =>
      'บ, ป, พ, ภ, ฟ all become -p at the end of a syllable';

  @override
  String get tip_consonantAspiration_title => 'Aspirated and unaspirated';

  @override
  String get tip_consonantAspiration_content =>
      'Thai distinguishes consonants by the puff of air. ป (unaspirated p) and พ (aspirated ph) are different sounds.';

  @override
  String get tip_consonantAspiration_example =>
      'ปลา (plaa = fish) / พลา (phlaa = to fail)';

  @override
  String get tip_consonantSilent_title => 'The silent mark ์ (kaa-ran)';

  @override
  String get tip_consonantSilent_content =>
      'A ์ above a letter means \"don\'t pronounce this one\". Common in loanwords.';

  @override
  String get tip_consonantSilent_example =>
      'จันทร์ (jan = moon) — the ร์ is silent';

  @override
  String get tip_consonantCluster_title => 'Clusters (àksɔ̌ɔn khûap)';

  @override
  String get tip_consonantCluster_content =>
      'Two consonants in a row are pronounced together: kr, kl, pr, pl, and so on.';

  @override
  String get tip_consonantCluster_example =>
      'กรุง (krung = capital) / ปลา (plaa = fish)';

  @override
  String get tip_numberThai_title => 'Thai numerals';

  @override
  String get tip_numberThai_content =>
      'Thai has its own digits: ๐๑๒๓๔๕๖๗๘๙ (0–9). You\'ll see them on signs and official documents.';

  @override
  String get tip_number1to5_title => 'Counting 1 to 5';

  @override
  String get tip_number1to5_content =>
      '๑ nʉ̀ng, ๒ sɔ̌ɔng, ๓ sǎam, ๔ sìi, ๕ hâa';

  @override
  String get tip_number6to10_title => 'Counting 6 to 10';

  @override
  String get tip_number6to10_content => '๖ hòk, ๗ jèt, ๘ pɛ̀ɛt, ๙ kâw, ๑๐ sìp';

  @override
  String get tip_number11and21_title => '11 and 21 are special';

  @override
  String get tip_number11and21_content =>
      '11 is sìp èt and 21 is yîi sìp èt — both the ones digit and the twenties are irregular.';

  @override
  String get tip_numberClassifier_title => 'Classifiers (láksanànaam)';

  @override
  String get tip_numberClassifier_content =>
      'Counting needs a number plus a classifier, the way English says \"two sheets of paper\".';

  @override
  String get tip_numberClassifier_example =>
      'khon (people), tua (animals), an (small objects)';

  @override
  String get tip_numberBig_title => 'Hundreds and thousands';

  @override
  String get tip_numberBig_content =>
      'rɔ́ɔi (hundred), phan (thousand), mʉ̀ʉn (ten thousand), sǎen (hundred thousand), láan (million)';

  @override
  String get tip_numberPrice_title => 'Asking the price';

  @override
  String get tip_numberPrice_content =>
      '\"How much is it?\" is thâo rài. Learn it alongside raakhaa (price).';

  @override
  String get tip_numberPrice_example => 'an-níi thâo rài (how much is this?)';

  @override
  String get tip_dailyPolite_title => 'ครับ / ค่ะ (khráp / khâ)';

  @override
  String get tip_dailyPolite_content =>
      'Men end sentences with khráp, women with khâ, to sound polite. This is basic Thai manners.';

  @override
  String get tip_dailyPolite_example => 'khɔ̀ɔp khun khráp / khɔ̀ɔp khun khâ';

  @override
  String get tip_dailyHello_title => 'สวัสดี (sà-wàt-dii)';

  @override
  String get tip_dailyHello_content =>
      '\"Hello\" — works any time of day, and on the way out too.';

  @override
  String get tip_dailyThanks_title => 'ขอบคุณ (khɔ̀ɔp khun)';

  @override
  String get tip_dailyThanks_content =>
      '\"Thank you.\" Add mâak for \"thank you very much\".';

  @override
  String get tip_dailySorry_title => 'ขอโทษ (khɔ̌ɔ thôot)';

  @override
  String get tip_dailySorry_content =>
      '\"Sorry\" or \"excuse me\" — it works both for apologising and for getting someone\'s attention.';

  @override
  String get tip_dailyYesNo_title => 'ใช่ / ไม่ใช่ (châi / mâi châi)';

  @override
  String get tip_dailyYesNo_content =>
      '\"Yes\" and \"no\", used to answer a question that\'s checking something.';

  @override
  String get tip_dailyYesNo_example =>
      'châi mǎi (is that right?) → châi khráp (yes)';

  @override
  String get tip_dailyEat_title => 'กิน (kin) = to eat';

  @override
  String get tip_dailyEat_content =>
      '\"Have you eaten?\" — kin khâao rʉ̌ʉ yang — is a standard Thai greeting.';

  @override
  String get tip_dailyDelicious_title => 'อร่อย (à-ròi) = delicious';

  @override
  String get tip_dailyDelicious_content =>
      'Say à-ròi after a good meal. Add mâak and it\'s \"really delicious\".';

  @override
  String get tip_dailyPronouns_title => 'Choosing a pronoun';

  @override
  String get tip_dailyPronouns_content =>
      'phǒm is the formal \"I\" for men, dì-chǎn for women.';

  @override
  String get tip_dailyPronouns_example =>
      'Casually, rao and chǎn are common too';

  @override
  String get tip_studyThaiOnly_title => 'Take on the quiz in Thai alone';

  @override
  String get tip_studyThaiOnly_content =>
      'Take the quiz and see whether you understand the meaning from the Thai alone, without looking at the sentence or the notes!';

  @override
  String get errPurchaseStatusFailed => 'Failed to get your purchase status';

  @override
  String get errPurchaseGeneric => 'A purchase error occurred';

  @override
  String get purchasePending =>
      'Your purchase is awaiting approval. It\'ll apply once approved.';

  @override
  String get errSignInBeforePurchase => 'Please sign in before purchasing';

  @override
  String get errPurchaseVerificationFailed => 'Purchase verification failed';

  @override
  String get settingsVocabTest => 'Measure your vocabulary';

  @override
  String get settingsVocabTestNever => 'Not taken yet';

  @override
  String settingsVocabTestLast(String date) {
    return 'Last time $date';
  }

  @override
  String get settingsVocabTestPremium => 'Premium only';

  @override
  String get vocabTestTitle => 'Measure your vocabulary';

  @override
  String get vocabTestIntroBody =>
      'You answer Thai words from four choices, and we measure your current vocabulary. It ends as soon as you hit a run of words you don\'t know. As few as 6 questions — the more words you know, the longer it runs.';

  @override
  String get vocabTestIntroNote =>
      'The result is reflected in the difficulty of your sentences and quizzes. You can retake it from Settings up to once a month.';

  @override
  String get vocabTestStart => 'Start';

  @override
  String get vocabTestQuestion => 'What does this word mean?';

  @override
  String get vocabTestDontKnow => 'I don\'t know';

  @override
  String vocabTestProgress(int current) {
    return 'Question $current';
  }

  @override
  String get vocabTestResultTitle => 'Your current vocabulary';

  @override
  String vocabTestResultVocab(int vocab) {
    return 'About $vocab words';
  }

  @override
  String get vocabTestResultBody =>
      'We use this result as a starting point to match the difficulty of your sentences and quizzes. As you use the app, it shifts little by little based on your actual answers.';

  @override
  String get vocabTestResultFreeCap =>
      'On the free plan the vocabulary score is capped at 100. When your premium trial ends, this number drops to 100 as well.';

  @override
  String get vocabTestResultClose => 'Close';

  @override
  String get vocabTestError => 'Could not run the vocabulary test';

  @override
  String get vocabTestRetry => 'Start over';

  @override
  String get rankingTitle => 'Vocabulary ranking';

  @override
  String get rankingSubtitle =>
      'Compare with other learners by vocabulary score';

  @override
  String rankingBandScope(String band) {
    return 'Your rank within $band';
  }

  @override
  String get rankingYourRank => 'Your rank';

  @override
  String rankingPosition(int rank) {
    return '#$rank';
  }

  @override
  String get rankingCapTiedNote =>
      'Too many people are tied at the cap, so no rank is given';

  @override
  String get rankingUnrankedHint => 'Generate a sentence to get a rank';

  @override
  String get rankingLoadFailed => 'Couldn\'t load the ranking';

  @override
  String get rankingYou => 'You';

  @override
  String get rankingDistributionTitle => 'Score distribution';

  @override
  String get rankingDistributionSubtitle =>
      'Number of learners per band. The colored one is where you are';

  @override
  String rankingPercentile(int percent) {
    return 'Top $percent%';
  }

  @override
  String rankingBandOver(int min) {
    return '$min+';
  }

  @override
  String rankingBandRange(int min, int max) {
    return '$min–$max';
  }

  @override
  String rankingAnonymousName(String suffix) {
    return 'User $suffix';
  }

  @override
  String rankingFreeCapNote(int limit) {
    return 'On the free plan your vocabulary score is capped at $limit words';
  }

  @override
  String get settingsRanking => 'Ranking';

  @override
  String get settingsRankingSubtitle =>
      'Compare with other learners by vocabulary score';

  @override
  String get guideTitle => 'How-to guide';

  @override
  String get guideSettingsSubtitle => 'Read through how to use the app';

  @override
  String get guideSkip => 'Skip';

  @override
  String get guideStart => 'Measure your vocabulary';

  @override
  String get guideClose => 'Close';

  @override
  String get guideLead =>
      'This sums up how to use the app. You can read it again any time from Settings.';

  @override
  String get guideFigureLoopSentence => 'Sentence';

  @override
  String get guideFigureLoopQuiz => 'Quiz';

  @override
  String get guideFigureLoopRepeat => 'repeat';

  @override
  String get guideFigureLoopSummary => 'Summary quiz';

  @override
  String get guideFigureLoopEvery => 'every five sentences';

  @override
  String get guideFigureCardThai => 'Thai script';

  @override
  String get guideFigureCardPronunciation => 'Pronunciation';

  @override
  String get guideFigureCardTranslation => 'Translation';

  @override
  String get guideFigureCardTranslationSample => 'I like coffee.';

  @override
  String get guideFigureCardTargetWord => 'Gold = target word';

  @override
  String get guideChapterOverview => 'Overview';

  @override
  String get guideChapterRoles => 'What each feature is for';

  @override
  String get guideChapterHowTo => 'How to use it';

  @override
  String get guideOverviewTitle => 'What you do in this app';

  @override
  String get guideOverviewBody1 =>
      'Every day, AI creates five Thai sentences at once, matched to your vocabulary.';

  @override
  String get guideOverviewBody2 =>
      'Learn with a sentence → check with a quiz. Repeat that five times and that\'s one round.';

  @override
  String get guideOverviewSummaryQuiz =>
      'After you finish five sentences, you move on to the summary quiz. It\'s drawn from the sentences you\'ve studied so far, and if you\'re unsure you can use hints or look back at the sentence.';

  @override
  String get guideOverviewBody3 =>
      'The more you get right in the summary quiz, the higher your vocabulary score, and the wider the range of words that appears in your sentences. Sentences you got wrong are asked again, so you don\'t have to manage the order of what to relearn yourself.';

  @override
  String get guideRoleSentenceTitle => 'Sentences';

  @override
  String get guideRoleSentenceBody =>
      'Check how Thai words are used from the detail screen. Remembering a word together with the situation it\'s used in sticks better than the word alone.';

  @override
  String get guideRoleSoundTitle => 'Pronunciation practice';

  @override
  String get guideRoleSoundBody =>
      'Compare your own intonation with the model to get the knack of pronunciation. In Thai, tone changes meaning.';

  @override
  String get guideRoleQuizTitle => 'Quizzes';

  @override
  String get guideRoleQuizBody =>
      'There are two kinds of quiz. The check quiz is one question choosing a word\'s meaning before you go on to the next sentence. After the fifth, you move on to the summary quiz, where you choose the word for the underlined part from the sentences you\'ve studied.';

  @override
  String get guideRoleScoreTitle => 'Vocabulary score';

  @override
  String get guideRoleScoreBody =>
      'A score representing your vocabulary, calculated from your quiz results.';

  @override
  String get guideRoleVocabTestTitle => 'Vocabulary test';

  @override
  String get guideRoleVocabTestBody =>
      'A four-choice test that measures your current vocabulary. The result becomes the starting point for your vocabulary score and is reflected in the difficulty of your sentences and quizzes. You can retake it from Settings up to once a month.';

  @override
  String get guideRoleRankingTitle => 'Ranking';

  @override
  String get guideRoleRankingBody =>
      'Shows your rank when users are lined up by vocabulary score. Your display name is assigned automatically.';

  @override
  String get guideRoleTopicTitle => 'Topics';

  @override
  String get guideRoleTopicBody =>
      'Try Thai in all sorts of settings — festivals, temple etiquette, BL dramas and more. You get to touch Thai culture along with the language.';

  @override
  String get guideRoleNotificationTitle => 'Daily notifications';

  @override
  String get guideRoleNotificationBody =>
      'Useful for making Thai study a habit. The day\'s sentence arrives at the time you set.';

  @override
  String get guideRolePremiumTitle => 'Free and Premium';

  @override
  String get guideRolePremiumBody =>
      'You can keep up daily study on the free version too. With Premium, the number of sentences, topic choice, and the vocabulary score cap all expand.';

  @override
  String get guidePlanColItem => 'Item';

  @override
  String get guidePlanColFree => 'Free';

  @override
  String get guidePlanColPremium => 'Premium';

  @override
  String get guidePlanRowSentences => 'Sentences a day';

  @override
  String get guidePlanRowTopic => 'Topics';

  @override
  String get guidePlanRowVocab => 'Vocabulary cap';

  @override
  String get guidePlanSentencesUnlimited => 'Unlimited';

  @override
  String guidePlanSentences(int count) {
    return '$count';
  }

  @override
  String get guidePlanTopicFree => 'Chosen for you';

  @override
  String get guidePlanTopicPremium => 'You choose';

  @override
  String guidePlanVocabFree(int count) {
    return '$count words';
  }

  @override
  String guidePlanVocabPremium(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'About $countString words';
  }

  @override
  String get guideHowSentenceTitle => 'Read today\'s sentence';

  @override
  String get guideHowSentenceStep1 =>
      'Open the Learn tab to see today\'s sentence. Sentences come in sets of five, and the header shows how far along you are.';

  @override
  String get guideHowSentenceStep3 =>
      'Gold words are the ones you\'re learning. The quiz asks about those.';

  @override
  String get guideHowSentenceStep4 =>
      'Tap the sentence card to open the detail screen.';

  @override
  String get guideHowDetailTitle => 'The detail screen';

  @override
  String get guideHowDetailLead =>
      'The detail screen explains Thai sentences in more depth. The more clues you have — situation, style, spelling and tone — the better that word stays in memory.';

  @override
  String get guideHowSoundTitle => 'Listen and say it aloud';

  @override
  String get guideHowSoundStep1 =>
      '“Listen to the model” plays the audio of the Thai sentence on a loop.';

  @override
  String get guideHowSoundStep2 =>
      'In “Pronunciation practice” on the detail screen, hold down the “Hold to speak” button and read along, and it judges on the spot whether your tones match.';

  @override
  String get guideHowSoundStep3 =>
      'In pronunciation practice, green means correct, amber means close, and red means wrong. Tap a word to see the model\'s curve against your own, and how to fix it.';

  @override
  String get guideHowQuizTitle => 'Take the check quiz';

  @override
  String get guideHowQuizStep1 =>
      '“Check if it stuck” below the sentence takes you to the check quiz.';

  @override
  String get guideHowQuizStep2 =>
      'You choose the meaning of the target word (the gold one) from the sentence you just read, out of four options.';

  @override
  String get guideHowQuizStep3 =>
      'Once you answer, an explanation of that word\'s meaning and usage appears.';

  @override
  String get guideHowQuizStep4 =>
      'From the results screen, go on to the next sentence. After you finish the fifth, you flow straight into the summary quiz.';

  @override
  String get guideHowReviewQuizTitle => 'Take the summary quiz';

  @override
  String get guideHowReviewQuizStep1 =>
      'A milestone quiz that comes every time you finish five sentences. From the sentences you\'ve studied, you choose the word that goes in the blank.';

  @override
  String get guideHowReviewQuizStep2 =>
      'The sentences it asks about are chosen with gaps in between — the day before, three days ago, a week ago, and so on. Within those, words you haven\'t got down yet come first.';

  @override
  String get guideHowReviewQuizStep3 =>
      'You can use hints. Press once for the pronunciation, again for the translation. Once you\'re used to it, answering without hints makes your vocabulary score grow faster.';

  @override
  String get guideHowReviewQuizStep4 =>
      'If you\'re unsure, “Check the sentence” takes you back to the sentence.';

  @override
  String get guideHowReviewQuizStep5 =>
      'Correct answers here are what\'s reflected in your vocabulary score.';

  @override
  String get guideHowSettingsTitle => 'What you can do in Settings';

  @override
  String get guideHowSettingsStep1 =>
      'Change your notification time, the display font, and the language of translations and explanations.';

  @override
  String get guideHowSettingsStep2 =>
      'You can also open the topic selection for your next sentence and the ranking from here.';

  @override
  String get guideHowSettingsStep3 =>
      'You can open this guide any time from “How-to guide” in Settings.';
}
