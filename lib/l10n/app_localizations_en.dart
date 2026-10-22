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
  String get settingsFontPickerTitle => 'Select font';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguagePickerTitle => 'Select language';

  @override
  String get settingsLanguageSubtitle => 'Translation and explanation language';

  @override
  String get settingsLanguageNote =>
      'Changes translations and explanations. Existing sentence translations keep their original language.';

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
  String get learnGoToSummaryQuiz => 'Start summary quiz';

  @override
  String learnDailySetRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sentences to summary quiz',
      one: '1 sentence to summary quiz',
    );
    return '$_temp0';
  }

  @override
  String get learnDailySetLast => 'Summary quiz up next';

  @override
  String learnDailySetProgress(int position, int total) {
    return '$position / $total';
  }

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Retry';

  @override
  String get sentencePreparing => 'Loading sentences...';

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
  String get playPronunciation => 'Play audio';

  @override
  String get sentenceListenModel => 'Listen';

  @override
  String get sentencePractice => 'Practice';

  @override
  String get sentenceUsingWord => 'Example with this word';

  @override
  String get badgePremiumSentence => 'Premium';

  @override
  String get badgeFreeSentence => 'Free';

  @override
  String get sampleSentenceNotice => 'Sample (not saved to History)';

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
      'A basic greeting for any time of day; women use ค่ะ instead.';

  @override
  String get quizTodayTitle => 'Quiz';

  @override
  String get quizGenerating => 'Creating quiz...';

  @override
  String get quizOpenSentenceFirst => 'Open a sentence first';

  @override
  String get quizFromLearningSentence => 'Based on your current sentence';

  @override
  String get quizBackToSentence => 'Back to sentence';

  @override
  String get quizCorrect => 'Correct!';

  @override
  String get quizIncorrect => 'Incorrect';

  @override
  String quizCorrectAnswer(String answer) {
    return 'Correct answer: $answer';
  }

  @override
  String get quizPrompt => 'Choose the missing word';

  @override
  String get quizMeaningPrompt => 'Choose this word\'s meaning';

  @override
  String get quizSpellingPrompt => 'Choose the matching spelling';

  @override
  String get quizWordOrderPrompt => 'Put the words in order';

  @override
  String get quizWordOrderCheck => 'Check';

  @override
  String quizWordOrderYourAnswer(String order) {
    return 'Your order: $order';
  }

  @override
  String get quizWordExplanation => 'Explanation';

  @override
  String quizProgress(int index, int total) {
    return '$index of $total';
  }

  @override
  String get quizSentenceReviewed => 'Sentence reviewed';

  @override
  String get quizReviewSentence => 'Review sentence';

  @override
  String get quizOpenSentenceDetail => 'View details';

  @override
  String get quizHint => 'Hint';

  @override
  String get quizHintPronunciation => 'Hint 1: pronunciation';

  @override
  String get quizHintTranslation => 'Hint 2: translation';

  @override
  String get quizHintShown => 'Hints shown';

  @override
  String get quizCheckSentence => 'Check sentence';

  @override
  String get quizPlaySentence => 'Play sentence';

  @override
  String get quizPlayWord => 'Play word';

  @override
  String get quizWhyCorrect => 'Why it\'s right';

  @override
  String get quizSpellingBreakdown => 'Spelling breakdown';

  @override
  String quizToneRuleFor(String consonantClass) {
    return 'Tone rules for $consonantClass';
  }

  @override
  String get quizPartOnset => 'Initial';

  @override
  String get quizPartVowel => 'Vowel';

  @override
  String get quizPartCoda => 'Final';

  @override
  String get quizPartVowelCoda => 'Vowel + final';

  @override
  String get quizPartToneLabel => 'Tone';

  @override
  String get quizPartKaran => 'Karan';

  @override
  String get quizPartSilent => 'Silent';

  @override
  String get quizPartSilentValue => 'Not read';

  @override
  String get quizPartNone => 'None';

  @override
  String get quizWhyIncorrect => 'Why it\'s wrong';

  @override
  String get quizSeeResults => 'See results';

  @override
  String get quizNextQuestion => 'Next question';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get vocabScore => 'Vocabulary score';

  @override
  String get vocabScoreCalculating => 'Calculating score...';

  @override
  String get vocabScoreUp => 'Vocabulary score up!';

  @override
  String get vocabScoreCapped => 'Vocabulary score limit reached';

  @override
  String get vocabScorePremiumPitch => 'Go Premium to keep tracking progress';

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
  String get historyFavoritesOnly => 'Favorites only';

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
  String get historyEmptyFavorites => 'No favorites yet';

  @override
  String get historyEmptySearch => 'No results found';

  @override
  String get historyEmpty => 'No sentences yet';

  @override
  String get historyEmptyFavoritesHint =>
      'Tap a sentence\'s heart to add it here';

  @override
  String get historyEmptySearchHint => 'Try another keyword';

  @override
  String get historyEmptyHint => 'Create a new sentence';

  @override
  String get historyDeleteAllConfirm =>
      'Delete all sentence history? This can\'t be undone.';

  @override
  String get historyDeletedAll => 'History deleted';

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
  String get detailTitle => 'Details';

  @override
  String get detailShare => 'Share';

  @override
  String detailWordBreakdown(int count) {
    return 'Words ($count)';
  }

  @override
  String get detailQuizTarget => '→ Quiz word';

  @override
  String get detailTapForTone => 'Tap for tone';

  @override
  String get detailUsageSection => 'How to use';

  @override
  String get detailWordsSection => 'Words';

  @override
  String get detailFavoriteAdd => 'Favorite';

  @override
  String get detailFavoriteRemove => 'Unfavorite';

  @override
  String get detailContextSection => 'Context';

  @override
  String get detailContextTopic => 'Situation';

  @override
  String get detailContextStyle => 'Style';

  @override
  String get detailContextEmotion => 'Emotion / tone';

  @override
  String get detailContextUsage => 'Usage';

  @override
  String get detailContextCulture => 'Culture';

  @override
  String detailCreatedAt(String date) {
    return 'Created: $date';
  }

  @override
  String get detailCopied => 'Copied';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsUser => 'User';

  @override
  String get settingsGuest => 'Guest';

  @override
  String get settingsRankingName => 'Ranking name';

  @override
  String get settingsNotSignedIn => 'Not signed in';

  @override
  String get settingsPlan => 'Plan';

  @override
  String get settingsPlanTrial => 'Free trial';

  @override
  String get settingsPlanTrialNoCharge => 'No auto-charge';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignInToSave => 'Sign in to save';

  @override
  String get settingsSignOutConfirm => 'Sign out?';

  @override
  String get settingsDeleteAccountTitle => 'Delete account';

  @override
  String get settingsDeleteAccountConfirm =>
      'Deleting your account permanently erases all of your learning data, both on our servers and on this device. This can\'t be undone.';

  @override
  String get settingsAccountDeleted => 'Account and data deleted';

  @override
  String get settingsFontSample => 'Sample';

  @override
  String get settingsLearningStatus => 'Progress';

  @override
  String get settingsGuideSection => 'Guide';

  @override
  String get settingsLearningSection => 'Learning';

  @override
  String get settingsToneGuide => 'Tone guide';

  @override
  String get settingsToneGuideSubtitle => 'How Thai tones work';

  @override
  String get settingsPronGuide => 'Pronunciation guide';

  @override
  String get settingsPronGuideSubtitle => 'Reading symbols and tricky sounds';

  @override
  String get settingsResetLearningData => 'Reset learning data';

  @override
  String get settingsResetLearningDataSubtitle =>
      'Clear on-device sentences and quiz history';

  @override
  String get settingsResetTitle => 'Reset learning data';

  @override
  String get settingsResetConfirm =>
      'This deletes all sentences, quiz results, and progress stored on this device. Your account will remain active.';

  @override
  String get settingsResetDone => 'Learning data reset';

  @override
  String get settingsResetFailed => 'Reset failed';

  @override
  String get commonReset => 'Reset';

  @override
  String get settingsDailyNotification => 'Daily sentence';

  @override
  String get settingsDailyNotificationSubtitle => 'Get a daily reminder';

  @override
  String get settingsAllowNotificationInOsSettings =>
      'Enable notifications in device settings';

  @override
  String get settingsNotificationTime => 'Notification time';

  @override
  String get notifyScheduleOff => 'Off';

  @override
  String notifySchedulePremiumUpsell(int count) {
    return 'With Premium, set up to $count notifications a day';
  }

  @override
  String get notifyScheduleReplaceNote =>
      'Each notification brings a new sentence set. If you don\'t read any sentence in a set before the next notification, it is replaced with a new one.';

  @override
  String get notifyScheduleChangeTime => 'Change time';

  @override
  String get notifyScheduleTimeTaken => 'That time is already set';

  @override
  String get notifyScheduleSave => 'Save';

  @override
  String get settingsTopic => 'Topic';

  @override
  String get settingsTopicRandom => 'Chosen for you';

  @override
  String settingsNextLevelIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Next level in $count words',
      one: 'Next level in 1 word',
    );
    return '$_temp0';
  }

  @override
  String settingsFreeVocabLimit(int limit) {
    return 'Free plan limit: $limit words';
  }

  @override
  String get settingsCouldNotOpenUrl => 'Couldn\'t open link';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsTagline => 'Immerse yourself in Thai';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of service';

  @override
  String get settingsContact => 'Feedback & contact';

  @override
  String get settingsLifetimeMigration => 'Switch to lifetime';

  @override
  String get settingsLifetimeMigrationSubtitle => 'No additional payment';

  @override
  String get lifetimeMigrationTitle => 'Lifetime plan';

  @override
  String get lifetimeMigrationBody =>
      'Thanks for being a loyal subscriber. For a limited time, you can switch to the lifetime plan at no extra cost.';

  @override
  String get lifetimeMigrationNoCharge => 'No additional payment';

  @override
  String lifetimeMigrationCancelNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'After switching, turn off monthly auto-renewal in your Google Play subscriptions. Otherwise, monthly billing will continue.',
        'other':
            'After switching, turn off monthly auto-renewal in your App Store account settings. Otherwise, monthly billing will continue.',
      },
    );
    return '$_temp0';
  }

  @override
  String get lifetimeMigrationProgress => 'Switching plans…';

  @override
  String get lifetimeMigrationDoneTitle => 'Switched to lifetime';

  @override
  String get lifetimeMigrationDoneBody =>
      'You now have Premium for life. Remember to turn off monthly auto-renewal.';

  @override
  String get lifetimeMigrationFailedTitle => 'Switch failed';

  @override
  String get lifetimeMigrationFailedBody =>
      'Please try again later. Your current Premium access remains active.';

  @override
  String get lifetimeMigrationConfirm => 'Switch to lifetime';

  @override
  String get lifetimeMigrationLater => 'Later';

  @override
  String get trialEndedTitle => 'Premium trial ended';

  @override
  String get trialEndedBody => 'You\'re on the free plan.';

  @override
  String get trialEndedKeepPremium => 'View Premium';

  @override
  String get trialEndedKeepFree => 'Later';

  @override
  String get trialEndedChangeQuotaLabel => 'Sentences';

  @override
  String get trialEndedChangeQuotaPremium => 'Unlimited';

  @override
  String trialEndedChangeQuotaFree(int free) {
    return '$free sets per day';
  }

  @override
  String get trialEndedChangeVocabLabel => 'Vocabulary score';

  @override
  String get trialEndedChangeVocabPremium => 'No cap';

  @override
  String trialEndedChangeVocabFree(int free) {
    return 'Up to $free words';
  }

  @override
  String trialStartedTitle(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days of Premium unlocked',
      one: '1 day of Premium unlocked',
    );
    return '$_temp0';
  }

  @override
  String get trialStartedBody =>
      'Enjoy all Premium features during your trial.';

  @override
  String get trialStartedChangeQuotaLabel => 'Sentences';

  @override
  String get trialStartedChangeQuota => 'Unlimited';

  @override
  String get trialStartedChangeTopicLabel => 'Topic selection';

  @override
  String get trialStartedChangeTopic => 'Choose sentence topics';

  @override
  String get trialStartedStart => 'Got it';

  @override
  String get topicPickerTitle => 'Select topic';

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
      'collab cafes, ordering, reactions, street stalls, spice levels, allergies';

  @override
  String get topicName_travel => 'Travel';

  @override
  String get topicSub_travel =>
      'filming locations, hotels, directions, sights, airports, tours';

  @override
  String get topicName_family => 'Family';

  @override
  String get topicSub_family =>
      'introductions, raising kids, thanking parents, siblings, family events';

  @override
  String get topicName_shopping => 'Shopping';

  @override
  String get topicSub_shopping =>
      'fan merch, haggling, sizes and colors, returns, night markets';

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
      'fandom, Muay Thai, music, movies, golf, social media, games';

  @override
  String get topicName_school => 'School';

  @override
  String get topicSub_school =>
      'in class, homework, exams, after school, language school';

  @override
  String get topicName_religion => 'Religion and faith';

  @override
  String get topicSub_religion =>
      'merit-making for idols\' birthdays, temple etiquette, almsgiving, amulets, speaking to monks, Buddhist holidays';

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
  String get topicName_life => 'Living in Thailand';

  @override
  String get topicSub_life =>
      'shopping, transport, health, family, weather, food';

  @override
  String get topicName_thaiTravel => 'Traveling in Thailand';

  @override
  String get topicSub_thaiTravel =>
      'sightseeing, hotels, transport, shopping, food';

  @override
  String get styleName_news => 'News';

  @override
  String get styleName_spoken => 'Colloquial';

  @override
  String get styleName_polite => 'Polite';

  @override
  String get styleName_sns => 'Texts and social media';

  @override
  String get styleName_narrative => 'Narrative and literary';

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
  String get paywallSignInRequired => 'Sign-in required';

  @override
  String get paywallSignInForPurchase =>
      'Sign in to keep your purchase when you change devices.';

  @override
  String get paywallSignInForRestore =>
      'Sign in with the account used for the purchase.';

  @override
  String get paywallActive => 'You\'re subscribed to the Premium plan';

  @override
  String get paywallSubscribe => 'Get Premium';

  @override
  String get paywallPlanMonthlyTitle => 'Monthly';

  @override
  String get paywallPlanMonthlyNote => 'Renews monthly. Cancel anytime.';

  @override
  String paywallPlanMonthlyPrice(String price) {
    return '$price / month';
  }

  @override
  String get paywallPlanYearlyTitle => 'Yearly';

  @override
  String get paywallPlanYearlyNote => 'Renews yearly. Cancel anytime.';

  @override
  String paywallPlanYearlyPrice(String price) {
    return '$price / year';
  }

  @override
  String paywallPlanYearlySave(int percent) {
    return 'Save $percent%';
  }

  @override
  String get paywallPlanLifetimeTitle => 'Lifetime';

  @override
  String get paywallPlanLifetimeNote => 'One payment. No renewal.';

  @override
  String get paywallPurchaseCta => 'Choose this plan';

  @override
  String get paywallChangeToLifetimeCta => 'Switch to lifetime';

  @override
  String get paywallLifetimeNote => 'A one-time payment. No renewals.';

  @override
  String paywallMonthlyToLifetimeNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'Buying the lifetime plan does not automatically cancel your current subscription. Cancel it separately in your Google Play subscriptions.',
        'other':
            'Buying the lifetime plan does not automatically cancel your current subscription. Cancel it separately in your App Store account settings.',
      },
    );
    return '$_temp0';
  }

  @override
  String paywallLegal(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'Your subscription renews automatically at the same price unless you cancel before the next renewal date. You can manage or cancel it in your Google Play subscriptions.',
        'other':
            'Your subscription renews automatically. You can cancel up to 24 hours before the period ends. Renewals are charged within 24 hours of the period ending, and you can manage or cancel from your App Store account settings.',
      },
    );
    return '$_temp0';
  }

  @override
  String get paywallTrialBadge => 'First-time offer';

  @override
  String paywallTrialHeadline(int days) {
    return '$days-day free Premium trial';
  }

  @override
  String paywallTrialCta(int days) {
    return 'Start $days-day free trial';
  }

  @override
  String paywallTrialTermsMonthly(int days, String price) {
    return 'Free for $days days, then $price per month, renewing automatically. Cancel at least 24 hours before the trial ends to avoid being charged.';
  }

  @override
  String paywallTrialTermsYearly(int days, String price) {
    return 'Free for $days days, then $price per year, renewing automatically. Cancel at least 24 hours before the trial ends to avoid being charged.';
  }

  @override
  String get paywallPlanCurrent => 'Current plan';

  @override
  String get paywallChangeToYearlyCta => 'Switch to yearly';

  @override
  String get paywallChangeToMonthlyCta => 'Switch to monthly';

  @override
  String paywallChangeToYearlyNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'You\'ll switch to the yearly plan right away and be charged the yearly price. The unused part of your monthly plan is added to your yearly plan.',
        'other':
            'You\'ll switch to the yearly plan right away. Apple refunds the unused part of your monthly plan.',
      },
    );
    return '$_temp0';
  }

  @override
  String paywallChangeToMonthlyNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'You\'ll switch to the monthly plan right away. You won\'t be charged until your paid yearly period ends, then it renews monthly.',
        'other':
            'You\'ll switch to the monthly plan when your current yearly plan ends. Until then, you keep the yearly plan.',
      },
    );
    return '$_temp0';
  }

  @override
  String get paywallCancelSubscriptionNote =>
      'You own the lifetime plan, but your subscription is still set to renew. Cancel it to stop being charged.';

  @override
  String get paywallManageSubscriptions => 'Cancel subscription';

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
  String get paywallFeatureQuotaTitle => 'Grow past a vocab score of 100';

  @override
  String get paywallFeatureQuotaPremium =>
      'Unlimited sentences · no vocab score cap';

  @override
  String get paywallFeatureTopicTitle => 'Start with scenes you care about';

  @override
  String get paywallFeatureTopicPremium =>
      'Choose from travel, life in Thailand, BL dramas and more';

  @override
  String get onboarding1Title => 'Can\'t read Thai yet? No problem';

  @override
  String get onboarding1Body =>
      'Sentences matched to your level, every day.\nTap a card to see how to read it and what it means.';

  @override
  String get onboarding2Title => 'Practice sounds and tones';

  @override
  String get onboarding2Body =>
      'Listen, then record yourself.\nSee which tones need work.';

  @override
  String get onboarding3Title => 'Build vocabulary with quizzes';

  @override
  String get onboarding3Body =>
      'Missed words come back.\nSentences use more words as your score grows.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingHaveAccount => 'Have an account? Sign in';

  @override
  String get interviewIntroTitle => 'Four quick questions';

  @override
  String get interviewIntroBody =>
      'Answer four questions for personalized learning tips.';

  @override
  String get interviewIntroStart => 'Start';

  @override
  String interviewStepLabel(int current, int total) {
    return '$current / $total';
  }

  @override
  String get interviewLevelQuestion => 'How much Thai do you know?';

  @override
  String get interviewLevelNone => 'I\'m new to Thai';

  @override
  String get interviewLevelChars => 'I can read a few letters';

  @override
  String get interviewLevelWords => 'I know words and greetings';

  @override
  String get interviewLevelConv => 'I can have everyday conversations';

  @override
  String get interviewGoalQuestion => 'Where do you want to use Thai?';

  @override
  String get interviewGoalTravel => 'For travel';

  @override
  String get interviewGoalWork => 'At work';

  @override
  String get interviewGoalLive => 'Living in Thailand';

  @override
  String get interviewGoalCulture => 'For dramas and music';

  @override
  String get interviewTimeQuestion => 'How long can you study daily?';

  @override
  String get interviewTimeShort => 'Just a few minutes';

  @override
  String get interviewTimeMedium => 'About 10 minutes';

  @override
  String get interviewTimeLong => '30 minutes or more';

  @override
  String get interviewStruggleQuestion => 'What\'s hard about Thai?';

  @override
  String get interviewStruggleNone => 'I just started';

  @override
  String get interviewStruggleScript => 'I can\'t read the letters';

  @override
  String get interviewStruggleTone => 'Tones are hard';

  @override
  String get interviewStruggleVocab => 'I forget words';

  @override
  String get philosophyHeading => 'How it works';

  @override
  String get philosophy1None =>
      'Start with each sentence\'s **sound and meaning**, then learn **Thai script** by recognizing its shapes.';

  @override
  String get philosophy1Chars =>
      'Each sentence is **broken down word by word** with meanings and pronunciation, helping you read more on your own.';

  @override
  String get philosophy1Words =>
      'Sentences match your **vocabulary score**, from basic greetings to everyday expressions.';

  @override
  String get philosophy1Conv =>
      'Your **quiz results** set sentence difficulty; more correct answers bring more words.';

  @override
  String get philosophyKeyWord =>
      'Each sentence shows **one target word** in context.';

  @override
  String get philosophy2None =>
      'No need to read Thai yet; you\'ll learn **how spelling affects tone**. If readings are unclear, try the pronunciation guide in Settings.';

  @override
  String get philosophy2Script =>
      'In Thai, **spelling determines tone**; see the rules for each word. The pronunciation guide in Settings explains the app\'s readings and tricky sounds.';

  @override
  String get philosophy2Tone =>
      'Use **pronunciation practice** to compare your tones with the model. You can check the tone rules in the tone guide in Settings.';

  @override
  String get philosophy2Vocab =>
      '**Quizzes** track each word; words you haven\'t mastered return later.';

  @override
  String get philosophy3Travel =>
      '**With Premium**, choose “Traveling in Thailand” for sentences you can use on your trip — sightseeing, getting around, shopping and more.';

  @override
  String get philosophy3Work =>
      '**With Premium**, choose “Work” for workplace sentences.';

  @override
  String get philosophy3Live =>
      '**With Premium**, choose “Living in Thailand” for sentences you can use in daily life — shopping, transport, family and more.';

  @override
  String get philosophy3Culture =>
      '**With Premium**, choose “Thai BL dramas” to learn expressions from the shows.';

  @override
  String get philosophy3TimeShort =>
      '**In a few minutes**, read a sentence and take its quiz.';

  @override
  String get philosophy3TimeMedium =>
      '**In ten minutes**, add sentences, practice pronunciation, and review words.';

  @override
  String get philosophy3TimeLong =>
      '**In thirty minutes**, also review past sentences and tone rules.';

  @override
  String get philosophyStart => 'See how it works';

  @override
  String get notifCoachTitle => 'Make Thai practice a daily habit';

  @override
  String get notifCoachHabit =>
      'Get new example sentences at your chosen time to help you keep learning';

  @override
  String get notifCoachNow => 'now';

  @override
  String get notifCoachSampleTitle => '🇹🇭 ขอบคุณ (thank you)';

  @override
  String get notifCoachSampleBody => '→ Thank you for the coffee';

  @override
  String get notifCoachEnable => 'Enable notifications';

  @override
  String get notifCoachLater => 'Not now';

  @override
  String get notifCoachEnabled =>
      'Your sentence will arrive daily at the time set in Settings.';

  @override
  String get notifCoachStillQuiet =>
      'Notifications will arrive quietly in Notification Center.';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get premiumHint1Title => 'Start with scenes you care about';

  @override
  String get premiumHint1Body =>
      'Choose sentence topics like travel, life in Thailand, BL dramas and more';

  @override
  String get signInReminderTitle => 'Protect your progress';

  @override
  String get signInReminderMessage =>
      'Sign in to save progress across devices; without an account, it\'s deleted after three inactive days.';

  @override
  String get signInReminderBanner =>
      'Protect your progress\nWithout an account, it\'s deleted after three inactive days.';

  @override
  String get commonLater => 'Later';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInSheetMessage => 'Save progress across devices.';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get quizOfferToQuiz => 'Start quiz';

  @override
  String get quizOfferOneQuestion => 'Quick check';

  @override
  String get quizOfferBody => 'Quiz yourself on the target word.';

  @override
  String get quizOfferTryOne => 'Check';

  @override
  String get audioRepeat => 'Repeat';

  @override
  String get audioOnce => 'Once';

  @override
  String get audioSpeed => 'Playback speed';

  @override
  String get audioPause => 'Pause';

  @override
  String get audioPlay => 'Play';

  @override
  String audioModeHint(String mode) {
    return '$mode. Hold to change playback mode';
  }

  @override
  String get audioModeRepeat => 'on repeat';

  @override
  String get audioModeOnce => 'playing once';

  @override
  String get audioPosition => 'Playback position';

  @override
  String get pronunciationTitle => 'Say it aloud';

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
  String pronunciationScore(int score) {
    return 'Score $score';
  }

  @override
  String get pronunciationVerdictCorrect => 'Correct';

  @override
  String get pronunciationVerdictClose => 'Close';

  @override
  String get pronunciationVerdictWrong => 'Incorrect';

  @override
  String get pronunciationVerdictUnscored => 'Couldn\'t check';

  @override
  String get pronunciationTooQuiet =>
      'Couldn\'t hear you. Try somewhere quieter.';

  @override
  String get pronunciationNoSpeakerRange =>
      'Couldn\'t detect your pitch. Try again.';

  @override
  String get pronunciationNoSyllables =>
      'Pronunciation practice unavailable for this sentence.';

  @override
  String get pronunciationMonotone =>
      'Your pitch barely moved. Listen to the model, then say it again with the rises and falls.';

  @override
  String get pronunciationCaptureFailed =>
      'No microphone audio detected. Try again.';

  @override
  String get pronunciationPermissionTitle => 'Microphone access needed';

  @override
  String get pronunciationPermissionBody =>
      'We use the microphone to check your pronunciation. Your audio is processed entirely on this device and is never uploaded.';

  @override
  String get pronunciationPermissionOpenSettings => 'Open Settings';

  @override
  String get ttsThaiVoiceMissing =>
      'Your text-to-speech engine has no Thai voice. Download the voice data to hear the examples.';

  @override
  String get ttsThaiVoiceInstall => 'Download';

  @override
  String get pronunciationSpeechRecognized =>
      'Consonants and vowels: recognized';

  @override
  String get pronunciationSpeechMissing =>
      'Consonants and vowels: not recognized';

  @override
  String get pronunciationSpeechUnavailable =>
      'Can\'t check consonants or vowels now — tones only';

  @override
  String get pronunciationSpeechNoAsset =>
      'Thai dictation isn\'t installed — showing tones only';

  @override
  String pronunciationSpeechNoAssetHow(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            'Add Thai to on-device speech recognition in your device settings to enable it.',
        'other':
            'Add the Thai keyboard under Settings → General → Keyboard, then turn on Enable Dictation.',
      },
    );
    return '$_temp0';
  }

  @override
  String get pronunciationSpeechAuthDenied =>
      'Speech recognition isn\'t allowed — showing tones only';

  @override
  String get pronunciationSpeechAndroid =>
      'Consonant and vowel checks need Android 13+ — tones only';

  @override
  String get pronunciationCoachLead => 'Fix this next';

  @override
  String get pronunciationCoachShapeMid => 'Mid tone: keep it flat throughout';

  @override
  String get pronunciationCoachShapeLow =>
      'Low tone: stay low and drift down slightly';

  @override
  String get pronunciationCoachShapeFalling =>
      'Falling tone: start high and fall fully';

  @override
  String get pronunciationCoachShapeHigh => 'High tone: keep rising to the end';

  @override
  String get pronunciationCoachShapeRising =>
      'Rising tone: dip, then rise fully';

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
    return 'Couldn\'t recognize \"$word\". Say it more clearly.';
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
    return 'Start \"$word\" with ง through the nose — don\'t add an \"n\" before it.';
  }

  @override
  String pronunciationSegmentFinalNg(String word) {
    return 'End \"$word\" through the nose with your mouth open (-ng), not with closed lips.';
  }

  @override
  String pronunciationSegmentFinalN(String word) {
    return 'End \"$word\" with your tongue tip behind your teeth (-n), so it doesn\'t become -ng.';
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
      other: '$total words recognized',
      one: '1 word recognized',
    );
    return '$ok of $_temp0';
  }

  @override
  String pronunciationNextFocus(String word) {
    return 'Fix \"$word\" next';
  }

  @override
  String get pronunciationTierPass => 'Passed';

  @override
  String get pronunciationTierNative => 'Native level';

  @override
  String pronunciationToPass(int points) {
    return '$points more to pass';
  }

  @override
  String pronunciationToNative(int points) {
    return '$points more to native level';
  }

  @override
  String pronunciationNativeFirst(int score) {
    return 'First time scoring $score+ on this sentence';
  }

  @override
  String get pronunciationNativeAgain => 'Already reached on this sentence';

  @override
  String get pronunciationCountCorrect => 'OK';

  @override
  String get pronunciationCountClose => 'Close';

  @override
  String get pronunciationCountWrong => 'Fix';

  @override
  String get pronunciationTapWordHintDetail =>
      'Tap a word to compare with the model';

  @override
  String get pronunciationListenModelWord => 'Listen to the model';

  @override
  String tipWithExample(String content, String example) {
    return '$content\nExample: $example';
  }

  @override
  String get errQuizGenerationFailed => 'Couldn\'t create quiz. Try again.';

  @override
  String get quotaQuizReached => 'No more new quizzes today.';

  @override
  String get quotaSentenceReached =>
      'No more new sentences today.\nYou can still review past ones in History.';

  @override
  String get quotaSentenceUpgradeCta => 'Unlock unlimited sentences';

  @override
  String get errAuth => 'Authentication failed. Restart the app.';

  @override
  String get errNetwork => 'Couldn\'t connect. Check your internet.';

  @override
  String get errTimeout => 'Request timed out. Try again.';

  @override
  String get errServer => 'Server unavailable. Try again later.';

  @override
  String get errSentenceGenerationFailed =>
      'Couldn\'t create sentence. Try again.';

  @override
  String get errLoadFailed => 'Couldn\'t load data';

  @override
  String get errLoadFailedRetry => 'Couldn\'t load data. Try again.';

  @override
  String errUnexpected(String error) {
    return 'Unexpected error: $error';
  }

  @override
  String get errSignInRequiredForPremium => 'Sign in to use Premium';

  @override
  String get errProductLoadFailed => 'Couldn\'t load purchase options';

  @override
  String get errPurchaseStartFailed => 'Couldn\'t start the purchase';

  @override
  String errStoreUnavailable(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android': 'Couldn\'t reach Google Play',
        'other': 'Couldn\'t reach the App Store',
      },
    );
    return '$_temp0';
  }

  @override
  String get errNothingToRestore => 'No purchases to restore';

  @override
  String get errRestoreFailed => 'Couldn\'t restore purchases';

  @override
  String get errGoogleSignInFailed => 'Couldn\'t sign in with Google';

  @override
  String get errAppleSignInFailed => 'Couldn\'t sign in with Apple';

  @override
  String get errSignOutFailed => 'Couldn\'t sign out';

  @override
  String get errDeleteAccountFailed => 'Couldn\'t delete the account';

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
    return 'Usage: $value';
  }

  @override
  String shareCulture(String value) {
    return 'Culture: $value';
  }

  @override
  String get contactSent => 'Message sent. Thanks!';

  @override
  String get contactFailed => 'Couldn\'t send message. Try again later.';

  @override
  String get contactName => 'Your name (optional)';

  @override
  String get contactEmail => 'Email (optional)';

  @override
  String get contactEmailInvalid => 'Enter a valid email';

  @override
  String get contactBody => 'Your message';

  @override
  String get contactBodyRequired => 'Enter a message';

  @override
  String get contactSubmit => 'Send';

  @override
  String get contactAnonymousHint =>
      'Leave email blank to send anonymously. We won\'t be able to reply.';

  @override
  String get contactSurveyTitle => 'Take a 1-minute survey';

  @override
  String get contactSurveySubtitle => 'Help us improve the app';

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
  String get syllableDeadShort => 'Dead (short vowel)';

  @override
  String get syllableDeadLong => 'Dead (long/compound vowel)';

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
  String get toneDialogTitle => 'Tone details';

  @override
  String get toneSyllableBreakdown => 'Syllables';

  @override
  String toneSyllableNumber(int number) {
    return 'Syllable $number';
  }

  @override
  String get toneMainConsonant => 'Initial';

  @override
  String get toneSyllableType => 'Syllable type';

  @override
  String get toneResultPrefix => 'Result: ';

  @override
  String get toneMarkLabel => 'Tone mark';

  @override
  String get toneMarkPrefix => 'Tone mark: ';

  @override
  String get toneResultTone => 'Result';

  @override
  String toneShiftFor(String consonantClass) {
    return 'Tone shifts for $consonantClass';
  }

  @override
  String toneShiftTableFor(String consonantClass) {
    return 'Tone chart for $consonantClass';
  }

  @override
  String get toneRareUsage => 'Exception (rare in modern Thai)';

  @override
  String get toneAppliedRule => '= rule used for this word';

  @override
  String get toneLearnMore => 'More about tones';

  @override
  String toneExamplePrefix(String value) {
    return 'Example: $value';
  }

  @override
  String get toneGuideOfferTitle => 'You said tones are hard';

  @override
  String get toneGuideOfferBody =>
      'See all five tones and the rules behind them';

  @override
  String get vocabRetestOfferTitle => 'Welcome back';

  @override
  String get vocabRetestOfferBody =>
      'Retake the vocabulary test to match sentences to your current level.';

  @override
  String get toneGuideTitle => 'Thai tone guide';

  @override
  String get toneGuideHeading => 'Thai tones';

  @override
  String get toneGuideIntro =>
      'Thai has five meaning-changing tones, determined by consonant class, tone mark, and syllable type.';

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
      'See how class, tone mark, and syllable type set the tone.';

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
  String get toneMidDesc => 'Flat, steady pitch.';

  @override
  String get toneMidExample => 'กา (gaa) crow';

  @override
  String get toneLowDesc => 'Starts low and falls slightly.';

  @override
  String get toneLowExample => 'ก่า (gàa) galangal';

  @override
  String get toneFallingDesc => 'Drops from high to low.';

  @override
  String get toneFallingExample => 'ก้า (gâa) step';

  @override
  String get toneHighDesc => 'Starts high and rises.';

  @override
  String get toneHighExample => 'ก๊า (gáa) sentence-final particle';

  @override
  String get toneRisingDesc => 'Rises from low to high.';

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
      'Eat with the spoon and use the fork to push food onto it. Chopsticks are mainly for noodles.';

  @override
  String get tip_cultureMaiPenRai_title => 'ไม่เป็นไร (mâi pen rai)';

  @override
  String get tip_cultureMaiPenRai_content =>
      'Means “don\'t worry” or “it\'s fine.” It\'s one of the most common Thai expressions.';

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
      'The 9 letters ก จ ฎ ฏ ด ต บ ป อ. Tone marks follow their basic pattern in this group.';

  @override
  String get tip_consonantLow_title => 'Low class (àksɔ̌ɔn tàm)';

  @override
  String get tip_consonantLow_content =>
      'The remaining 24 letters. Some pair with high-class letters; others stand alone.';

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
      'Thai uses a number plus a classifier, similar to “two sheets of paper” in English.';

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
      'Men add khráp and women add khâ to the end of sentences to sound polite.';

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
      'Means \"sorry\" or \"excuse me.\" Use it to apologize or get someone\'s attention.';

  @override
  String get tip_dailyYesNo_title => 'ใช่ / ไม่ใช่ (châi / mâi châi)';

  @override
  String get tip_dailyYesNo_content =>
      'Means \"yes\" and \"no\" when confirming whether something is correct.';

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
  String get tip_studyThaiOnly_title => 'Take the quiz using only Thai';

  @override
  String get tip_studyThaiOnly_content =>
      'Try answering from the Thai alone, without checking the sentence or notes.';

  @override
  String get errPurchaseStatusFailed => 'Couldn\'t check your purchase status';

  @override
  String get errPurchaseGeneric => 'Something went wrong with the purchase';

  @override
  String get purchasePending =>
      'Your purchase is awaiting approval. It will take effect once approved.';

  @override
  String get errSignInBeforePurchase => 'Please sign in before purchasing';

  @override
  String get errPurchaseVerificationFailed => 'Purchase verification failed';

  @override
  String get settingsVocabTest => 'Vocabulary test';

  @override
  String get settingsVocabTestNever => 'Not taken yet';

  @override
  String settingsVocabTestLast(String date) {
    return 'Last taken: $date';
  }

  @override
  String get settingsVocabTestPremium => 'Premium only';

  @override
  String get vocabTestTitle => 'Vocabulary test';

  @override
  String get vocabTestIntroBody =>
      'Choose each Thai word\'s meaning from four options. The test ends after several misses in a row, starting at six questions and continuing if you know more.';

  @override
  String get vocabTestIntroNote =>
      'Your result sets sentence and quiz difficulty. Retake it in Settings up to once a month.';

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
  String get vocabTestResultTitle => 'Your vocabulary';

  @override
  String vocabTestResultVocab(int vocab) {
    return 'About $vocab words';
  }

  @override
  String get vocabTestResultBody =>
      'This result sets your initial difficulty; your answers then adjust it gradually.';

  @override
  String vocabTestResultFreeCap(int vocab) {
    return 'The free plan caps your vocabulary score and sentence difficulty at 100 words. Your score will start at 100 and cannot increase. With Premium, it starts at your measured $vocab words.';
  }

  @override
  String get vocabTestResultClose => 'Close';

  @override
  String get vocabTestError => 'Couldn\'t start vocabulary test';

  @override
  String get vocabTestRetry => 'Start over';

  @override
  String get rankingTitle => 'Vocabulary ranking';

  @override
  String get rankingSubtitle => 'Compare vocabulary scores';

  @override
  String rankingBandScope(String band) {
    return 'Rank in $band';
  }

  @override
  String get rankingYourRank => 'Your rank';

  @override
  String rankingPosition(int rank) {
    return '#$rank';
  }

  @override
  String get rankingCapTiedNote =>
      'No rank shown: many learners share the limit';

  @override
  String get rankingUnrankedHint => 'Create a sentence to get ranked';

  @override
  String get rankingLoadFailed => 'Couldn\'t load the ranking';

  @override
  String get rankingYou => 'You';

  @override
  String get rankingDistributionTitle => 'Score distribution';

  @override
  String get rankingDistributionSubtitle =>
      'Learners by score range; yours is highlighted';

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
    return 'Free score limit: $limit words';
  }

  @override
  String get settingsRanking => 'Ranking';

  @override
  String get settingsRankingSubtitle => 'Compare vocabulary scores';

  @override
  String get guideTitle => 'App guide';

  @override
  String get guideSettingsSubtitle => 'Quick app tour';

  @override
  String get guideSkip => 'Skip';

  @override
  String get guideStart => 'Measure your vocabulary';

  @override
  String get guideClose => 'Close';

  @override
  String get guideLead =>
      'Learn the basics; reopen this guide anytime from Settings.';

  @override
  String get guideFigureLoopSentence => 'Sentence';

  @override
  String get guideFigureLoopQuiz => 'Quiz';

  @override
  String get guideFigureLoopRepeat => 'repeat';

  @override
  String get guideFigureLoopSummary => 'Summary quiz';

  @override
  String get guideFigureLoopEvery => 'after up to five';

  @override
  String get guideFigureCardThai => 'Thai script';

  @override
  String get guideFigureCardPronunciation => 'Pronunciation';

  @override
  String get guideFigureCardTranslation => 'Translation';

  @override
  String get guideFigureCardTranslationSample => 'I like coffee.';

  @override
  String get guideFigureCardTargetWord => 'Gold = target';

  @override
  String get guideChapterOverview => 'Overview';

  @override
  String get guideChapterRoles => 'Features';

  @override
  String get guideChapterHowTo => 'How to';

  @override
  String get guideOverviewTitle => 'How it works';

  @override
  String get guideOverviewBody1 =>
      'AI chooses words for your level and uses them in Thai sentences.';

  @override
  String get guideOverviewBody2 =>
      'Learn a target word in a sentence → take a quiz. Complete up to five to finish a set.';

  @override
  String get guideOverviewSummaryQuiz =>
      'After each set, take a summary quiz; use a hint or review the sentence if needed.';

  @override
  String get guideOverviewBody3 =>
      'Your summary quiz answers adjust your vocabulary score and the difficulty of future sentences, and your sentences gradually use more words. Correct answers without hints have more impact, and missed questions return later.';

  @override
  String get guideRoleSentenceTitle => 'Sentences';

  @override
  String get guideRoleSentenceBody =>
      'Open Details to see each word in context and remember it more easily.';

  @override
  String get guideRoleSoundTitle => 'Pronunciation practice';

  @override
  String get guideRoleSoundBody =>
      'Compare your sounds and tones with the model; tones change meaning in Thai.';

  @override
  String get guideRoleQuizTitle => 'Quizzes';

  @override
  String get guideRoleQuizCheck =>
      'Check quiz: choose the target word\'s meaning.';

  @override
  String get guideRoleQuizSummary =>
      'Summary quiz: choose missing words after each set.';

  @override
  String get guideRoleQuizSpelling =>
      'Spelling quiz: shown when your vocabulary test result is under 100 words. Choose the target word’s spelling from its pronunciation and meaning. After you answer correctly once, that word appears in other formats, such as fill-in-the-blank or word order.';

  @override
  String get guideRoleScoreTitle => 'Vocabulary score';

  @override
  String get guideRoleScoreBody =>
      'An estimate based on your vocabulary test and summary quizzes.';

  @override
  String get guideRoleVocabTestTitle => 'Vocabulary test';

  @override
  String get guideRoleVocabTestBody =>
      'A multiple-choice test that estimates your vocabulary and sets difficulty. Retake it up to once a month.';

  @override
  String get guideRoleRankingTitle => 'Ranking';

  @override
  String get guideRoleRankingBody =>
      'Rank by vocabulary score with an automatically assigned name.';

  @override
  String get guideRoleTopicTitle => 'Topics';

  @override
  String get guideRoleTopicBody =>
      'Learn through festivals, temple etiquette, BL dramas, and more.';

  @override
  String get guideRoleNotificationTitle => 'Study reminders';

  @override
  String get guideRoleNotificationBody =>
      'Get a new sentence set at your chosen time. If you stay away, reminders slow down and eventually stop; open the app to make them daily again.';

  @override
  String get guideRolePremiumTitle => 'Free and Premium';

  @override
  String get guideRolePremiumBody =>
      'Free supports daily study; Premium adds more sentences, topic choice, and a higher vocabulary limit.';

  @override
  String get guidePlanColItem => 'Item';

  @override
  String get guidePlanColFree => 'Free';

  @override
  String get guidePlanColPremium => 'Premium';

  @override
  String get guidePlanRowSentences => 'Daily sentences';

  @override
  String get guidePlanRowTopic => 'Topics';

  @override
  String get guidePlanRowVocab => 'Vocabulary cap';

  @override
  String get guidePlanSentencesUnlimited => 'Unlimited';

  @override
  String guidePlanSentences(int count) {
    return '$count sets';
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
      'Open Learn for today\'s sentence. Sets contain up to five, with progress shown at the top.';

  @override
  String get guideHowSentenceStep3 =>
      'Gold marks target words used in quizzes.';

  @override
  String get guideHowSentenceStep4 => 'Tap the sentence card for details.';

  @override
  String get guideHowDetailTitle => 'The detail screen';

  @override
  String get guideHowDetailLead =>
      'Details connect context, style, spelling, and tones to help words stick.';

  @override
  String get guideHowSoundTitle => 'Listen and repeat';

  @override
  String get guideHowSoundStep1 =>
      '“Listen to the model” plays the sentence on a loop.';

  @override
  String get guideHowSoundStep2 =>
      'In “Pronunciation practice,” hold “Hold to speak” and say the sentence aloud while following the pronunciation shown. You do not need to read Thai script yet. Your tones are checked instantly.';

  @override
  String get guideHowSoundStep3 =>
      'Words turn green, amber, or red by tone accuracy. Tap one to compare your pitch with the model.';

  @override
  String get guideHowQuizTitle => 'Take the check quiz';

  @override
  String get guideHowQuizStep1 =>
      'Tap “Quick check” below the sentence to start.';

  @override
  String get guideHowQuizStep2 => 'Choose the gold word\'s meaning.';

  @override
  String get guideHowQuizStep3 => 'Then review the word\'s meaning and use.';

  @override
  String get guideHowQuizStep4 =>
      'Continue to the next sentence; the set ends with a summary quiz.';

  @override
  String get guideHowReviewQuizTitle => 'Take the summary quiz';

  @override
  String get guideHowReviewQuizStep1 =>
      'After each set, choose missing words from sentences you studied.';

  @override
  String get guideHowReviewQuizStep2 =>
      'Sentences return after one day, three days, one week, then longer. Unmastered words appear first.';

  @override
  String get guideHowReviewQuizStep3 =>
      'Tap Hint once for pronunciation, twice for translation. No-hint answers raise your score faster.';

  @override
  String get guideHowReviewQuizStep4 =>
      'Not sure? “Check sentence” takes you back.';

  @override
  String get guideHowReviewQuizStep5 =>
      'Your answers adjust your vocabulary score and the difficulty of future sentences.';

  @override
  String get guideHowNotifyTitle => 'Set up reminders';

  @override
  String get guideHowNotifyStep1 =>
      'In Settings > \"Daily sentence\", toggle each reminder on or off, or tap a time to change it.';

  @override
  String get guideHowNotifyStep2 =>
      'Free: 1 reminder a day; Premium: up to 3. Each brings a new set.';

  @override
  String get guideHowNotifyStep3 =>
      'Delivered sets appear in the Learn tab even if you skip the notification.';

  @override
  String get guideHowNotifyStep4 =>
      'An unread set is replaced at the next reminder.';

  @override
  String get guideHowNotifyStep5 =>
      'No reminders? Check that notifications are allowed in your device settings. On Free, none comes once you\'ve finished the day\'s sets.';

  @override
  String get guideHowSettingsTitle => 'Settings';

  @override
  String get guideHowSettingsStep1 =>
      'Change notification time, font, and translation language.';

  @override
  String get guideHowSettingsStep2 =>
      'Also choose the next topic and view rankings.';

  @override
  String get guideHowSettingsStep3 =>
      'Reopen this guide anytime from Settings.';

  @override
  String get guideChapterTips => 'Learning tips';

  @override
  String get guideTipsTitle => 'Tips';

  @override
  String get guideTipsRepeat =>
      'Quiz mistakes are fine; repeated target words build vocabulary without memorizing whole sentences.';

  @override
  String get guideTipsScript =>
      'Start by recognizing each Thai word\'s shape, then gradually distinguish consonants, vowels, and tone marks.';

  @override
  String get guideTipsSpeak =>
      'Use learned words and sentences in conversation; saying them aloud helps them stick.';

  @override
  String get coachQuizOfferTitle => 'Quick check';

  @override
  String get coachQuizOfferMessage =>
      'After reading, tap here for a one-question target-word quiz.';

  @override
  String get coachTapHere => 'Tap the highlight';

  @override
  String get coachSkip => 'Skip';

  @override
  String get coachGotIt => 'Got it';

  @override
  String get settingsWordOrderGuide => 'Word order guide';

  @override
  String get settingsWordOrderGuideSubtitle => 'How Thai word order works';

  @override
  String get wordOrderLearnMore => 'More on word order';

  @override
  String get wordOrderGuideTitle => 'Thai word order guide';

  @override
  String get wordOrderGuideHeading => 'Thai word order basics';

  @override
  String get wordOrderGuideIntro =>
      'Stuck? Thai usually puts the topic first, verbs before objects, and describing words after their nouns.';

  @override
  String get wordOrderRule1Title => 'Put the topic first';

  @override
  String get wordOrderRule1Body =>
      'Thai often names what you are talking about first, then says something about it. Places and nouns marked with นี้/นั้น (this/that) often serve as topics.';

  @override
  String get wordOrderRule2Title => 'Specific things can be topics';

  @override
  String get wordOrderRule2Body =>
      'Something already mentioned and marked with นี้/นั้น can go at the start, and the rest of the sentence says something about it.';

  @override
  String get wordOrderRule3Title => 'After the topic: who → does → what';

  @override
  String get wordOrderRule3Body =>
      'The verb comes before its object, as in English.';

  @override
  String get wordOrderRule4Title => 'Descriptions follow nouns';

  @override
  String get wordOrderRule4Body =>
      'Adjectives follow the noun. The owner also comes after the thing owned.';

  @override
  String get wordOrderRule5Title => 'Noun → number → classifier → this';

  @override
  String get wordOrderRule5Body =>
      'Numbers follow the noun, together with a classifier (a counting word). \"This\" comes after that.';

  @override
  String get wordOrderRule6Title => 'ไม่ (not) goes before what it negates';

  @override
  String get wordOrderRule6Body => 'ไม่ goes right before what it negates.';

  @override
  String get wordOrderRule7Title => 'Question words stay in place';

  @override
  String get wordOrderRule7Body =>
      'Question words stay where the answer goes, though ทำไม (why) often comes first. For yes/no questions, add ไหม after the predicate (polite endings go after it).';

  @override
  String get wordOrderRule8Title => 'Words like จะ and แล้ว';

  @override
  String get wordOrderRule8Body =>
      'จะ (will), กำลัง (be doing) and เคย (have ever) go before the verb. แล้ว (already) goes after the verb and its object.';

  @override
  String get wordOrderRule9Title => 'Time: first/last · place: after verb';

  @override
  String get wordOrderRule9Body =>
      'Time expressions go first or last. Places usually follow the verb.';

  @override
  String get wordOrderRule10Title => 'Polite endings come last';

  @override
  String get wordOrderRule10Body =>
      'Men use ครับ. Women usually use ค่ะ, and คะ in questions. They go after ไหม, แล้ว and sentence-final words like นะ, เลย and ด้วย. After นะ, women use คะ (นะคะ).';

  @override
  String get wordOrderTipsTitle => 'Word-order tips';

  @override
  String get wordOrderTipsBody =>
      'If a place or \"this ...\" is the topic of the whole sentence, put it first\nFind the action or state word. \"Who\" goes before it; \"what\" and \"where\" go after it\nDescribing words, numbers, นี้ and มาก go after what they describe\nกับ, ใน etc. go before the noun; อยาก and ต้อง go before the verb\nไหม, แล้ว, นะ and ครับ/ค่ะ/คะ go near the end';

  @override
  String get wordOrderEx1aGloss => 'tour|this|people|many';

  @override
  String get wordOrderEx1aMeaning => 'This tour is crowded';

  @override
  String get wordOrderEx1bGloss => 'airport|people|many';

  @override
  String get wordOrderEx1bMeaning => 'The airport is crowded';

  @override
  String get wordOrderRule1Note =>
      'Thai usually doesn\'t repeat a topic with a pronoun like \"they\".';

  @override
  String get wordOrderEx2aGloss => 'report|this|tomorrow|use|can|?';

  @override
  String get wordOrderEx2aMeaning => 'Can we use this report tomorrow?';

  @override
  String get wordOrderEx3aGloss => 'I|eat|rice';

  @override
  String get wordOrderEx3aMeaning => 'I eat rice';

  @override
  String get wordOrderRule3Note =>
      'Obvious \"who\" and \"what\" are often omitted.';

  @override
  String get wordOrderEx4aGloss => 'house|big';

  @override
  String get wordOrderEx4aMeaning => 'a big house';

  @override
  String get wordOrderEx4bGloss => 'house|of|me';

  @override
  String get wordOrderEx4bMeaning => 'my house';

  @override
  String get wordOrderRule4Note =>
      'บ้านใหญ่ can also mean \"The house is big\": adjectives work as predicates without เป็น. ของ can be left out.';

  @override
  String get wordOrderEx5aGloss => 'cat|two|[classifier]';

  @override
  String get wordOrderEx5aMeaning => 'two cats';

  @override
  String get wordOrderEx5bGloss => 'cat|two|[classifier]|this';

  @override
  String get wordOrderEx5bMeaning => 'these two cats';

  @override
  String get wordOrderEx6aGloss => 'I|not|eat|spicy';

  @override
  String get wordOrderEx6aMeaning => 'I don\'t eat spicy food';

  @override
  String get wordOrderEx6bGloss => 'I|didn\'t|go';

  @override
  String get wordOrderEx6bMeaning => 'I didn\'t go';

  @override
  String get wordOrderEx6cGloss => 'go|can\'t';

  @override
  String get wordOrderEx6cMeaning => 'I can\'t go';

  @override
  String get wordOrderRule6Note =>
      'ไม่ได้ + verb often means \"didn\'t\" or \"am not doing\". In \"can\'t\", ไม่ได้ comes after the verb.';

  @override
  String get wordOrderEx7aGloss => 'you|eat|what';

  @override
  String get wordOrderEx7aMeaning => 'What do you eat?';

  @override
  String get wordOrderEx7bGloss => 'go|where';

  @override
  String get wordOrderEx7bMeaning => 'Where are you going?';

  @override
  String get wordOrderEx7cGloss => 'eat|?';

  @override
  String get wordOrderEx7cMeaning => 'Will you eat?';

  @override
  String get wordOrderEx8aGloss => 'I|will|go';

  @override
  String get wordOrderEx8aMeaning => 'I will go';

  @override
  String get wordOrderEx8bGloss => 'eat|rice|already';

  @override
  String get wordOrderEx8bMeaning => 'I\'ve already eaten';

  @override
  String get wordOrderEx9aGloss => 'tomorrow|I|will|go|Chiang Mai';

  @override
  String get wordOrderEx9aMeaning => 'Tomorrow I\'ll go to Chiang Mai';

  @override
  String get wordOrderEx9bGloss => 'I|work|at|Bangkok';

  @override
  String get wordOrderEx9bMeaning => 'I work in Bangkok';

  @override
  String get wordOrderEx10aGloss => 'eat|?|polite (female)';

  @override
  String get wordOrderEx10aMeaning => 'Will you eat?';

  @override
  String get wordOrderEx10bGloss => 'eat|already|polite (female)';

  @override
  String get wordOrderEx10bMeaning => 'I\'ve already eaten';

  @override
  String get wordOrderRule5Note =>
      'หนึ่ง after the classifier, as in แมวตัวหนึ่ง, means \"a certain cat\".';

  @override
  String get wordOrderEx10cGloss => 'tasty|[softener]|polite (female)';

  @override
  String get wordOrderEx10cMeaning => 'It\'s tasty, isn\'t it?';

  @override
  String get wordOrderRule11Title => 'Clauses: noun → ที่ → description';

  @override
  String get wordOrderRule11Body =>
      'When a clause describes a noun (\"the shop I like\"), it still comes after: usually put ที่ after the noun, then the clause.';

  @override
  String get wordOrderEx11aGloss => 'shop|that|I|like';

  @override
  String get wordOrderEx11aMeaning => 'the shop I like';

  @override
  String get wordOrderRule12Title => 'Prepositions come before the noun';

  @override
  String get wordOrderRule12Body =>
      'กับ (with), ใน (in), บน (on), ให้ (to/for) and ที่ (at) go before the noun.';

  @override
  String get wordOrderEx12aGloss => 'I|go|with|friend';

  @override
  String get wordOrderEx12aMeaning => 'I\'m going with a friend';

  @override
  String get wordOrderEx12bGloss => 'cat|be|on|table';

  @override
  String get wordOrderEx12bMeaning => 'The cat is on the table';

  @override
  String get wordOrderRule13Title => '\"Very\" and \"a little\" come after';

  @override
  String get wordOrderRule13Body =>
      'มาก (very), จริงๆ (really) and นิดหน่อย (a little) follow the adjective or verb.';

  @override
  String get wordOrderEx13aGloss => 'food|this|tasty|very';

  @override
  String get wordOrderEx13aMeaning => 'This food is very tasty';

  @override
  String get wordOrderRule14Title => 'Comparing: adjective → กว่า → other';

  @override
  String get wordOrderRule14Body =>
      '\"A is more ... than B\" is A + adjective + กว่า + B. For \"the most ...\", add ที่สุด after the adjective.';

  @override
  String get wordOrderEx14aGloss => 'today|hot|more than|yesterday';

  @override
  String get wordOrderEx14aMeaning => 'Today is hotter than yesterday';

  @override
  String get wordOrderEx14bGloss => 'thing|this|good|most';

  @override
  String get wordOrderEx14bMeaning => 'This one is the best';

  @override
  String get wordOrderRule15Title => '\"Want\" before the verb, \"can\" after';

  @override
  String get wordOrderRule15Body =>
      'อยาก (want to), ต้อง (must) and ควร (should) go before the verb. ได้ (can) goes after the verb and its object.';

  @override
  String get wordOrderEx15aGloss => 'I|want to|eat|som tam';

  @override
  String get wordOrderEx15aMeaning => 'I want to eat som tam';

  @override
  String get wordOrderEx15bGloss => 'I|speak|Thai|can';

  @override
  String get wordOrderEx15bMeaning => 'I can speak Thai';

  @override
  String get wordOrderRule16Title => 'Verbs line up in a row';

  @override
  String get wordOrderRule16Body =>
      'Thai strings verbs together in the order things happen: ไป (go) + ซื้อ (buy) means \"go shopping\". ไป/มา meaning \"away from\" or \"toward the speaker\" come at the end.';

  @override
  String get wordOrderEx16aGloss => 'I|go|buy|things';

  @override
  String get wordOrderEx16aMeaning => 'I\'m going shopping';

  @override
  String get wordOrderEx16bGloss => 'take|water|come';

  @override
  String get wordOrderEx16bMeaning => 'Bring some water';

  @override
  String get pronGuideTitle => 'Thai pronunciation guide';

  @override
  String get pronGuideHeading => 'Key points of Thai pronunciation';

  @override
  String get pronGuideIntro =>
      'The app\'s readings are romanization with a few extra symbols. Learn the sounds behind them here. Tones are covered in the tone guide.';

  @override
  String get pronSymbolsTitle => 'Reading symbols';

  @override
  String get pronSymbolsBody =>
      'Only the symbols that differ from plain romanization.';

  @override
  String get pronSymbolsDescs =>
      'ɛ is an open \"e\" as in \"bed\"; ɔ is an open \"o\" as in \"law\"|\"u\" said with spread lips, not rounded|A relaxed sound like the \"u\" in \"fur\", without the r|A doubled vowel is long|k has no puff of air and often sounds close to \"g\"; kh has a strong puff|With h, a strong puff of air. t and p have none|\"ng\" as in \"sing\". It can start a word|Tones: no mark is mid, à low, â falling, á high, ǎ rising';

  @override
  String get pronAspTitle => 'With or without a puff of air';

  @override
  String get pronAspBody =>
      'kh, th, ph and ch have a strong puff of air; k, t, p and j have none, like the p in \"spin\" or the t in \"stop\". In Thai this difference changes the word.';

  @override
  String get pronAspMeanings =>
      'chicken|egg|eye|to apply|to throw|to take along';

  @override
  String get pronAspNote =>
      'Say them with your hand in front of your mouth: you should feel air on kh, th and ph, but not on k, t and p.';

  @override
  String get pronLengthTitle => 'Long and short vowels';

  @override
  String get pronLengthBody =>
      'A doubled vowel such as aa or ii is long. Length alone can change the word.';

  @override
  String get pronLengthMeanings => 'to enter|rice|he/she|white';

  @override
  String get pronVowelTitle => 'Telling similar vowels apart';

  @override
  String get pronVowelBody =>
      'e/ɛ, o/ɔ and u/ʉ are different vowels. Open your mouth wide for ɛ and ɔ, and keep your lips spread for ʉ.';

  @override
  String get pronVowelMeanings =>
      'child|sunshine|table|room|to look|hand|money|to walk';

  @override
  String get pronFinalTitle => 'Final k, t, p are not released';

  @override
  String get pronFinalBody =>
      'At the end of a word, k, t and p are stopped without releasing air. Also keep n and ng apart.';

  @override
  String get pronFinalMeanings => 'bird|car|with|plate|faded';

  @override
  String get pronFinalNote =>
      'In Thai script, final ด, ส, ช etc. sound like t, and final บ, พ etc. like p.';

  @override
  String get pronCasualTitle => 'Casual speech';

  @override
  String get pronCasualBody =>
      'In conversation, words often aren\'t said as written: r becomes l, the second consonant of a cluster drops, or the tone changes.';

  @override
  String get pronCasualMeanings =>
      'to love|polite (male)|question particle|I (female)';

  @override
  String get pronCasualNote =>
      'These forms help with listening. When speaking, the written reading is fine.';

  @override
  String get guideRoleQuizWordOrder =>
      'Word-order quiz: some summary quiz questions ask you to put four words from the sentence in the right order. After answering, tap \"Learn more about word order\" to open the word order guide.';

  @override
  String get guideHowSettingsGuides =>
      'Review tone and word-order rules in their guides.';

  @override
  String streakChipDays(int count) {
    return '$count';
  }

  @override
  String get streakChipStart => '0';

  @override
  String streakTitle(int count) {
    return '$count-day sentence streak';
  }

  @override
  String get streakRestart => 'Make 1 sentence to restart';

  @override
  String get streakStart => 'Make a sentence today to start';

  @override
  String streakBest(int count) {
    return 'Best $count';
  }

  @override
  String streakNextMilestone(int count, int target) {
    return '$count to go until $target days';
  }

  @override
  String get streakToday => 'Today';

  @override
  String get streakWeekdayLetters => 'MTWTFSS';
}
