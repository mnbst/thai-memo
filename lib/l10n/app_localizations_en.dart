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
  String get settingsLanguageNote =>
      'Changes the language of translations and notes. Sentences you already created keep the language they were created in.';

  @override
  String get navLearn => 'Learn';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get learnQuizTitle => 'Quiz';

  @override
  String get learnSummaryQuizTitle => 'Review quiz';

  @override
  String get learnNextSentence => 'Next sentence';

  @override
  String get firstGuideTitle => 'Let\'s try it once';

  @override
  String get firstGuideBody =>
      'You\'ll go through one full round, from a sentence to a quiz.\nI\'ll point out each button as you go.';

  @override
  String get firstGuideTrial => 'Your first 2 days are on Premium';

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Try again';

  @override
  String get coachDetailTitle => 'Tap the sentence first';

  @override
  String get coachDetailMessage =>
      'Tap the card to see the meaning and pronunciation of each word.';

  @override
  String get coachQuizTitle => 'Now try the quiz';

  @override
  String get coachQuizMessage =>
      'Once you\'ve read the sentence, move on to the quiz.';

  @override
  String get coachPronunciationTitle => 'Say it out loud';

  @override
  String get coachPronunciationMessage =>
      'Hold the button and read it aloud. Your tones are checked on the spot.';

  @override
  String get sentencePreparing => 'Preparing your next sentence...';

  @override
  String get todaysWords => 'Today\'s words';

  @override
  String get playPronunciation => 'Play pronunciation';

  @override
  String get sentenceUsingWord => 'A sentence using these words';

  @override
  String get badgePremiumSentence => 'Premium sentence';

  @override
  String get badgeFreeSentence => 'Free sentence';

  @override
  String get sampleSentenceNotice =>
      'Sample sentence (not saved to your history)';

  @override
  String get sampleGreetingTranslation => 'Hello (said by a man)';

  @override
  String get sampleGreetingWord1Meaning => 'hello, goodbye';

  @override
  String get sampleGreetingWord1Role => 'greeting';

  @override
  String get sampleGreetingWord2Meaning => 'polite particle used by men';

  @override
  String get sampleGreetingWord2Role => 'final particle';

  @override
  String get sampleGreetingTopic => 'everyday greetings';

  @override
  String get sampleGreetingStyle => 'conversational';

  @override
  String get sampleGreetingEmotion => 'polite, formal';

  @override
  String get sampleGreetingUsage =>
      'A basic greeting you can use any time of day. Women say ค่ะ instead.';

  @override
  String get quizTodayTitle => 'Today\'s quiz';

  @override
  String get quizOptionalChallenge => 'Take the 5-question challenge';

  @override
  String get quizGenerating => 'Building your quiz...';

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
  String get quizIncorrect => 'Not quite';

  @override
  String quizCorrectAnswer(String answer) {
    return 'Correct answer: $answer';
  }

  @override
  String get quizPrompt => 'Choose the word that fits the blank';

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
  String get quizCheckSentence => 'Show the sentence';

  @override
  String get quizPlaySentence => 'Play the sentence';

  @override
  String get quizPlayWord => 'Play the word';

  @override
  String get quizWhyCorrect => 'Why it\'s right';

  @override
  String get quizWhyIncorrect => 'Why it\'s wrong';

  @override
  String get quizSeeResults => 'See results';

  @override
  String get quizNextQuestion => 'Next question';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get coachQuizReviewTitle => 'You can go back to the sentence';

  @override
  String get coachQuizReviewMessage =>
      'Not sure of the answer? Check the sentence again from here before you answer.';

  @override
  String get coachSummaryQuizTitle => 'Try the review quiz';

  @override
  String get coachSummaryQuizEmphasis => 'every 5 sentences';

  @override
  String get coachSummaryQuizMessage =>
      'A quiz that reviews everything you\'ve studied. It normally comes around every 5 sentences. You can also skip it and move on to the next sentence.';

  @override
  String get coachTopicTitle => 'You can pick the next topic';

  @override
  String get coachTopicMessage =>
      'Tap here to change the topic of your next sentence (travel, romance, and more). Study whatever you\'re in the mood for.';

  @override
  String get vocabScore => 'Vocabulary score';

  @override
  String get vocabScoreCalculating => 'Calculating your vocabulary score...';

  @override
  String get vocabScoreUp => 'Your vocabulary grew!';

  @override
  String get vocabScoreCapped => 'Your vocabulary score has hit its cap';

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
  String get historySearchHint => 'Search in Thai or English';

  @override
  String get historyEmptyFavorites => 'No favorite sentences yet';

  @override
  String get historyEmptySearch => 'No matches found';

  @override
  String get historyEmpty => 'No sentences yet';

  @override
  String get historyEmptyFavoritesHint =>
      'Tap the heart on a sentence to save it here';

  @override
  String get historyEmptySearchHint => 'Try a different keyword';

  @override
  String get historyEmptyHint => 'Generate your first sentence';

  @override
  String get historyDeleteAllConfirm =>
      'Delete your entire sentence history? This can\'t be undone.';

  @override
  String get historyDeletedAll => 'Deleted every sentence';

  @override
  String historyDeleteFailed(String error) {
    return 'Couldn\'t delete: $error';
  }

  @override
  String get historyDeleteConfirmTitle => 'Delete this sentence?';

  @override
  String get historyDeleteConfirm =>
      'This sentence will be removed from your history.';

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
  String get detailContextSection => 'Context and usage';

  @override
  String get detailContextTopic => 'Setting';

  @override
  String get detailContextStyle => 'Register';

  @override
  String get detailContextEmotion => 'Mood';

  @override
  String get detailContextUsage => 'When to use it';

  @override
  String get detailContextCulture => 'Cultural background';

  @override
  String detailCreatedAt(String date) {
    return 'Created $date';
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
  String get settingsSignInToSave => 'Sign in to save your progress';

  @override
  String get settingsSignOutConfirm => 'Sign out of your account?';

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
  String get settingsLearningStatus => 'Your progress';

  @override
  String get settingsLearningSection => 'Learning';

  @override
  String get settingsToneGuide => 'Tone guide';

  @override
  String get settingsToneGuideSubtitle => 'Learn how Thai tones work';

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
  String get settingsResetFailed => 'Couldn\'t reset your data';

  @override
  String get commonReset => 'Reset';

  @override
  String get settingsDailyNotification => 'Daily sentence';

  @override
  String get settingsDailyNotificationSubtitle =>
      'We\'ll send you the day\'s sentence';

  @override
  String get settingsAllowNotificationInOsSettings =>
      'Allow notifications in your device settings';

  @override
  String get settingsNotificationTime => 'Delivery time';

  @override
  String get settingsTopic => 'Topic';

  @override
  String get settingsTopicRandom => 'Any topic';

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
  String get settingsTagline => 'A little Thai, every day';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsContact => 'Contact us';

  @override
  String get trialEndedTitle => 'Your premium trial has ended';

  @override
  String get trialEndedBody => 'You\'re on the free plan starting today.';

  @override
  String trialEndedChangeQuota(int premium, int free) {
    return 'Sentences  $premium/day → $free/day';
  }

  @override
  String trialEndedChangePronunciation(int count) {
    return 'Pronunciation checks  Unlimited → $count/day';
  }

  @override
  String get trialEndedLater => 'Later';

  @override
  String get trialEndedSeePremium => 'See Premium';

  @override
  String trialStartedTitle(int days) {
    return 'Try Premium for $days days';
  }

  @override
  String get trialStartedBody =>
      'We\'ve unlocked features you don\'t normally have, just for this period.';

  @override
  String trialStartedChangeQuota(int free, int premium) {
    return 'Sentences  $free/day → $premium/day';
  }

  @override
  String trialStartedChangePronunciation(int count) {
    return 'Pronunciation checks  $count/day → unlimited';
  }

  @override
  String get trialStartedChangeTopic => 'Topics  Pick your own sentence topics';

  @override
  String get trialStartedStart => 'Try it out';

  @override
  String get topicPickerTitle => 'Choose a topic';

  @override
  String get nextTopicPrefix => 'Next topic: ';

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
  String get topicName_transport => 'Getting around';

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
  String get topicSub_weather =>
      'the heat, rainy season, storms, staying out of the sun';

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
  String get topicName_religion => 'Religion';

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
  String get styleName_news => 'News style';

  @override
  String get styleName_spoken => 'Casual spoken';

  @override
  String get styleName_polite => 'Polite';

  @override
  String get styleName_sns => 'Texting and social media';

  @override
  String get styleName_narrative => 'Narrative';

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
  String vocabDialogTitle(String level) {
    return 'Vocabulary score ($level)';
  }

  @override
  String vocabDialogTitleFree(String level) {
    return 'Vocabulary score (Free · $level)';
  }

  @override
  String vocabProgressOf(int current, int threshold) {
    return '$current of $threshold words';
  }

  @override
  String get vocabFreeCap => 'Free cap';

  @override
  String vocabRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to go',
      one: '1 to go',
    );
    return '$_temp0';
  }

  @override
  String vocabCurrentTopics(int count) {
    return 'Your topics ($count)';
  }

  @override
  String vocabFreeTopics(int count) {
    return 'Free topics ($count)';
  }

  @override
  String vocabNextUnlock(int count) {
    return 'Unlocks next (+$count)';
  }

  @override
  String vocabNextUnlockIn(int words, int count) {
    return '$words more words to unlock (+$count)';
  }

  @override
  String get vocabSeePremium => 'See Premium';

  @override
  String get commonClose => 'Close';

  @override
  String get vocabFreeLimitTitle => 'Free stops at 100 words';

  @override
  String get vocabFreeLimitBody =>
      'Premium takes you past 100 words and opens up more topics, so you meet a wider range of Thai.';

  @override
  String get vocabUnlockMore =>
      'As your vocabulary score grows, new sentence topics unlock.';

  @override
  String vocabTopicCountNow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count topics are in rotation right now',
      one: '1 topic is in rotation right now',
    );
    return '$_temp0';
  }

  @override
  String vocabPremiumAddsTopics(int count) {
    return 'Premium adds $count more topics';
  }

  @override
  String get listSeparator => ', ';

  @override
  String get paywallTitle => 'Premium';

  @override
  String get paywallTagline =>
      'One day, you\'ll understand them without subtitles.';

  @override
  String get paywallSignInRequired => 'Sign in first';

  @override
  String get paywallSignInForPurchase =>
      'Sign in so your purchase follows you to your next phone.';

  @override
  String get paywallSignInForRestore =>
      'To restore a purchase, sign in with the account you bought it on.';

  @override
  String get paywallActive => 'Your Premium plan is active';

  @override
  String get paywallSubscribe => 'Go Premium';

  @override
  String get paywallLegal =>
      'Your subscription renews automatically. You can cancel up to 24 hours before the period ends. Renewals are charged within 24 hours of the period ending, and you can manage or cancel from your App Store account settings.';

  @override
  String get paywallRestore => 'Restore purchases';

  @override
  String paywallPriceYen(String amount) {
    return '¥$amount / month';
  }

  @override
  String paywallPrice(String currency, String amount) {
    return '$currency $amount / month';
  }

  @override
  String get paywallFeatureQuotaTitle => 'Study more sentences a day';

  @override
  String paywallFeatureQuotaCount(int count) {
    return '$count sentences a day';
  }

  @override
  String get paywallFeature1Title => 'Learn the phrasing natives use';

  @override
  String get paywallFeature1Free => 'Textbook basics';

  @override
  String get paywallFeature1Premium => 'The phrasing Thai people actually use';

  @override
  String get paywallFeaturePronunciationTitle =>
      'Get your pronunciation scored';

  @override
  String paywallFeaturePronunciationFree(int count) {
    return '$count checks a day';
  }

  @override
  String get paywallFeaturePronunciationPremium => 'Unlimited';

  @override
  String get paywallFeatureOtherTitle => 'Also with Premium';

  @override
  String get paywallFeatureOtherTopic => 'Pick the topics you want to study';

  @override
  String paywallFeatureOtherVocab(int limit) {
    return 'No $limit-word cap — enough to follow drama dialogue';
  }

  @override
  String get paywallTrialActive =>
      'You\'re on the Premium trial. When it ends, this all goes back to Free.';

  @override
  String get paywallTrialEnded => 'This is what you had during your trial.';

  @override
  String get onboarding1Title => 'A fresh Thai sentence every day';

  @override
  String get onboarding1Body =>
      'A new sentence arrives daily.\nTap the card for words and meaning.';

  @override
  String get onboarding2Title => 'Pronunciation practice, tones included';

  @override
  String get onboarding2Body =>
      'Listen to the model audio, then record yourself.\nSee where your tones drift.';

  @override
  String get onboarding3Title => 'Grow your vocabulary score';

  @override
  String get onboarding3Body =>
      'Words you miss come back around.\nYour sentences level up with your score.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingNext => 'Next';

  @override
  String get notifCoachTitle => 'Make it a daily habit';

  @override
  String get notifCoachStep1 =>
      'Pick a time that fits your day — your commute, or just before bed';

  @override
  String get notifCoachStep2 =>
      'At that time, one sentence picked for you arrives on its own';

  @override
  String get notifCoachHabit =>
      'Opening it at the same time each day is what turns it into a habit';

  @override
  String get notifCoachPreviewLabel => 'What it looks like';

  @override
  String get notifCoachFooter =>
      'Tap the notification to jump straight in. You can change the time in Settings.';

  @override
  String get notifCoachNow => 'now';

  @override
  String get notifCoachSampleTitle => '🇹🇭 Today\'s Thai · ขอบคุณ (thank you)';

  @override
  String get notifCoachSampleBody => '→ Thank you for the coffee';

  @override
  String get notifCoachEnable => 'Turn on notifications';

  @override
  String get notifCoachLater => 'Not now';

  @override
  String get notifCoachEnabled =>
      'Your daily sentence will arrive at this time. You can change it in Settings.';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get premiumHint1Title => 'Pick the topics you want to study';

  @override
  String get premiumHint1Body =>
      'Thai dramas, romance, travel — choose what your next sentence is about';

  @override
  String get premiumHint2Title => 'Learn the phrasing natives use';

  @override
  String get premiumHint2Body =>
      'Move past textbook basics to the phrasing Thai people actually use';

  @override
  String get premiumHint3Title => 'No cap on how many words';

  @override
  String get premiumHint3Body =>
      'Go beyond the first 100 words — enough to follow drama dialogue';

  @override
  String get signInReminderTitle => 'Keep your progress safe';

  @override
  String get signInReminderMessage =>
      'Sign in and your progress is saved, so you can pick up where you left off on a new phone. Without an account, your progress is deleted after three days of not using the app.';

  @override
  String get signInReminderBanner =>
      'Protect your learning data\nWithout signing in, your progress is deleted after three days of not using the app.';

  @override
  String get commonLater => 'Later';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInSheetMessage =>
      'Save your progress and keep learning on your next phone.';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get quizOfferToQuiz => 'Go to the quiz';

  @override
  String get quizOfferOneQuestion => 'One quick question';

  @override
  String get quizOfferBody => 'See right away whether these words stuck.';

  @override
  String get quizOfferTryOne => 'Try one question';

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
  String get pronunciationTitle => 'Try saying it';

  @override
  String get pronunciationHoldToSpeak => 'Hold to speak';

  @override
  String get pronunciationRecording => 'Recording… release to check';

  @override
  String get pronunciationAnalyzing => 'Checking…';

  @override
  String get pronunciationRetry => 'Try again';

  @override
  String get pronunciationReference => 'Model';

  @override
  String get pronunciationYours => 'You';

  @override
  String get pronunciationTapWordHint => 'Tap a word to see what to fix';

  @override
  String pronunciationScore(int score) {
    return 'Score $score';
  }

  @override
  String get pronunciationVerdictCorrect => 'On target';

  @override
  String get pronunciationVerdictClose => 'Almost';

  @override
  String get pronunciationVerdictWrong => 'Off';

  @override
  String get pronunciationVerdictUnscored => 'Not measured';

  @override
  String get pronunciationTooQuiet =>
      'We couldn\'t hear you. Try again somewhere quieter.';

  @override
  String get pronunciationNoSpeakerRange =>
      'We couldn\'t read your pitch. Give it another go.';

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
  String get pronunciationBandCombined =>
      'Bar color = tone and sounds together';

  @override
  String get pronunciationSpeechRecognized => 'Consonants & vowels: understood';

  @override
  String get pronunciationSpeechMissing =>
      'Consonants & vowels: not understood';

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
      'Mid tone: hold it flat, without changing height';

  @override
  String get pronunciationCoachShapeLow =>
      'Low tone: stay down low, drifting slightly downward';

  @override
  String get pronunciationCoachShapeFalling =>
      'Falling tone: start high and fall all the way down';

  @override
  String get pronunciationCoachShapeHigh =>
      'High tone: keep rising to the end instead of levelling off';

  @override
  String get pronunciationCoachShapeRising =>
      'Rising tone: start low and rise all the way to the end';

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
    return 'In \"$word\", $label has no puff of air. With air it sounds like $aspirated.';
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
    return 'Start \"$word\" with ง humming through the nose — no vowel before it.';
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
  String pronunciationSegmentShortVowel(String word, String label) {
    return 'Keep $label in \"$word\" short — lengthening it makes a different word.';
  }

  @override
  String pronunciationSegmentVowelAe(String word) {
    return 'The vowel in \"$word\" is wider than \"e\" — spread the mouth (ɛ).';
  }

  @override
  String pronunciationSegmentVowelOe(String word) {
    return 'The vowel in \"$word\" is a relaxed, unrounded mid vowel (ə).';
  }

  @override
  String pronunciationSegmentVowelAw(String word) {
    return 'The vowel in \"$word\" is rounder and more open than \"o\" (ɔ).';
  }

  @override
  String pronunciationSegmentVowelUe(String word) {
    return 'The vowel in \"$word\" is \"u\" with the lips spread, not rounded (ɯ).';
  }

  @override
  String get pronunciationLimitTitle =>
      'You\'ve used today\'s free pronunciation checks';

  @override
  String get pronunciationLimitBody =>
      'Premium lets you check your pronunciation as often as you like.';

  @override
  String pronunciationFreeRemaining(int count) {
    return '$count free checks left today';
  }

  @override
  String tipWithExample(String content, String example) {
    return '$content\nExample: $example';
  }

  @override
  String get errQuizGenerationFailed =>
      'We couldn\'t build the quiz. Please try again.';

  @override
  String get quotaQuizReached => 'You\'ve hit today\'s quiz limit.';

  @override
  String get quotaSentenceReached =>
      'You\'ve hit today\'s sentence limit.\nPlease come back tomorrow.';

  @override
  String get errAuth =>
      'Something went wrong signing you in. Please restart the app.';

  @override
  String get errNetwork =>
      'Couldn\'t reach the network. Check your internet connection.';

  @override
  String get errTimeout => 'The request timed out. Please try again.';

  @override
  String get errServer => 'Server error. Please wait a moment and try again.';

  @override
  String get errSentenceGenerationFailed =>
      'We couldn\'t create a sentence. Please try again.';

  @override
  String get errLoadFailed => 'Couldn\'t load your data';

  @override
  String get errLoadFailedRetry =>
      'Couldn\'t load your data. Please try again.';

  @override
  String errUnexpected(String error) {
    return 'Something unexpected happened: $error';
  }

  @override
  String get errSignInRequiredForPremium => 'Sign in to use Premium';

  @override
  String get errProductLoadFailed => 'Couldn\'t load the subscription details';

  @override
  String get errPurchaseStartFailed => 'Couldn\'t start the purchase';

  @override
  String get errStoreUnavailable => 'Couldn\'t reach the App Store';

  @override
  String get errNothingToRestore => 'No purchases to restore';

  @override
  String get errRestoreFailed => 'Couldn\'t restore your purchase';

  @override
  String get errGoogleSignInFailed => 'Google sign-in failed';

  @override
  String get errAppleSignInFailed => 'Apple sign-in failed';

  @override
  String get errSignOutFailed => 'Couldn\'t sign you out';

  @override
  String get errDeleteAccountFailed => 'Couldn\'t delete your account';

  @override
  String quotaResetInHours(int hours, int minutes) {
    return 'Resets in ${hours}h ${minutes}m';
  }

  @override
  String quotaResetInMinutes(int minutes) {
    return 'Resets in ${minutes}m';
  }

  @override
  String shareTopic(String value) {
    return 'Setting: $value';
  }

  @override
  String shareStyle(String value) {
    return 'Register: $value';
  }

  @override
  String shareEmotion(String value) {
    return 'Mood: $value';
  }

  @override
  String shareUsage(String value) {
    return 'When to use it: $value';
  }

  @override
  String shareCulture(String value) {
    return 'Cultural background: $value';
  }

  @override
  String get contactSent => 'Thanks — your message is on its way.';

  @override
  String get contactFailed =>
      'We couldn\'t send that. Please try again in a little while.';

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
  String get contactBody => 'How can we help?';

  @override
  String get contactBodyRequired => 'Please tell us what you need';

  @override
  String get contactSubmit => 'Send';

  @override
  String get consonantClassHigh => 'High-class consonant';

  @override
  String get consonantClassMiddle => 'Mid-class consonant';

  @override
  String get consonantClassLow => 'Low-class consonant';

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
  String get toneDialogTitle => 'Tone breakdown';

  @override
  String get toneSyllableBreakdown => 'Syllables';

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
    return 'How tones shift for $consonantClass';
  }

  @override
  String toneShiftTableFor(String consonantClass) {
    return 'Tone chart for $consonantClass';
  }

  @override
  String get toneRareUsage => 'Exceptional — rare in modern Thai';

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
  String get toneGuideHeading => 'How Thai tones work';

  @override
  String get toneGuideIntro =>
      'Thai has five tones, and the same spelling can mean different things depending on the tone. The tone comes from three things: the class of the initial consonant, the tone mark, and the syllable type.';

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
      'For each consonant class, this shows the tone you get from every combination of tone mark and syllable type.';

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
  String get toneMidDesc => 'The pitch stays flat and level.';

  @override
  String get toneMidExample => 'กา (gaa) crow';

  @override
  String get toneLowDesc => 'Starts low and dips slightly.';

  @override
  String get toneLowExample => 'ก่า (gàa) galangal';

  @override
  String get toneFallingDesc => 'Starts high and drops.';

  @override
  String get toneFallingExample => 'ก้า (gâa) step';

  @override
  String get toneHighDesc => 'Starts high and rises further.';

  @override
  String get toneHighExample => 'ก๊า (gáa) sentence-final particle';

  @override
  String get toneRisingDesc => 'Starts low and rises.';

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
      '\"Never mind, it\'s fine.\" The phrase that captures Thai easygoingness.';

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
      'สวย (sǔuai = beautiful) versus ซวย (suuai = unlucky). One tone apart, worlds apart.';

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
  String get tip_number11and21_title => 'The odd ones: 11 and 21';

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
  String get tip_numberBig_title => 'Hundreds, thousands, and beyond';

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
  String get tip_studyThaiOnly_title => 'Try the quiz in Thai alone';

  @override
  String get tip_studyThaiOnly_content =>
      'See whether the meaning lands without the translation or notes — take the quiz and find out.';

  @override
  String get errPurchaseStatusFailed => 'Couldn\'t check your purchase status';

  @override
  String get errPurchaseGeneric => 'Something went wrong with the purchase';

  @override
  String get purchasePending =>
      'Your purchase is awaiting approval. It\'ll apply once approved.';

  @override
  String get errSignInBeforePurchase => 'Sign in before buying';

  @override
  String get errPurchaseVerificationFailed => 'Couldn\'t verify your purchase';

  @override
  String get rankingTitle => 'Vocabulary ranking';

  @override
  String get rankingSubtitle => 'See how your vocabulary score compares';

  @override
  String get rankingYourRank => 'Your rank';

  @override
  String rankingPosition(int rank) {
    return '#$rank';
  }

  @override
  String get rankingUnrankedHint => 'Generate a sentence to get ranked';

  @override
  String get rankingLoadFailed => 'Couldn\'t load the ranking';

  @override
  String get rankingYou => 'You';

  @override
  String get rankingDistributionTitle => 'Score distribution';

  @override
  String get rankingDistributionSubtitle =>
      'Learners in each band; yours is highlighted';

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
    return 'Learner $suffix';
  }

  @override
  String rankingFreeCapNote(int limit) {
    return 'On the free plan your vocabulary score is capped at $limit words';
  }

  @override
  String get settingsRanking => 'Ranking';

  @override
  String get settingsRankingSubtitle =>
      'See how your vocabulary score compares';
}
