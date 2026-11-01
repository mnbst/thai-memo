// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class L10nKo extends L10n {
  L10nKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => '매일 태국어';

  @override
  String get settingsDisplay => '화면';

  @override
  String get settingsFont => '글꼴';

  @override
  String get settingsFontPickerTitle => '글꼴 선택';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsLanguagePickerTitle => '언어 선택';

  @override
  String get settingsLanguageSubtitle => '번역과 해설 언어가 변경돼요';

  @override
  String get settingsLanguageNote =>
      '번역과 해설 언어가 변경돼요. 이미 만든 예문의 번역은 생성 당시 언어로 유지돼요.';

  @override
  String get navLearn => '학습';

  @override
  String get navHistory => '기록';

  @override
  String get navSettings => '설정';

  @override
  String get learnOpenDetail => '상세';

  @override
  String get learnQuizTitle => '확인 퀴즈';

  @override
  String get learnSummaryQuizTitle => '종합 퀴즈';

  @override
  String get learnNextSentence => '다음 예문';

  @override
  String get learnNextSet => '다음 세트';

  @override
  String get learnGoToSummaryQuiz => '종합 퀴즈로';

  @override
  String learnDailySetRemaining(int count) {
    return '$count개 더 학습하면 종합 퀴즈';
  }

  @override
  String get learnDailySetLast => '다음은 종합 퀴즈';

  @override
  String learnDailySetProgress(int position, int total) {
    return '$position / $total';
  }

  @override
  String get commonOk => '확인';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get sentencePreparing => '예문을 준비하고 있어요...';

  @override
  String todaysWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '학습 단어',
    );
    return '$_temp0';
  }

  @override
  String get playPronunciation => '발음 재생';

  @override
  String get sentenceListenModel => '모범 발음 듣기';

  @override
  String get sentencePractice => '발음 연습';

  @override
  String get sentenceUsingWord => '이 단어를 사용한 예문';

  @override
  String get badgePremiumSentence => 'Premium 예문';

  @override
  String get badgeFreeSentence => 'Free 예문';

  @override
  String get sampleSentenceNotice => '샘플 예문(기록에 저장되지 않아요)';

  @override
  String get sampleReload => '오늘의 예문 불러오기';

  @override
  String get sampleGreetingTranslation => '안녕하세요(남성 화자)';

  @override
  String get sampleGreetingWord1Meaning => '안녕하세요, 안녕히 가세요';

  @override
  String get sampleGreetingWord1Role => '인사말';

  @override
  String get sampleGreetingWord2Meaning => '~입니다(남성이 쓰는 공손한 종결 표현)';

  @override
  String get sampleGreetingWord2Role => '문말 조사';

  @override
  String get sampleGreetingTopic => '일상적인 인사';

  @override
  String get sampleGreetingStyle => '구어체';

  @override
  String get sampleGreetingEmotion => '공손함, 격식 있음';

  @override
  String get sampleGreetingUsage =>
      '아침, 낮, 저녁 언제든 쓸 수 있는 기본 인사예요. 여성은 「ค่ะ」를 사용해요.';

  @override
  String get quizTodayTitle => '퀴즈';

  @override
  String get quizGenerating => '퀴즈를 만들고 있어요...';

  @override
  String get quizOpenSentenceFirst => '먼저 예문을 열어 보세요';

  @override
  String get quizFromLearningSentence => '학습 중인 예문에서 문제가 출제돼요';

  @override
  String get quizBackToSentence => '예문으로 돌아가기';

  @override
  String get quizCorrect => '정답!';

  @override
  String get quizIncorrect => '오답';

  @override
  String quizCorrectAnswer(String answer) {
    return '정답: $answer';
  }

  @override
  String get quizPrompt => '밑줄에 들어갈 단어를 선택해 주세요';

  @override
  String get quizMeaningPrompt => '이 단어의 뜻을 선택해 주세요';

  @override
  String get quizSpellingPrompt => '이 발음에 맞는 철자를 선택해 주세요';

  @override
  String get quizWordOrderPrompt => '올바른 순서로 배열해 주세요';

  @override
  String get quizWordOrderCheck => '정답 확인';

  @override
  String quizWordOrderYourAnswer(String order) {
    return '내가 배열한 순서: $order';
  }

  @override
  String get quizWordExplanation => '단어 해설';

  @override
  String quizProgress(int index, int total) {
    return '문제 $index / $total';
  }

  @override
  String get quizSentenceReviewed => '예문 복습 완료';

  @override
  String get quizReviewSentence => '예문 복습';

  @override
  String get quizOpenSentenceDetail => '예문 상세 보기';

  @override
  String get quizHint => '힌트';

  @override
  String get quizHintPronunciation => '힌트 1: 발음 보기';

  @override
  String get quizHintTranslation => '힌트 2: 한국어 번역 보기';

  @override
  String get quizHintShown => '힌트를 이미 확인했어요';

  @override
  String get quizCheckSentence => '예문 확인';

  @override
  String get quizPlaySentence => '예문 재생';

  @override
  String get quizPlayWord => '단어 재생';

  @override
  String get quizWhyCorrect => '정답인 이유';

  @override
  String get quizSpellingBreakdown => '철자 분석';

  @override
  String quizToneRuleFor(String consonantClass) {
    return '$consonantClass 성조 규칙';
  }

  @override
  String get quizPartOnset => '초성 자음';

  @override
  String get quizPartVowel => '모음';

  @override
  String get quizPartCoda => '종성 자음';

  @override
  String get quizPartVowelCoda => '모음+종성 자음';

  @override
  String get quizPartToneLabel => '성조';

  @override
  String get quizPartKaran => '까란';

  @override
  String get quizPartSilent => '묵음';

  @override
  String get quizPartSilentValue => '읽지 않음';

  @override
  String get quizPartNone => '없음';

  @override
  String get quizWhyIncorrect => '오답인 이유';

  @override
  String get quizSeeResults => '결과 보기';

  @override
  String get quizNextQuestion => '다음 문제';

  @override
  String get commonTryAgain => '다시 시도';

  @override
  String get vocabScore => '어휘 점수';

  @override
  String get vocabScoreCalculating => '어휘 점수를 계산하고 있어요...';

  @override
  String get vocabScoreUp => '어휘 점수 상승!';

  @override
  String get vocabScoreCapped => '어휘 점수가 상한에 도달했어요';

  @override
  String get vocabScorePremiumPitch => 'Premium으로 계속 성장 기록하기';

  @override
  String vocabWords(int count) {
    return '$count단어';
  }

  @override
  String vocabWordsDelta(String delta) {
    return '$delta단어';
  }

  @override
  String get historyTitle => '기록';

  @override
  String get historyFavoritesOnly => '즐겨찾기만 표시';

  @override
  String get historyDeleteAll => '모두 삭제';

  @override
  String get historyFilterAll => '전체';

  @override
  String get historyFilterFavorites => '즐겨찾기';

  @override
  String historyDateWithYear(int year, int month, int day) {
    return '$year년 $month월 $day일';
  }

  @override
  String historyDate(int month, int day) {
    return '$month월 $day일';
  }

  @override
  String get historySearchHint => '태국어 또는 한국어로 검색';

  @override
  String get historyEmptyFavorites => '즐겨찾기한 예문이 없어요';

  @override
  String get historyEmptySearch => '검색 결과가 없어요';

  @override
  String get historyEmpty => '아직 예문이 없어요';

  @override
  String get historyEmptyFavoritesHint => '예문의 하트 아이콘을 눌러 즐겨찾기에 추가할 수 있어요';

  @override
  String get historyEmptySearchHint => '다른 검색어로 검색해 보세요';

  @override
  String get historyEmptyHint => '새 예문을 만들어 보세요';

  @override
  String get historyDeleteAllConfirm => '모든 예문 기록을 삭제할까요? 이 작업은 취소할 수 없어요.';

  @override
  String get historyDeletedAll => '모든 예문을 삭제했어요';

  @override
  String historyDeleteFailed(String error) {
    return '삭제하지 못했어요: $error';
  }

  @override
  String get historyDeleteConfirmTitle => '삭제 확인';

  @override
  String get historyDeleteConfirm => '이 예문을 삭제할까요?';

  @override
  String get historyDeletedOne => '예문을 삭제했어요';

  @override
  String historyWordCount(int count) {
    return '$count단어';
  }

  @override
  String get commonError => '오류가 발생했어요';

  @override
  String get commonCancel => '취소';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonUnknown => '알 수 없음';

  @override
  String get detailTitle => '예문 상세';

  @override
  String get detailShare => '공유';

  @override
  String detailWordBreakdown(int count) {
    return '단어 분석 ($count)';
  }

  @override
  String get detailQuizTarget => '→ 퀴즈에 출제';

  @override
  String get detailTapForTone => '눌러서 성조 확인';

  @override
  String get detailUsageSection => '사용법';

  @override
  String get detailWordsSection => '단어';

  @override
  String get detailFavoriteAdd => '즐겨찾기에 추가';

  @override
  String get detailFavoriteRemove => '즐겨찾기에서 삭제';

  @override
  String get detailContextSection => '맥락·사용법';

  @override
  String get detailContextTopic => '상황';

  @override
  String get detailContextStyle => '문체';

  @override
  String get detailContextEmotion => '감정·어조';

  @override
  String get detailContextUsage => '사용 상황';

  @override
  String get detailContextCulture => '문화적 배경';

  @override
  String detailCreatedAt(String date) {
    return '생성일: $date';
  }

  @override
  String get detailCopied => '클립보드에 복사했어요';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsAccount => '계정';

  @override
  String get settingsUser => '사용자';

  @override
  String get settingsGuest => '게스트';

  @override
  String get settingsRankingName => '랭킹 표시 이름';

  @override
  String get settingsNotSignedIn => '로그인하지 않았어요';

  @override
  String get settingsPlan => '요금제';

  @override
  String get settingsPlanTrial => '무료 체험 중';

  @override
  String get settingsPlanTrialNoCharge => '자동 결제 없음';

  @override
  String get settingsDeleteAccount => '계정 삭제';

  @override
  String get settingsSignOut => '로그아웃';

  @override
  String get settingsSignInToSave => '로그인하고 학습 진도 저장';

  @override
  String get settingsSignOutConfirm => '로그아웃할까요?';

  @override
  String get settingsDeleteAccountTitle => '계정 삭제';

  @override
  String get settingsDeleteAccountConfirm =>
      '계정을 삭제하면 서버와 기기에 있는 모든 학습 데이터가 영구적으로 삭제돼요. 이 작업은 되돌릴 수 없어요.';

  @override
  String get settingsAccountDeleted => '계정과 모든 데이터를 삭제했어요';

  @override
  String get settingsFontSample => '예문';

  @override
  String get settingsLearningStatus => '학습 현황';

  @override
  String get settingsGuideSection => '가이드';

  @override
  String get settingsLearningSection => '학습 설정';

  @override
  String get settingsToneGuide => '성조 가이드';

  @override
  String get settingsToneGuideSubtitle => '태국어 성조 규칙 알아보기';

  @override
  String get settingsPronGuide => '발음 가이드';

  @override
  String get settingsPronGuideSubtitle => '발음 표기와 구별하기 어려운 소리 알아보기';

  @override
  String get settingsThaiScriptGuide => '태국 문자 가이드';

  @override
  String get settingsThaiScriptGuideSubtitle => '자주 쓰는 문자와 철자 읽는 법 알아보기';

  @override
  String get settingsResetLearningData => '학습 데이터 초기화';

  @override
  String get settingsResetLearningDataSubtitle => '기기의 예문·퀴즈 기록 삭제';

  @override
  String get settingsResetTitle => '학습 데이터 초기화';

  @override
  String get settingsResetConfirm =>
      '기기에 저장된 예문, 퀴즈 기록, 학습 진도가 모두 삭제돼요. 계정은 유지돼요.';

  @override
  String get settingsResetDone => '학습 데이터를 초기화했어요';

  @override
  String get settingsResetFailed => '초기화하지 못했어요';

  @override
  String get commonReset => '초기화';

  @override
  String get settingsDailyNotification => '매일 예문 알림';

  @override
  String get settingsDailyNotificationSubtitle => '예문을 알려 드려요';

  @override
  String get settingsAllowNotificationInOsSettings => '기기 설정에서 알림을 허용해 주세요';

  @override
  String get settingsNotificationTime => '알림 시간';

  @override
  String get notifyScheduleOff => '끔';

  @override
  String notifySchedulePremiumUpsell(int count) {
    return 'Premium에서는 예문 알림을 하루 최대 $count회 설정할 수 있어요';
  }

  @override
  String get notifyScheduleReplaceNote =>
      '알림마다 새로운 예문 세트가 도착해요. 다음 알림 전까지 하나도 읽지 않은 예문 세트는 새 세트로 교체돼요.';

  @override
  String get notifyScheduleChangeTime => '시간 변경';

  @override
  String get notifyScheduleTimeTaken => '이미 설정된 시간이에요';

  @override
  String get notifyScheduleSave => '저장';

  @override
  String get settingsTopic => '주제';

  @override
  String get settingsTopicRandom => '자동 선택';

  @override
  String settingsNextLevelIn(int count) {
    return '다음 레벨까지 $count단어';
  }

  @override
  String settingsFreeVocabLimit(int limit) {
    return 'Free 요금제는 $limit단어가 상한이에요';
  }

  @override
  String get settingsCouldNotOpenUrl => 'URL을 열지 못했어요';

  @override
  String get settingsAbout => '앱 정보';

  @override
  String get settingsTagline => '태국어를 매일 충분히 만나 보세요';

  @override
  String get settingsPrivacyPolicy => '개인정보 처리방침';

  @override
  String get settingsTerms => '이용약관';

  @override
  String get settingsContact => '의견 및 문의';

  @override
  String get settingsLifetimeMigration => '평생 이용 요금제로 전환';

  @override
  String get settingsLifetimeMigrationSubtitle => '추가 결제 없음';

  @override
  String get lifetimeMigrationTitle => '평생 이용 요금제가 새로 생겼어요';

  @override
  String get lifetimeMigrationBody =>
      '항상 이용해 주셔서 감사해요. 계속 이용해 주신 분은 지금 무료로 평생 이용 요금제로 전환할 수 있어요.';

  @override
  String get lifetimeMigrationNoCharge => '추가 결제 없음';

  @override
  String lifetimeMigrationCancelNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            '전환 후 월간 자동 갱신을 직접 중지해 주세요(Google Play 정기 결제 설정). 중지하지 않으면 월 요금이 계속 청구돼요.',
        'other':
            '전환 후 월간 자동 갱신을 직접 중지해 주세요(App Store 계정 설정). 중지하지 않으면 월 요금이 계속 청구돼요.',
      },
    );
    return '$_temp0';
  }

  @override
  String get lifetimeMigrationProgress => '전환하고 있어요…';

  @override
  String get lifetimeMigrationDoneTitle => '평생 이용 요금제로 전환했어요';

  @override
  String get lifetimeMigrationDoneBody =>
      '이제 Premium을 계속 이용할 수 있어요. 월간 자동 갱신을 꼭 중지해 주세요.';

  @override
  String get lifetimeMigrationFailedTitle => '전환하지 못했어요';

  @override
  String get lifetimeMigrationFailedBody =>
      '잠시 후 다시 시도해 주세요. Premium은 이전과 같이 계속 이용할 수 있어요.';

  @override
  String get lifetimeMigrationConfirm => '평생 이용으로 전환';

  @override
  String get lifetimeMigrationLater => '나중에';

  @override
  String get trialEndedTitle => 'Premium 체험이 종료됐어요';

  @override
  String get trialEndedBody => '오늘부터 무료 요금제로 전환돼요.';

  @override
  String get trialEndedKeepPremium => 'Premium 요금제 보기';

  @override
  String get trialEndedKeepFree => '나중에';

  @override
  String get trialEndedChangeQuotaLabel => '예문';

  @override
  String get trialEndedChangeQuotaPremium => '무제한';

  @override
  String trialEndedChangeQuotaFree(int free) {
    return '하루 $free세트';
  }

  @override
  String get trialEndedChangeVocabLabel => '어휘 점수';

  @override
  String get trialEndedChangeVocabPremium => '상한 없음';

  @override
  String trialEndedChangeVocabFree(int free) {
    return '$free단어까지';
  }

  @override
  String trialStartedTitle(int days) {
    return 'Premium을 $days일 동안 체험할 수 있어요';
  }

  @override
  String get trialStartedBody => 'Free 버전에서 사용할 수 없는 기능을 이 기간 동안 열어 드렸어요.';

  @override
  String get trialStartedChangeQuotaLabel => '예문';

  @override
  String get trialStartedChangeQuota => '무제한';

  @override
  String get trialStartedChangeTopicLabel => '주제 선택';

  @override
  String get trialStartedChangeTopic => '예문 주제를 직접 선택할 수 있어요';

  @override
  String get trialStartedStart => '확인';

  @override
  String get topicPickerTitle => '주제 선택';

  @override
  String get nextTopicPrefix => '다음 주제: ';

  @override
  String get topicPrefix => '주제: ';

  @override
  String get topicName_blDrama => '태국 BL 드라마';

  @override
  String get topicSub_blDrama => '고백, 오해, 재회, 질투, 배신, 화해, 벽치기, 애칭 부르기';

  @override
  String get topicName_romance => '연애·남녀 관계';

  @override
  String get topicSub_romance => '고백, 데이트, 달콤한 말, 장거리 연애, 이별, 화해';

  @override
  String get topicName_work => '직장';

  @override
  String get topicSub_work => '업무 보고·연락·상담, 회의, 야근 신청, 동료와의 잡담';

  @override
  String get topicName_greetings => '인사';

  @override
  String get topicSub_greetings => '아침·낮·저녁, 첫 만남, 재회, 작별, 전화';

  @override
  String get topicName_food => '음식';

  @override
  String get topicSub_food => '컬래버 카페, 주문, 감상, 길거리 음식, 매운맛 조절, 알레르기';

  @override
  String get topicName_travel => '여행';

  @override
  String get topicSub_travel => '촬영지 투어, 호텔, 길 안내, 관광지, 공항, 투어';

  @override
  String get topicName_family => '가족';

  @override
  String get topicSub_family => '가족 소개, 육아, 부모님께 감사, 형제자매, 가족 행사';

  @override
  String get topicName_shopping => '쇼핑';

  @override
  String get topicSub_shopping => '가격 흥정, 크기·색상 확인, 반품, 야시장';

  @override
  String get topicName_transport => '교통';

  @override
  String get topicSub_transport => 'Grab, BTS, 오토바이 택시, 썽태우, 교통 체증';

  @override
  String get topicName_health => '건강';

  @override
  String get topicSub_health => '증상 설명, 약국, 마사지, 건강검진';

  @override
  String get topicName_weather => '날씨';

  @override
  String get topicSub_weather => '더위, 우기, 태풍, 자외선 대책';

  @override
  String get topicName_hobbies => '취미';

  @override
  String get topicSub_hobbies => '무에타이, 음악, 영화, 골프, SNS, 게임';

  @override
  String get topicName_school => '학교';

  @override
  String get topicSub_school => '수업, 숙제, 시험, 방과 후, 어학원';

  @override
  String get topicName_religion => '종교·신앙';

  @override
  String get topicSub_religion => '최애 생일의 탐분, 사원 예절, 탁발, 부적, 승려에게 말하는 법, 불교 행사';

  @override
  String get topicName_festivals => '전통·축제';

  @override
  String get topicSub_festivals => '송끄란, 러이끄라통, 왕실 행사, 지역 전통 음식';

  @override
  String get topicName_etiquette => '예절';

  @override
  String get topicSub_etiquette => '와이 인사법, 높임말, 금기, 식사 예절, 선물';

  @override
  String get topicName_life => '태국 생활';

  @override
  String get topicSub_life => '쇼핑, 교통, 건강, 가족, 날씨, 음식';

  @override
  String get topicName_thaiTravel => '태국 여행';

  @override
  String get topicSub_thaiTravel => '관광, 호텔, 교통, 쇼핑, 음식';

  @override
  String get topicName_oshi => '덕질';

  @override
  String get topicSub_oshi => '콘서트, 티켓팅, 굿즈, 악수회, 공항 마중';

  @override
  String get styleName_news => '뉴스 기사체';

  @override
  String get styleName_spoken => '구어체';

  @override
  String get styleName_polite => '공손한 표현';

  @override
  String get styleName_sns => 'SNS·문자 메시지';

  @override
  String get styleName_narrative => '서사·문학체';

  @override
  String get vocabLevelIntro => '입문';

  @override
  String get vocabLevelBeginner => '초급';

  @override
  String get vocabLevelUpperBeginner => '초중급';

  @override
  String get vocabLevelIntermediate => '중급';

  @override
  String get vocabLevelAdvanced => '고급';

  @override
  String get vocabSeePremium => 'Premium 보기';

  @override
  String get commonClose => '닫기';

  @override
  String get paywallTitle => 'Premium 요금제';

  @override
  String get paywallSignInRequired => '로그인이 필요해요';

  @override
  String get paywallSignInForPurchase =>
      '기기를 바꾼 뒤에도 구매 내역을 이어서 이용하려면 로그인해 주세요.';

  @override
  String get paywallSignInForRestore => '구매 내역을 복원하려면 구매할 때 사용한 계정으로 로그인해 주세요.';

  @override
  String get paywallActive => 'Premium 요금제를 이용 중이에요';

  @override
  String get paywallSubscribe => 'Premium 구독';

  @override
  String get paywallPlanMonthlyTitle => '월간 요금제';

  @override
  String get paywallPlanMonthlyNote => '매월 자동 갱신·언제든 해지';

  @override
  String paywallPlanMonthlyPrice(String price) {
    return '$price / 월';
  }

  @override
  String get paywallPlanYearlyTitle => '연간 요금제';

  @override
  String get paywallPlanYearlyNote => '매년 자동 갱신·언제든 해지';

  @override
  String paywallPlanYearlyPrice(String price) {
    return '$price / 년';
  }

  @override
  String paywallPlanYearlySave(int percent) {
    return '$percent% 할인';
  }

  @override
  String get paywallPlanLifetimeTitle => '평생 이용 요금제';

  @override
  String get paywallPlanLifetimeNote => '한 번만 결제·갱신 없음';

  @override
  String get paywallPurchaseCta => '이 요금제로 시작';

  @override
  String get paywallChangeToLifetimeCta => '평생 이용으로 변경';

  @override
  String get paywallLifetimeNote => '한 번만 결제해요. 갱신은 없어요.';

  @override
  String paywallMonthlyToLifetimeNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android':
            '평생 이용 요금제를 구매해도 현재 구독은 자동으로 해지되지 않아요. Google Play 정기 결제 설정에서 해지해 주세요.',
        'other':
            '평생 이용 요금제를 구매해도 현재 구독은 자동으로 해지되지 않아요. App Store 계정 설정에서 해지해 주세요.',
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
            '구독은 자동으로 갱신돼요. 다음 갱신일 전까지 해지하지 않으면 같은 요금으로 자동 갱신돼요. 관리 및 해지는 Google Play 정기 결제 설정에서 할 수 있어요.',
        'other':
            '구독은 자동으로 갱신돼요. 이용 기간 종료 24시간 전까지 해지할 수 있어요. 갱신 요금은 종료 전 24시간 이내에 청구되며, 관리 및 해지는 App Store 계정 설정에서 할 수 있어요.',
      },
    );
    return '$_temp0';
  }

  @override
  String get paywallTrialBadge => '첫 이용 한정';

  @override
  String paywallTrialHeadline(int days) {
    return 'Premium $days일 무료 체험';
  }

  @override
  String paywallTrialCta(int days) {
    return '$days일 무료 체험';
  }

  @override
  String paywallTrialTermsMonthly(int days, String price) {
    return '$days일 동안 무료예요. 이후 월 $price에 자동 갱신돼요. 요금이 청구되지 않도록 하려면 무료 체험 종료 24시간 전까지 해지해 주세요.';
  }

  @override
  String paywallTrialTermsYearly(int days, String price) {
    return '$days일 동안 무료예요. 이후 연 $price에 자동 갱신돼요. 요금이 청구되지 않도록 하려면 무료 체험 종료 24시간 전까지 해지해 주세요.';
  }

  @override
  String get paywallPlanCurrent => '이용 중';

  @override
  String get paywallChangeToYearlyCta => '연간 요금제로 변경';

  @override
  String get paywallChangeToMonthlyCta => '월간 요금제로 변경';

  @override
  String paywallChangeToYearlyNote(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android': '즉시 연간 요금제로 전환되고 연간 요금이 청구돼요. 남은 월간 이용 기간은 연간 요금제 기간에 추가돼요.',
        'other': '즉시 연간 요금제로 전환돼요. 남은 월간 이용 기간의 요금은 Apple에서 일할 계산해 환불해요.',
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
            '즉시 월간 요금제로 전환돼요. 결제한 연간 이용 기간이 끝날 때까지는 청구되지 않고, 이후 월간 요금으로 갱신돼요.',
        'other': '현재 연간 요금제가 만료되면 월간 요금제로 전환돼요. 그때까지는 연간 요금제를 그대로 이용할 수 있어요.',
      },
    );
    return '$_temp0';
  }

  @override
  String get paywallCancelSubscriptionNote =>
      '평생 이용 요금제를 구매했어요. 구독 자동 갱신이 계속되고 있으므로 해지하지 않으면 요금이 계속 청구돼요.';

  @override
  String get paywallManageSubscriptions => '구독 해지';

  @override
  String get paywallRestore => '구매 복원';

  @override
  String paywallPriceYen(String amount) {
    return '¥$amount / 월';
  }

  @override
  String paywallPrice(String currency, String amount) {
    return '$currency $amount / 월';
  }

  @override
  String get paywallFeatureQuotaTitle => '어휘 점수 100 이상으로 성장';

  @override
  String get paywallFeatureQuotaPremium => '예문 무제한·어휘 점수 상한 없음';

  @override
  String get paywallFeatureTopicTitle => '좋아하는 상황의 태국어부터 시작';

  @override
  String get paywallFeatureTopicPremium => '여행·생활·BL 드라마 등에서 직접 선택';

  @override
  String get onboarding1Title => '태국 문자를 읽지 못해도 괜찮아요';

  @override
  String get onboarding1Body =>
      '내 수준에 맞는 예문을 매일 받아 보세요.\n카드를 누르면 읽는 법과 뜻을 확인할 수 있어요.';

  @override
  String get onboarding2Title => '성조까지 익히는 발음 연습';

  @override
  String get onboarding2Body =>
      '모범 발음을 듣고 내 목소리를 녹음해요.\n성조가 어긋난 부분을 바로 확인할 수 있어요.';

  @override
  String get onboarding3Title => '퀴즈로 어휘 점수 UP';

  @override
  String get onboarding3Body => '틀린 단어는 반복해서 출제돼요.\n점수에 따라 예문에 나오는 단어가 늘어나요.';

  @override
  String get onboardingSkip => '건너뛰기';

  @override
  String get onboardingNext => '다음';

  @override
  String get onboardingHaveAccount => '이미 계정이 있나요?';

  @override
  String get interviewIntroTitle => '질문 4개에 답해 주세요';

  @override
  String get interviewIntroBody => '답변에 맞춰 이 앱으로 학습하는 방법을 알려 드릴게요. 금방 끝나요.';

  @override
  String get interviewIntroStart => '시작';

  @override
  String interviewStepLabel(int current, int total) {
    return '$current / $total';
  }

  @override
  String get interviewLevelQuestion => '태국어를 얼마나 공부했나요?';

  @override
  String get interviewLevelNone => '완전 처음이에요';

  @override
  String get interviewLevelChars => '문자를 조금 읽을 수 있어요';

  @override
  String get interviewLevelWords => '단어나 인사말을 알아요';

  @override
  String get interviewLevelConv => '일상 회화를 할 수 있어요';

  @override
  String get interviewGoalQuestion => '어떤 상황에서 태국어를 쓰고 싶나요?';

  @override
  String get interviewGoalTravel => '여행에서 쓰고 싶어요';

  @override
  String get interviewGoalWork => '업무에 필요해요';

  @override
  String get interviewGoalLive => '태국에서 살고 있거나 살고 싶어요';

  @override
  String get interviewGoalCulture => '드라마·음악을 즐기고 싶어요';

  @override
  String get interviewTimeQuestion => '하루에 얼마나 학습할 수 있나요?';

  @override
  String get interviewTimeShort => '몇 분만';

  @override
  String get interviewTimeMedium => '약 10분';

  @override
  String get interviewTimeLong => '30분 이상';

  @override
  String get interviewStruggleQuestion => '태국어를 배우며 어려웠던 점이 있나요?';

  @override
  String get interviewStruggleNone => '이제 막 시작했어요';

  @override
  String get interviewStruggleScript => '문자를 읽기 어려워요';

  @override
  String get interviewStruggleTone => '성조가 어려워요';

  @override
  String get interviewStruggleVocab => '단어가 잘 외워지지 않아요';

  @override
  String get philosophyHeading => '이 앱의 학습 방식';

  @override
  String get philosophy1None =>
      '받은 예문을 먼저 **소리와 뜻**으로 익혀요. **태국 문자**는 전체적인 모양부터 눈에 익히며 천천히 배워 보세요.';

  @override
  String get philosophy1Chars =>
      '받은 예문을 **단어별로 분석**해 뜻과 발음을 보여 줘요. 읽을 수 있는 태국 문자가 늘수록 스스로 읽을 수 있는 범위도 넓어져요.';

  @override
  String get philosophy1Words =>
      '예문은 앱의 **어휘 점수**에 맞춰 만들어져요. 인사말부터 시작해 일상 표현까지 점차 넓어져요.';

  @override
  String get philosophy1Conv =>
      '예문의 난이도는 **퀴즈 결과**에 따라 정해져요. 많이 맞힐수록 더 다양한 단어가 나와요.';

  @override
  String get philosophyKeyWord =>
      '예문에는 매번 **핵심 단어 하나**가 있어요. 그 단어가 실제로 어떻게 쓰이는지 예문으로 익혀 보세요.';

  @override
  String get philosophy2None =>
      '처음에는 태국 문자를 읽지 못해도 괜찮아요. 이 앱에서는 **태국 문자와 성조의 관계**도 배울 수 있어요. 읽는 법이 헷갈리면 설정의 발음 가이드를 이용해 보세요.';

  @override
  String get philosophy2Script =>
      '태국어는 **철자에 따라 성조가 정해져요**. 이 앱에서 그 원리를 단어마다 확인할 수 있어요. 앱의 발음 표기와 구별하기 어려운 소리는 설정의 발음 가이드에서 확인할 수 있어요.';

  @override
  String get philosophy2Tone =>
      '**발음 연습 기능**을 활용해 보세요. 모범 발음과 내 목소리를 비교해 어느 단어의 성조가 어긋났는지 알 수 있어요. 성조 규칙은 설정의 성조 가이드에서 확인할 수 있어요.';

  @override
  String get philosophy2Vocab =>
      '**퀴즈**로 단어별 학습 정도를 확인해요. 확실히 익히지 못한 단어는 나중에 다시 출제돼요.';

  @override
  String get philosophy3Travel =>
      '**Premium**에서는 예문 주제를 직접 선택할 수 있어요. ‘태국 여행’을 선택하면 관광, 이동, 쇼핑 등 현지에서 쓸 만한 예문이 도착해요.';

  @override
  String get philosophy3Work =>
      '**Premium**에서는 예문 주제를 직접 선택할 수 있어요. ‘직장’을 선택하면 직장에서 쓸 만한 예문이 도착해요.';

  @override
  String get philosophy3Live =>
      '**Premium**에서는 예문 주제를 직접 선택할 수 있어요. ‘태국 생활’을 선택하면 쇼핑, 교통, 가족 등 생활 속 예문이 도착해요.';

  @override
  String get philosophy3Culture =>
      '**Premium**에서는 예문 주제를 직접 선택할 수 있어요. ‘태국 BL 드라마’나 ‘덕질’을 선택하면 작품이나 팬 활동에서 쓰는 표현이 도착해요.';

  @override
  String get philosophy3TimeShort => '**몇 분이면** 예문 하나를 읽고 확인 퀴즈까지 풀 수 있어요.';

  @override
  String get philosophy3TimeMedium =>
      '**10분이면** 예문을 추가하면서 발음을 연습하고 이전 단어까지 복습할 수 있어요.';

  @override
  String get philosophy3TimeLong =>
      '**30분이면** 예문 추가와 발음 연습은 물론 지난 예문 복습과 성조 학습까지 할 수 있어요.';

  @override
  String get philosophyStart => '사용법 보기';

  @override
  String get notifCoachTitle => '알림으로 매일 학습하는 습관 만들기';

  @override
  String get notifCoachHabit => '정해진 시간에 새 예문이 도착해 꾸준히 학습하는 계기가 돼요';

  @override
  String get notifCoachNow => '지금';

  @override
  String get notifCoachSampleTitle => '🇹🇭 ขอบคุณ(고마워요)';

  @override
  String get notifCoachSampleBody => '→ 커피 고마워요';

  @override
  String get notifCoachEnable => '알림 켜기';

  @override
  String get notifCoachLater => '지금은 안 함';

  @override
  String get notifCoachEnabled => '매일 정해진 시간에 예문을 보내 드려요. 시간은 설정에서 변경할 수 있어요.';

  @override
  String get notifCoachStillQuiet => '알림은 지금처럼 알림 센터에 조용히 도착해요.';

  @override
  String get commonGotIt => '확인';

  @override
  String get premiumHint1Title => '좋아하는 상황의 태국어부터 시작';

  @override
  String get premiumHint1Body => '여행·생활·BL 드라마 등에서 예문 주제를 직접 선택할 수 있어요';

  @override
  String get signInReminderTitle => '학습 진도 보호';

  @override
  String get signInReminderMessage =>
      '로그인하면 진도가 저장되어 기기를 바꾼 뒤에도 계속 학습할 수 있어요. 로그인하지 않은 상태에서 3일 동안 이용하지 않으면 학습 진도가 삭제돼요.';

  @override
  String get signInReminderBanner =>
      '학습 데이터를 보호하세요\n로그인하지 않고 3일 동안 이용하지 않으면 학습 진도가 삭제돼요.';

  @override
  String get commonLater => '나중에';

  @override
  String get signIn => '로그인';

  @override
  String get signInSheetMessage => '진도를 저장하고 기기를 바꾼 뒤에도 계속 학습할 수 있어요.';

  @override
  String get signInWithApple => 'Apple로 로그인';

  @override
  String get signInWithGoogle => 'Google로 로그인';

  @override
  String get quizOfferToQuiz => '확인 퀴즈로';

  @override
  String get quizOfferOneQuestion => '외웠는지 확인';

  @override
  String get quizOfferBody => '단어를 외웠는지 퀴즈로 확인해요.';

  @override
  String get quizOfferTryOne => '확인';

  @override
  String get audioRepeat => '반복';

  @override
  String get audioOnce => '한 번만';

  @override
  String get audioSpeed => '재생 속도';

  @override
  String get audioPause => '일시 정지';

  @override
  String get audioPlay => '재생';

  @override
  String audioModeHint(String mode) {
    return '현재 $mode. 길게 눌러 재생 모드 변경';
  }

  @override
  String get audioModeRepeat => '반복 재생';

  @override
  String get audioModeOnce => '한 번만 재생';

  @override
  String get audioPosition => '재생 위치';

  @override
  String get pronunciationTitle => '발음해 보기';

  @override
  String get pronunciationHoldToSpeak => '누른 채 말하기';

  @override
  String get pronunciationRecording => '녹음 중… 손을 떼면 판정해요';

  @override
  String get pronunciationAnalyzing => '판정 중…';

  @override
  String get pronunciationRetry => '다시';

  @override
  String get pronunciationReference => '모범 발음';

  @override
  String get pronunciationYours => '내 발음';

  @override
  String pronunciationScore(int score) {
    return '$score점';
  }

  @override
  String get pronunciationVerdictCorrect => '정확해요';

  @override
  String get pronunciationVerdictClose => '거의 맞아요';

  @override
  String get pronunciationVerdictWrong => '어긋났어요';

  @override
  String get pronunciationVerdictUnscored => '판정할 수 없어요';

  @override
  String get pronunciationTooQuiet => '목소리가 감지되지 않았어요. 조용한 곳에서 다시 시도해 주세요';

  @override
  String get pronunciationNoSpeakerRange => '음높이를 인식하지 못했어요. 다시 시도해 주세요';

  @override
  String get pronunciationNoSyllables => '이 예문은 발음 연습을 지원하지 않아요';

  @override
  String get pronunciationMonotone =>
      '음높이가 거의 변하지 않았어요. 모범 발음을 듣고 높낮이를 살려 다시 말해 보세요';

  @override
  String get pronunciationCaptureFailed => '마이크에서 음성을 가져오지 못했어요. 다시 시도해 주세요';

  @override
  String get pronunciationPermissionTitle => '마이크 사용을 허용해 주세요';

  @override
  String get pronunciationPermissionBody =>
      '발음을 판정하기 위해 마이크를 사용해요. 녹음한 음성은 기기 안에서만 처리되며 어디에도 전송되지 않아요.';

  @override
  String get pronunciationPermissionOpenSettings => '설정 열기';

  @override
  String get ttsThaiVoiceMissing =>
      '음성 읽어주기에 태국어 음성이 설치되어 있지 않아요. 음성 데이터를 다운로드하면 모범 발음을 들을 수 있어요.';

  @override
  String get ttsThaiVoiceInstall => '다운로드';

  @override
  String get pronunciationSpeechRecognized => '발음(자음·모음): 알아들을 수 있어요';

  @override
  String get pronunciationSpeechMissing => '발음(자음·모음): 알아듣기 어려워요';

  @override
  String get pronunciationSpeechUnavailable =>
      '현재 발음(자음·모음)을 판정할 수 없어 성조만 확인하고 있어요';

  @override
  String get pronunciationSpeechNoAsset =>
      '이 기기에 태국어 음성 입력이 없어 발음(자음·모음)을 판정할 수 없어요. 성조만 확인하고 있어요';

  @override
  String pronunciationSpeechNoAssetHow(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android': '기기 설정의 음성 입력(기기 내 음성 인식)에 태국어를 추가하면 사용할 수 있어요.',
        'other': '‘설정’ → ‘일반’ → ‘키보드’에서 태국어 키보드를 추가하고 받아쓰기를 켜면 사용할 수 있어요.',
      },
    );
    return '$_temp0';
  }

  @override
  String get pronunciationSpeechAuthDenied =>
      '음성 인식이 허용되지 않아 발음(자음·모음)을 판정할 수 없어요. 성조만 확인하고 있어요';

  @override
  String get pronunciationSpeechAndroid =>
      'Android 13 이전 버전에서는 발음(자음·모음)을 판정할 수 없어요. 성조만 확인하고 있어요';

  @override
  String get pronunciationCoachLead => '다음에는 이 부분을 고쳐 보세요';

  @override
  String get pronunciationCoachShapeMid => '평성은 높이를 바꾸지 않고 평평하게 이어 가세요';

  @override
  String get pronunciationCoachShapeLow => '저성은 낮은 위치에서 조금 내려가는 높이를 유지하세요';

  @override
  String get pronunciationCoachShapeFalling => '하강성은 높은 위치에서 시작해 끝까지 충분히 낮추세요';

  @override
  String get pronunciationCoachShapeHigh => '고성은 올라간 위치에서 멈추지 말고 끝까지 계속 올리세요';

  @override
  String get pronunciationCoachShapeRising => '상승성은 한 번 낮춘 뒤 끝까지 올리세요';

  @override
  String pronunciationCoachStepUp(String tone) {
    return '$tone은 직전 소리보다 높은 위치에서 시작하세요';
  }

  @override
  String pronunciationCoachStepDown(String tone) {
    return '$tone은 직전 소리보다 낮은 위치에서 시작하세요';
  }

  @override
  String pronunciationCoachNotRecognized(String word) {
    return '「$word」을(를) 알아듣지 못했어요. 조금 더 또렷하게 말해 보세요';
  }

  @override
  String pronunciationSegmentUnaspirated(
      String word, String label, String aspirated) {
    return '「$word」의 $label은(는) 숨을 내보내지 않고 소리 내세요. 숨이 새면 $aspirated(으)로 들려요';
  }

  @override
  String pronunciationSegmentFinalP(String word) {
    return '「$word」의 끝은 입술을 닫은 채 멈추세요. 뒤에 ‘으’ 모음을 붙이지 마세요';
  }

  @override
  String pronunciationSegmentFinalT(String word) {
    return '「$word」의 끝은 혀끝을 떼지 않고 멈추세요. 뒤에 ‘으’ 모음을 붙이지 마세요';
  }

  @override
  String pronunciationSegmentFinalK(String word) {
    return '「$word」의 끝은 목 안쪽에서 막아 멈추세요. 뒤에 ‘으’ 모음을 붙이지 마세요';
  }

  @override
  String pronunciationSegmentNgInitial(String word) {
    return '「$word」 첫머리의 ง은 입을 벌린 채 코로 울리세요. 앞에 ‘으’나 ‘ㄴ’을 붙이지 마세요';
  }

  @override
  String pronunciationSegmentFinalNg(String word) {
    return '「$word」의 끝은 입을 벌린 채 코로 울리세요(-ng). 입을 닫으면 다른 단어가 돼요';
  }

  @override
  String pronunciationSegmentFinalN(String word) {
    return '「$word」의 끝은 혀끝을 윗니 뒤에 대세요(-n). 혀 뒤쪽으로 막으면 -ng이 돼요';
  }

  @override
  String pronunciationSegmentFinalM(String word) {
    return '「$word」의 끝은 입술을 닫으세요(-m)';
  }

  @override
  String pronunciationSegmentVowelAe(String word) {
    return '「$word」의 모음은 ‘에’보다 입을 좌우로 더 크게 벌려요(ɛ)';
  }

  @override
  String pronunciationSegmentVowelOe(String word) {
    return '「$word」의 모음은 입을 크게 움직이지 않고 힘을 빼서 소리 내요(ə)';
  }

  @override
  String pronunciationSegmentVowelAw(String word) {
    return '「$word」의 모음은 ‘오’보다 입을 둥글고 크게 벌려요(ɔ)';
  }

  @override
  String pronunciationSegmentVowelUe(String word) {
    return '「$word」의 모음은 입술을 좌우로 편 채 ‘우’ 소리를 내요(ʉ)';
  }

  @override
  String pronunciationSummaryRecognized(int ok, int total) {
    return '$total단어 중 $ok단어를 알아들을 수 있었어요';
  }

  @override
  String pronunciationNextFocus(String word) {
    return '「$word」을(를) 고쳐 봐요';
  }

  @override
  String get pronunciationTierPass => '합격';

  @override
  String get pronunciationTierNative => '태국인 수준';

  @override
  String pronunciationToPass(int points) {
    return '합격까지 $points점';
  }

  @override
  String pronunciationToNative(int points) {
    return '태국인 수준까지 $points점';
  }

  @override
  String pronunciationNativeFirst(int score) {
    return '이 예문에서 처음으로 $score점을 넘었어요';
  }

  @override
  String get pronunciationNativeAgain => '이미 달성한 예문이에요';

  @override
  String get pronunciationCountCorrect => '정확';

  @override
  String get pronunciationCountClose => '아쉬움';

  @override
  String get pronunciationCountWrong => '교정';

  @override
  String get pronunciationTapWordHintDetail =>
      '단어를 누르면 모범 발음과 비교하고 교정 방법을 볼 수 있어요';

  @override
  String get pronunciationListenModelWord => '모범 발음 듣기';

  @override
  String tipWithExample(String content, String example) {
    return '$content\n예: $example';
  }

  @override
  String get errQuizGenerationFailed => '퀴즈를 만들지 못했어요. 다시 시도해 주세요.';

  @override
  String get quotaQuizReached => '오늘의 새 퀴즈는 여기까지예요.';

  @override
  String get quotaSentenceReached =>
      '오늘의 새 예문은 여기까지예요.\n기록에서 이전 예문을 다시 읽을 수 있어요.';

  @override
  String get quotaSentenceUpgradeCta => 'Premium은 예문 무제한';

  @override
  String get errAuth => '인증 오류가 발생했어요. 앱을 다시 시작해 주세요.';

  @override
  String get errNetwork => '네트워크 연결 오류가 발생했어요. 인터넷 연결을 확인해 주세요.';

  @override
  String get errTimeout => '요청 시간이 초과됐어요. 다시 시도해 주세요.';

  @override
  String get errServer => '서버 오류가 발생했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get errSentenceGenerationFailed => '예문을 만들지 못했어요. 다시 시도해 주세요.';

  @override
  String get errLoadFailed => '데이터를 불러오지 못했어요';

  @override
  String get errLoadFailedRetry => '데이터를 불러오지 못했어요. 다시 시도해 주세요.';

  @override
  String errUnexpected(String error) {
    return '예기치 않은 오류가 발생했어요: $error';
  }

  @override
  String get errSignInRequiredForPremium => 'Premium을 이용하려면 로그인해야 해요';

  @override
  String get errProductLoadFailed => '결제 상품 정보를 가져오지 못했어요';

  @override
  String get errPurchaseStartFailed => '구매를 시작하지 못했어요';

  @override
  String errStoreUnavailable(String store) {
    String _temp0 = intl.Intl.selectLogic(
      store,
      {
        'android': 'Google Play에 연결하지 못했어요',
        'other': 'App Store에 연결하지 못했어요',
      },
    );
    return '$_temp0';
  }

  @override
  String get errNothingToRestore => '복원할 수 있는 구매 내역이 없어요';

  @override
  String get errRestoreFailed => '복원하지 못했어요';

  @override
  String get errGoogleSignInFailed => 'Google 로그인에 실패했어요';

  @override
  String get errAppleSignInFailed => 'Apple 로그인에 실패했어요';

  @override
  String get errSignOutFailed => '로그아웃하지 못했어요';

  @override
  String get errDeleteAccountFailed => '계정을 삭제하지 못했어요';

  @override
  String quotaResetInHours(int hours, int minutes) {
    return '다음 초기화까지 $hours시간 $minutes분';
  }

  @override
  String quotaResetInMinutes(int minutes) {
    return '다음 초기화까지 $minutes분';
  }

  @override
  String shareTopic(String value) {
    return '【상황】$value';
  }

  @override
  String shareStyle(String value) {
    return '【문체】$value';
  }

  @override
  String shareEmotion(String value) {
    return '【어조】$value';
  }

  @override
  String shareUsage(String value) {
    return '【사용 상황】$value';
  }

  @override
  String shareCulture(String value) {
    return '【문화적 배경】$value';
  }

  @override
  String get contactSent => '전송했어요. 감사합니다.';

  @override
  String get contactFailed => '전송하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get contactName => '이름(선택)';

  @override
  String get contactEmail => '이메일 주소(선택)';

  @override
  String get contactEmailInvalid => '올바른 이메일 주소를 입력해 주세요';

  @override
  String get contactBody => '의견 및 문의 내용';

  @override
  String get contactBodyRequired => '내용을 입력해 주세요';

  @override
  String get contactSubmit => '보내기';

  @override
  String get contactAnonymousHint =>
      '이메일 주소 없이 보내면 익명으로 전달돼요. 이 경우 답변을 받을 수 없어요.';

  @override
  String get contactSurveyTitle => '설문 참여(1분)';

  @override
  String get contactSurveySubtitle => '앱 개선에 힘을 보태 주세요';

  @override
  String get consonantClassHigh => '고자음';

  @override
  String get consonantClassMiddle => '중자음';

  @override
  String get consonantClassLow => '저자음';

  @override
  String get commonUnknownShort => '알 수 없음';

  @override
  String get toneMarkNone => '성조 부호 없음';

  @override
  String get toneMarkMaiEk => '마이엑';

  @override
  String get toneMarkMaiTho => '마이토';

  @override
  String get toneMarkMaiTri => '마이뜨리';

  @override
  String get toneMarkMaiChattawa => '마이짯따와';

  @override
  String get toneMarkSymbolNone => '없음';

  @override
  String get syllableLive => '생음절';

  @override
  String get syllableDead => '사음절';

  @override
  String get syllableDeadShort => '사음절(단모음)';

  @override
  String get syllableDeadLong => '사음절(장모음·복합 모음)';

  @override
  String get syllableLiveDesc => '장모음 또는 -m, -n, -ng, -y, -w로 끝남';

  @override
  String get syllableDeadDesc => '종성 없이 단모음으로 끝나거나 -p, -t, -k로 끝남';

  @override
  String get toneMid => '평성';

  @override
  String get toneLow => '저성';

  @override
  String get toneFalling => '하강성';

  @override
  String get toneHigh => '고성';

  @override
  String get toneRising => '상승성';

  @override
  String get toneAnalyzerEmptyWord => '단어가 비어 있어요';

  @override
  String get toneDialogTitle => '성조 해설';

  @override
  String get toneSyllableBreakdown => '음절 분석';

  @override
  String toneSyllableNumber(int number) {
    return '음절 $number';
  }

  @override
  String get toneMainConsonant => '첫 자음';

  @override
  String get toneSyllableType => '음절 유형';

  @override
  String get toneResultPrefix => '결과: ';

  @override
  String get toneMarkLabel => '성조 부호';

  @override
  String get toneMarkPrefix => '성조 부호: ';

  @override
  String get toneResultTone => '결과 성조';

  @override
  String toneShiftFor(String consonantClass) {
    return '$consonantClass 성조 변화';
  }

  @override
  String toneShiftTableFor(String consonantClass) {
    return '$consonantClass 성조 변화표';
  }

  @override
  String get toneRareUsage => '예외적인 용법(현대에는 드묾)';

  @override
  String get toneAppliedRule => '= 이 단어에 적용된 규칙';

  @override
  String get toneLearnMore => '성조 자세히 알아보기';

  @override
  String toneExamplePrefix(String value) {
    return '예: $value';
  }

  @override
  String get toneGuideOfferTitle => '성조가 어렵다고 답했다면';

  @override
  String get toneGuideOfferBody => '다섯 가지 성조와 성조가 정해지는 원리를 그림으로 확인할 수 있어요';

  @override
  String get vocabRetestOfferTitle => '다시 만나 반가워요';

  @override
  String get vocabRetestOfferBody =>
      '한동안 쉬었으니 어휘 테스트로 현재 어휘량을 다시 측정해 볼까요? 예문 난이도가 현재 수준에 맞게 조정돼요.';

  @override
  String get toneGuideTitle => '태국어 성조 가이드';

  @override
  String get toneGuideHeading => '태국어 성조';

  @override
  String get toneGuideIntro =>
      '태국어에는 다섯 가지 성조가 있으며, 철자가 같아도 성조에 따라 뜻이 달라져요. 성조는 자음 문자의 종류(고·중·저), 성조 부호, 음절 유형에 따라 정해져요.';

  @override
  String get toneGuideFiveTones => '다섯 가지 성조';

  @override
  String get toneGuideConsonantClasses => '자음 등급';

  @override
  String get toneGuideToneMarks => '성조 부호';

  @override
  String get toneGuideSyllableTypes => '음절 유형';

  @override
  String get toneGuideShiftTable => '성조 변화표';

  @override
  String get toneGuideShiftTableIntro =>
      '자음 등급별로 성조 부호와 음절 유형의 조합에 따라 정해지는 성조를 보여 줘요.';

  @override
  String toneGuideLetterCount(int count) {
    return '$count자';
  }

  @override
  String get toneMidDesc => '음높이가 평평하게 유지되는 성조예요.';

  @override
  String get toneMidExample => 'กา (gaa) 까마귀';

  @override
  String get toneLowDesc => '낮은 음에서 시작해 조금 내려가는 성조예요.';

  @override
  String get toneLowExample => 'ก่า (gàa) 갈랑갈';

  @override
  String get toneFallingDesc => '높은 음에서 낮게 떨어지는 성조예요.';

  @override
  String get toneFallingExample => 'ก้า (gâa) 걸음';

  @override
  String get toneHighDesc => '높은 음에서 시작해 더 올라가는 성조예요.';

  @override
  String get toneHighExample => 'ก๊า (gáa) ~야(종결 표현)';

  @override
  String get toneRisingDesc => '낮은 음에서 높은 음으로 올라가는 성조예요.';

  @override
  String get toneRisingExample => 'ก๋า (gǎa) ~네(종결 표현)';

  @override
  String get toneMarkMaiEkDesc => '제1성조 부호예요. 자음 등급에 따라 다른 성조가 돼요.';

  @override
  String get toneMarkMaiThoDesc => '제2성조 부호예요. 자음 등급에 따라 다른 성조가 돼요.';

  @override
  String get toneMarkMaiTriDesc => '제3성조 부호예요. 중자음에 쓰며 저자음·고자음에서는 예외적으로 쓰여요.';

  @override
  String get toneMarkMaiChattawaDesc =>
      '제4성조 부호예요. 중자음에 쓰며 저자음·고자음에서는 예외적으로 쓰여요.';

  @override
  String get tipCatVowel => '모음';

  @override
  String get tipCatCulture => '문화';

  @override
  String get tipCatTone => '성조';

  @override
  String get tipCatConsonant => '자음';

  @override
  String get tipCatNumber => '숫자';

  @override
  String get tipCatDaily => '일상 표현';

  @override
  String get tipCatStudy => '학습 팁';

  @override
  String get tipCatGrammar => '문법';

  @override
  String get tipCatPronunciation => '발음';

  @override
  String get tipCatScript => '문자';

  @override
  String tipWordExample(String thai, String reading, String meaning) {
    return '$thai($reading=$meaning)';
  }

  @override
  String tipGrammarExample(String thai, String meaning) {
    return '$thai($meaning)';
  }

  @override
  String get tip_vowelUea_title => 'เอือ (ʉa)';

  @override
  String get tip_vowelUea_content => 'เอือ는 한국어에 없는 모음으로 ‘ʉa’라고 표기해요.';

  @override
  String get tip_vowelUea_example => 'เมือง(mʉʉang=도시·나라)';

  @override
  String get tip_vowelIa_title => 'เอีย (ia)';

  @override
  String get tip_vowelIa_content => 'เอีย는 ‘ia’예요. i에서 a로 부드럽게 이어 주세요.';

  @override
  String get tip_vowelIa_example => 'เรียน(riian=배우다)';

  @override
  String get tip_vowelUa_title => 'อัว (ua)';

  @override
  String get tip_vowelUa_content => 'อัว는 ‘ua’예요. u에서 a로 부드럽게 이어 주세요.';

  @override
  String get tip_vowelUa_example => 'ตัว(tuua=몸·마리)';

  @override
  String get tip_vowelAw_title => 'เอา (aw)';

  @override
  String get tip_vowelAw_content => 'เอา는 ‘aw’예요. 입을 벌렸다가 오므려요.';

  @override
  String get tip_vowelAw_example => 'เอา(aw=원하다·집다)';

  @override
  String get tip_vowelAi_title => 'ไอ / ใอ (ai)';

  @override
  String get tip_vowelAi_content => 'ไอ와 ใอ는 모두 ‘ai’로 발음해요. ใ를 쓰는 단어는 20개뿐이에요.';

  @override
  String get tip_vowelAi_example => 'ไป(pai=가다) / ใจ(jai=마음)';

  @override
  String get tip_cultureWai_title => 'wâi(합장 인사·ไหว้)';

  @override
  String get tip_cultureWai_content =>
      '두 손을 모으는 태국식 인사예요. 윗사람에게는 코 높이, 또래에게는 가슴 높이에서 해요.';

  @override
  String get tip_cultureTemple_title => '사원 방문 예절';

  @override
  String get tip_cultureTemple_content =>
      '사원에서는 신발을 벗고 어깨와 무릎을 가리는 옷을 입어요. 불상보다 높은 곳에 앉지 마세요.';

  @override
  String get tip_cultureSongkran_title => 'sǒngkraan(물 축제)';

  @override
  String get tip_cultureSongkran_content =>
      '매년 4월 13~15일에 열리는 태국 설날 축제예요. 서로 물을 뿌리며 새해를 축하해요.';

  @override
  String get tip_cultureLoyKrathong_title => 'lɔɔi krathong(등불 띄우기)';

  @override
  String get tip_cultureLoyKrathong_content =>
      '음력 12월 보름에 강에 등불을 띄우는 축제예요. 물의 정령에게 감사를 전해요.';

  @override
  String get tip_cultureEating_title => '태국 음식 먹는 법';

  @override
  String get tip_cultureEating_content =>
      '포크와 숟가락을 사용하고 숟가락으로 음식을 먹어요. 젓가락은 면 요리를 먹을 때만 써요.';

  @override
  String get tip_cultureMaiPenRai_title => 'ไม่เป็นไร(mâi pen rai)';

  @override
  String get tip_cultureMaiPenRai_content =>
      '‘신경 쓰지 마세요·괜찮아요’라는 뜻으로, 태국인의 관용적인 태도를 보여 주는 대표 표현이에요.';

  @override
  String get tip_toneMistake_title => '성조를 틀리면…';

  @override
  String get tip_toneMistake_content =>
      'สวย(sǔuai=아름답다)와 ซวย(suuai=운이 나쁘다)처럼 성조에 따라 뜻이 크게 달라져요.';

  @override
  String get tip_toneRelative_title => '성조는 상대적인 음높이';

  @override
  String get tip_toneRelative_content =>
      '성조의 높이는 앞 음절에 따라 달라져요. 구절 단위로 익히는 것이 효과적이에요.';

  @override
  String get tip_consonant44_title => '태국어의 자음 문자 44개';

  @override
  String get tip_consonant44_content =>
      '44개가 있지만 현재 쓰이는 문자는 42개예요. 발음은 21가지로 모여요.';

  @override
  String get tip_consonantHigh_title => '고자음(àksɔ̌ɔn sǔung)';

  @override
  String get tip_consonantHigh_content =>
      'ข ฃ ข ฉ ฐ ถ ผ ฝ ศ ษ ส ห의 11개예요. 성조 규칙이 중자음·저자음과 달라요.';

  @override
  String get tip_consonantMid_title => '중자음(àksɔ̌ɔn klaang)';

  @override
  String get tip_consonantMid_content =>
      'ก จ ฎ ฏ ด ต บ ป อ의 9개예요. 성조 부호가 그대로 반영되는 기본 그룹이에요.';

  @override
  String get tip_consonantLow_title => '저자음(àksɔ̌ɔn tàm)';

  @override
  String get tip_consonantLow_content =>
      '나머지 24개가 저자음이에요. 대응하는 고자음이 있는 ‘짝자음’과 ‘단독 자음’으로 나뉘어요.';

  @override
  String get tip_consonantSilent_title => '묵음 부호 ์(kaa-ran)';

  @override
  String get tip_consonantSilent_content =>
      '문자 위에 붙는 ์는 ‘이 자음은 읽지 않는다’는 부호예요. 외래어에 많이 쓰여요.';

  @override
  String get tip_consonantSilent_example => 'จันทร์(jan=달) ← ร์는 읽지 않음';

  @override
  String get tip_consonantCluster_title => '자음군(àksɔ̌ɔn khûap)';

  @override
  String get tip_consonantCluster_content =>
      '자음이 두 개 연속되면 함께 발음해요. kr, kl, pr, pl 같은 형태가 있어요.';

  @override
  String get tip_consonantCluster_example => 'กรุง(krung=도시) / ปลา(plaa=물고기)';

  @override
  String get tip_numberThai_title => '태국 숫자';

  @override
  String get tip_numberThai_content =>
      '태국에는 고유한 숫자가 있어요. ๐๑๒๓๔๕๖๗๘๙(0~9)이며 간판이나 공문서에 쓰여요.';

  @override
  String get tip_number1to5_title => '1~5 읽는 법';

  @override
  String get tip_number1to5_content =>
      '๑ nʉ̀ng, ๒ sɔ̌ɔng, ๓ sǎam, ๔ sìi, ๕ hâa';

  @override
  String get tip_number6to10_title => '6~10 읽는 법';

  @override
  String get tip_number6to10_content => '๖ hòk, ๗ jèt, ๘ pɛ̀ɛt, ๙ kâw, ๑๐ sìp';

  @override
  String get tip_number11and21_title => '11과 21의 특별한 읽는 법';

  @override
  String get tip_number11and21_content =>
      '11은 sìp èt, 21은 yîi sìp èt이에요. 일의 자리 1과 십의 자리 2를 특별하게 읽어요.';

  @override
  String get tip_numberBig_title => '백·천·만 단위';

  @override
  String get tip_numberBig_content =>
      'rɔ́ɔi(백), phan(천), mʉ̀ʉn(만), sǎen(십만), láan(백만)';

  @override
  String get tip_numberPrice_title => '가격 묻는 법';

  @override
  String get tip_numberPrice_content =>
      '‘얼마예요?’는 thâo rài예요. raakhaa(가격)와 함께 익혀 보세요.';

  @override
  String get tip_numberPrice_example => 'an-níi thâo rài(이거 얼마예요?)';

  @override
  String get tip_dailyHello_title => 'สวัสดี(sà-wàt-dii)';

  @override
  String get tip_dailyHello_content =>
      '‘안녕하세요.’ 아침, 낮, 저녁 언제나 쓸 수 있는 만능 인사예요. 헤어질 때도 써요.';

  @override
  String get tip_dailyThanks_title => 'ขอบคุณ(khɔ̀ɔp khun)';

  @override
  String get tip_dailyThanks_content =>
      '‘고마워요.’ khɔ̀ɔp khun mâak은 ‘정말 고마워요’라는 뜻이에요.';

  @override
  String get tip_dailySorry_title => 'ขอโทษ(khɔ̌ɔ thôot)';

  @override
  String get tip_dailySorry_content => '‘죄송해요·미안해요.’ 사과하거나 사람을 부를 때 쓸 수 있어요.';

  @override
  String get tip_dailyYesNo_title => 'ใช่ / ไม่ใช่(châi / mâi châi)';

  @override
  String get tip_dailyYesNo_content => '‘네 / 아니요.’ 확인 질문에 답할 때 써요.';

  @override
  String get tip_dailyYesNo_example => 'châi mǎi(그런가요?) → châi khráp(네)';

  @override
  String get tip_dailyEat_title => 'กิน(kin)=먹다';

  @override
  String get tip_dailyEat_content =>
      '‘밥 먹었어요?’라는 뜻의 kin khâao rʉ̌ʉ yang은 태국의 대표적인 인사예요.';

  @override
  String get tip_dailyDelicious_title => 'อร่อย(à-ròi)=맛있다';

  @override
  String get tip_dailyDelicious_content =>
      '태국 음식을 먹었다면 à-ròi! mâak을 붙이면 ‘정말 맛있다’가 돼요.';

  @override
  String get tip_dailyPronouns_title => '인칭대명사 구분하기';

  @override
  String get tip_dailyPronouns_content =>
      'phǒm(저)은 남성, dì-chǎn(저)은 여성이 쓰는 격식 있는 1인칭이에요.';

  @override
  String get tip_dailyPronouns_example => '편한 사이에서는 rao나 chǎn도 써요';

  @override
  String get tip_studyThaiOnly_title => '태국어만 보고 퀴즈 풀기';

  @override
  String get tip_studyThaiOnly_content =>
      '예문이나 해설 없이 태국어만 보고 뜻을 알 수 있는지 퀴즈로 도전해 보세요!';

  @override
  String get errPurchaseStatusFailed => '구매 상태를 가져오지 못했어요';

  @override
  String get errPurchaseGeneric => '구매 오류가 발생했어요';

  @override
  String get purchasePending => '구매 승인을 기다리고 있어요. 승인되면 반영돼요';

  @override
  String get errSignInBeforePurchase => '로그인한 후 구매해 주세요';

  @override
  String get errPurchaseVerificationFailed => '구매를 확인하지 못했어요';

  @override
  String get settingsVocabTest => '어휘력 측정';

  @override
  String get settingsVocabTestNever => '아직 응시하지 않았어요';

  @override
  String settingsVocabTestLast(String date) {
    return '최근 $date';
  }

  @override
  String get settingsVocabTestPremium => 'Premium 전용';

  @override
  String get vocabTestTitle => '어휘력 측정';

  @override
  String get vocabTestIntroBody =>
      '태국어 단어의 뜻을 4지선다로 답해 현재 어휘량을 측정해요. 모르는 단어가 연이어 나오면 종료돼요. 빠르면 6문제로 끝나며, 어휘량이 많을수록 더 오래 걸려요.';

  @override
  String get vocabTestIntroNote =>
      '결과는 예문과 퀴즈 난이도에 반영돼요. 설정 화면에서 한 달에 한 번 다시 응시할 수 있어요.';

  @override
  String get vocabTestStart => '시작';

  @override
  String get vocabTestQuestion => '이 단어의 뜻은?';

  @override
  String get vocabTestDontKnow => '모르겠어요';

  @override
  String vocabTestProgress(int current) {
    return '$current번 문제';
  }

  @override
  String get vocabTestResultTitle => '현재 어휘량';

  @override
  String vocabTestResultVocab(int vocab) {
    return '약 $vocab단어';
  }

  @override
  String get vocabTestResultBody =>
      '이 결과를 출발점으로 예문과 퀴즈의 난이도를 맞춰요. 앱을 사용하면서 실제 정답과 오답에 따라 조금씩 조정돼요.';

  @override
  String vocabTestResultFreeCap(int vocab) {
    return '무료 요금제에서는 어휘 점수와 예문 난이도가 100단어까지예요. 이후 학습에서는 점수가 100이 되며 더 올라가지 않아요. Premium에서는 측정된 $vocab단어부터 시작할 수 있어요.';
  }

  @override
  String get vocabTestResultClose => '닫기';

  @override
  String get vocabTestError => '어휘 테스트를 실행하지 못했어요';

  @override
  String get vocabTestRetry => '다시 하기';

  @override
  String get rankingTitle => '어휘 랭킹';

  @override
  String get rankingSubtitle => '어휘 점수로 다른 학습자와 비교';

  @override
  String rankingBandScope(String band) {
    return '$band 내 순위';
  }

  @override
  String get rankingYourRank => '내 순위';

  @override
  String rankingPosition(int rank) {
    return '$rank위';
  }

  @override
  String get rankingCapTiedNote => '상한에 도달한 사용자가 많아 순위가 매겨지지 않아요';

  @override
  String get rankingUnrankedHint => '예문을 만들면 순위가 매겨져요';

  @override
  String get rankingLoadFailed => '랭킹을 불러오지 못했어요';

  @override
  String get rankingYou => '나';

  @override
  String get rankingDistributionTitle => '어휘 점수 분포';

  @override
  String get rankingDistributionSubtitle => '구간별 인원이며 색으로 표시된 곳이 내 위치예요';

  @override
  String rankingPercentile(int percent) {
    return '상위 $percent%';
  }

  @override
  String rankingBandOver(int min) {
    return '$min~';
  }

  @override
  String rankingBandRange(int min, int max) {
    return '$min~$max';
  }

  @override
  String rankingAnonymousName(String suffix) {
    return '사용자$suffix';
  }

  @override
  String rankingFreeCapNote(int limit) {
    return '무료 요금제의 어휘 점수는 $limit단어가 상한이에요';
  }

  @override
  String get settingsRanking => '랭킹';

  @override
  String get settingsRankingSubtitle => '어휘 점수로 다른 학습자와 비교';

  @override
  String get guideTitle => '사용법 가이드';

  @override
  String get guideSettingsSubtitle => '앱 사용법 한눈에 보기';

  @override
  String get guideSkip => '건너뛰기';

  @override
  String get guideStart => '어휘력 측정';

  @override
  String get guideClose => '닫기';

  @override
  String get guideLead => '기본 사용법을 정리했어요. 설정에서 언제든 다시 볼 수 있어요.';

  @override
  String get guideFigureLoopSentence => '예문';

  @override
  String get guideFigureLoopQuiz => '퀴즈';

  @override
  String get guideFigureLoopRepeat => '반복';

  @override
  String get guideFigureLoopSummary => '종합 퀴즈';

  @override
  String get guideFigureLoopEvery => '예문 최대 5개마다';

  @override
  String get guideFigureCardThai => '태국 문자';

  @override
  String get guideFigureCardPronunciation => '읽는 법';

  @override
  String get guideFigureCardTranslation => '한국어 번역';

  @override
  String get guideFigureCardTranslationSample => '저는 커피를 좋아해요';

  @override
  String get guideFigureCardTargetWord => '금색=학습 단어';

  @override
  String get guideChapterOverview => '개요';

  @override
  String get guideChapterRoles => '각 기능의 역할';

  @override
  String get guideChapterHowTo => '사용 방법';

  @override
  String get guideOverviewTitle => '이 앱에서 학습하는 것';

  @override
  String get guideOverviewBody1 =>
      'AI가 내 수준에 맞는 학습 단어를 고르고, 그 단어를 사용한 태국어 예문을 만들어요.';

  @override
  String get guideOverviewBody2 =>
      '예문으로 학습 단어 익히기 → 확인 퀴즈로 점검하기. 이 과정을 최대 5번 반복하면 한 세트예요.';

  @override
  String get guideOverviewSummaryQuiz =>
      '한 세트를 모두 학습하면 ‘종합 퀴즈’로 넘어가요. 헷갈릴 때는 힌트를 보거나 예문을 다시 확인할 수 있어요.';

  @override
  String get guideOverviewBody3 =>
      '종합 퀴즈 답변을 바탕으로 어휘 점수와 다음 예문의 난이도가 조정되고, 예문에 나오는 단어도 늘어나요. 힌트 없이 맞힌 답은 더 잘 반영되며, 틀린 문제는 나중에 다시 출제돼요.';

  @override
  String get guideRoleSentenceTitle => '예문';

  @override
  String get guideRoleSentenceBody =>
      '상세 화면에서 단어 사용법을 확인할 수 있어요. 사용하는 상황과 함께 익히면 더 오래 기억할 수 있어요.';

  @override
  String get guideRoleSoundTitle => '발음 연습';

  @override
  String get guideRoleSoundBody =>
      '내 발음과 성조를 모범 발음과 비교할 수 있어요. 태국어는 성조에 따라 뜻이 달라져요.';

  @override
  String get guideRoleQuizTitle => '퀴즈';

  @override
  String get guideRoleQuizCheck => '확인 퀴즈: 예문마다 학습 단어의 뜻을 선택해요.';

  @override
  String get guideRoleQuizSummary => '종합 퀴즈: 예문 최대 5개마다 밑줄에 들어갈 단어를 선택해요.';

  @override
  String get guideRoleQuizSpelling =>
      '철자 퀴즈: 어휘 측정 결과가 100단어 미만일 때 나와요. 학습 단어의 발음과 뜻을 보고 올바른 철자를 선택해요. 한 번 맞힌 단어는 이후 빈칸 채우기나 순서 맞추기 등 다른 형식으로 출제돼요. 틀렸을 때는 ‘태국 문자 자세히 알아보기’에서 태국 문자 가이드를 열 수 있어요.';

  @override
  String get guideRoleScoreTitle => '어휘 점수';

  @override
  String get guideRoleScoreBody => '어휘 측정 테스트와 종합 퀴즈 결과로 추정한 현재 어휘량이에요.';

  @override
  String get guideRoleVocabTestTitle => '어휘 측정 테스트';

  @override
  String get guideRoleVocabTestBody =>
      '4지선다로 현재 어휘량을 측정해 예문과 퀴즈의 난이도를 정해요. 설정에서 한 달에 한 번 다시 응시할 수 있어요.';

  @override
  String get guideRoleRankingTitle => '랭킹';

  @override
  String get guideRoleRankingBody =>
      '어휘 점수에 따른 순위를 확인할 수 있어요. 표시 이름은 자동으로 지정돼요.';

  @override
  String get guideRoleTopicTitle => '주제';

  @override
  String get guideRoleTopicBody => '축제·사원 예절·BL 드라마 등을 통해 태국어와 문화를 배울 수 있어요.';

  @override
  String get guideRoleNotificationTitle => '학습 알림';

  @override
  String get guideRoleNotificationBody =>
      '정해진 시간에 새 예문 세트가 도착해요. 한동안 앱을 열지 않으면 알림 간격이 조금씩 넓어지다가 결국 멈춰요. 앱을 열면 다시 매일 알림이 와요.';

  @override
  String get guideRolePremiumTitle => '무료 버전과 Premium';

  @override
  String get guideRolePremiumBody =>
      '무료 버전으로도 매일 학습할 수 있어요. Premium에서는 예문 수, 주제 선택, 어휘 점수의 한도가 늘어나요.';

  @override
  String get guidePlanColItem => '항목';

  @override
  String get guidePlanColFree => '무료 버전';

  @override
  String get guidePlanColPremium => 'Premium';

  @override
  String get guidePlanRowSentences => '하루 예문';

  @override
  String get guidePlanRowTopic => '주제';

  @override
  String get guidePlanRowVocab => '어휘 점수 상한';

  @override
  String get guidePlanSentencesUnlimited => '무제한';

  @override
  String guidePlanSentences(int count) {
    return '$count세트';
  }

  @override
  String get guidePlanTopicFree => '자동 선택';

  @override
  String get guidePlanTopicPremium => '직접 선택';

  @override
  String guidePlanVocabFree(int count) {
    return '$count단어';
  }

  @override
  String guidePlanVocabPremium(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '약 $countString단어';
  }

  @override
  String get guideHowSentenceTitle => '오늘의 예문 읽기';

  @override
  String get guideHowSentenceStep1 =>
      '학습 탭에 그날의 예문이 표시돼요. 예문은 최대 5개가 한 세트예요. 위쪽에서 진도를 확인할 수 있어요.';

  @override
  String get guideHowSentenceStep3 => '금색 단어가 학습 단어예요. 퀴즈에서 이 단어가 출제돼요.';

  @override
  String get guideHowSentenceStep4 => '예문 카드를 누르면 상세 화면이 열려요.';

  @override
  String get guideHowDetailTitle => '상세 화면';

  @override
  String get guideHowDetailLead =>
      '상세 화면에서는 예문의 상황, 문체, 철자, 성조를 확인할 수 있어요. 여러 단서와 연결해 익히면 단어가 더 오래 기억에 남아요.';

  @override
  String get guideHowSoundTitle => '듣고 소리 내기';

  @override
  String get guideHowSoundStep1 => '‘모범 발음 듣기’를 누르면 예문이 반복 재생돼요.';

  @override
  String get guideHowSoundStep2 =>
      '상세 화면의 ‘발음 연습’에서 ‘누른 채 말하기’를 길게 누르고, 표시된 발음을 보며 예문을 소리 내어 말해요. 태국 문자를 아직 읽지 못해도 괜찮아요. 그 자리에서 성조를 판정할 수 있어요.';

  @override
  String get guideHowSoundStep3 =>
      '각 단어의 성조가 맞으면 초록색, 거의 맞으면 주황색, 다르면 빨간색으로 표시돼요. 단어를 누르면 모범 발음과의 음높이 차이와 교정 방법을 확인할 수 있어요.';

  @override
  String get guideHowQuizTitle => '확인 퀴즈 풀기';

  @override
  String get guideHowQuizStep1 => '예문 아래의 ‘외웠는지 확인’에서 확인 퀴즈로 이동해요.';

  @override
  String get guideHowQuizStep2 => '바로 앞 예문에 있는 금색 단어의 뜻을 4지선다로 선택해요.';

  @override
  String get guideHowQuizStep3 => '답변 후 단어의 뜻과 사용법을 확인할 수 있어요.';

  @override
  String get guideHowQuizStep4 =>
      '결과 화면에서 다음 예문으로 이동해요. 세트의 마지막 예문 다음에는 ‘종합 퀴즈’가 나와요.';

  @override
  String get guideHowReviewQuizTitle => '종합 퀴즈 풀기';

  @override
  String get guideHowReviewQuizStep1 =>
      '한 세트(최대 5개)의 예문을 학습할 때마다 이미 학습한 예문에서 빈칸 채우기 문제가 나와요.';

  @override
  String get guideHowReviewQuizStep2 =>
      '종합 퀴즈에서는 전날, 3일 전, 일주일 전 등에 학습한 예문을 일정한 간격으로 복습해요. 아직 익히지 못한 학습 단어의 문제가 우선 출제돼요.';

  @override
  String get guideHowReviewQuizStep3 =>
      '힌트는 첫 번째에 발음, 두 번째에 번역이 나와요. 힌트 없이 맞히면 어휘 점수가 더 잘 올라요.';

  @override
  String get guideHowReviewQuizStep4 => '헷갈리면 ‘예문 확인’으로 예문을 다시 볼 수 있어요.';

  @override
  String get guideHowReviewQuizStep5 => '답변을 바탕으로 어휘 점수와 다음 예문의 난이도가 조정돼요.';

  @override
  String get guideHowNotifyTitle => '알림 설정하기';

  @override
  String get guideHowNotifyStep1 =>
      '설정의 \'매일 예문 알림\'에서 알림 시간을 확인할 수 있어요. 스위치로 켜고 끄고, 시간을 탭하면 바꿀 수 있어요.';

  @override
  String get guideHowNotifyStep2 =>
      '무료 버전은 하루 1번, Premium은 하루 3번까지 설정할 수 있어요. 알림마다 새 예문 세트가 도착해요.';

  @override
  String get guideHowNotifyStep3 => '알림을 열지 않아도, 앱을 열면 도착한 예문 세트가 학습 탭에 표시돼요.';

  @override
  String get guideHowNotifyStep4 => '다음 알림 전까지 하나도 읽지 않은 예문 세트는 새 세트로 교체돼요.';

  @override
  String get guideHowNotifyStep5 =>
      '알림이 오지 않으면 기기 설정에서 알림이 허용되어 있는지 확인해 주세요. 무료 버전에서는 알림 전에 그날의 예문 세트를 모두 학습한 날에는 알림이 오지 않아요.';

  @override
  String get guideHowSettingsTitle => '설정에서 할 수 있는 것';

  @override
  String get guideHowSettingsStep1 => '알림 시간, 표시 글꼴, 번역과 해설 언어를 변경할 수 있어요.';

  @override
  String get guideHowSettingsStep2 => '다음 예문의 주제를 선택하고 랭킹을 열 수도 있어요.';

  @override
  String get guideHowSettingsStep3 => '이 가이드는 설정의 ‘사용법 가이드’에서 언제든 열 수 있어요.';

  @override
  String get guideChapterTips => '학습 팁';

  @override
  String get guideTipsTitle => '꾸준히 학습하는 팁';

  @override
  String get guideTipsRepeat =>
      '퀴즈는 틀려도 괜찮아요. 예문 전체를 외우지 않아도 학습 단어를 여러 번 보다 보면 자연스럽게 어휘가 늘어요.';

  @override
  String get guideTipsScript =>
      '태국 문자는 먼저 단어 전체의 모양을 익히는 것만으로도 충분해요. 눈에 익으면 자음, 모음, 성조 부호를 조금씩 구별해 보세요.';

  @override
  String get guideTipsSpeak =>
      '외운 단어나 예문을 대화에서 사용해 보세요. 소리 내어 말할수록 더 잘 익힐 수 있어요.';

  @override
  String get settingsWordOrderGuide => '어순 가이드';

  @override
  String get settingsWordOrderGuideSubtitle => '태국어 단어 배열 알아보기';

  @override
  String get wordOrderLearnMore => '어순 자세히 알아보기';

  @override
  String get thaiScriptLearnMore => '태국 문자 자세히 알아보기';

  @override
  String get wordOrderGuideTitle => '태국어 어순 가이드';

  @override
  String get wordOrderGuideHeading => '태국어 어순 규칙';

  @override
  String get wordOrderGuideIntro =>
      '순서 맞추기 문제에서 헷갈릴 때 참고하세요. 태국어는 화제를 먼저 제시하고, 동사는 목적어 앞에, 수식하는 말은 뒤에 놓는 것이 기본이에요.';

  @override
  String get wordOrderRule1Title => '화제(~은/는)를 문장 맨 앞에 놓기';

  @override
  String get wordOrderRule1Body =>
      '무엇에 관해 말할지 먼저 제시한 뒤 설명해요. 한국어의 ‘~은/는’과 비슷한 배열이에요. 장소나 นี้·นั้น(이·그)이 붙은 명사가 화제가 되기 쉬워요.';

  @override
  String get wordOrderRule2Title => '특정한 대상을 화제로 삼아 앞에 놓기';

  @override
  String get wordOrderRule2Body =>
      'นี้·นั้น으로 특정한, 이미 대화에 나온 대상은 문장 앞에 놓고 ‘그것에 관해’ 설명하기도 해요.';

  @override
  String get wordOrderRule3Title => '화제 다음은 ‘누가 → 하다 → 무엇을’';

  @override
  String get wordOrderRule3Body => '동사는 목적어보다 앞에 와요. 한국어와 반대예요.';

  @override
  String get wordOrderRule4Title => '명사를 꾸미는 말은 뒤에';

  @override
  String get wordOrderRule4Body => '형용사는 명사 뒤에 와요. ‘~의’도 소유자가 뒤에 와요.';

  @override
  String get wordOrderRule5Title => '세거나 가리킬 때는 ‘명사 → 수 → 분류사 → 이’';

  @override
  String get wordOrderRule5Body =>
      '수는 명사 뒤에 분류사(세는 단위)와 함께 붙어요. ‘이’는 그보다 더 뒤에 와요.';

  @override
  String get wordOrderRule6Title => '부정어 ไม่는 부정할 말 앞에';

  @override
  String get wordOrderRule6Body => 'ไม่는 부정할 말 바로 앞에 놓아요.';

  @override
  String get wordOrderRule7Title => '의문사는 답이 들어갈 자리에 그대로 놓기';

  @override
  String get wordOrderRule7Body =>
      '의문사는 답이 들어갈 자리에 그대로 놓아요. 단, ทำไม(왜)는 문장 맨 앞에도 자주 와요. 예·아니요 질문은 서술어 뒤에 ไหม를 붙여요(공손한 종결 표현은 그보다 더 뒤에 와요).';

  @override
  String get wordOrderRule8Title => '시제를 나타내는 말(จะ·แล้ว 등)';

  @override
  String get wordOrderRule8Body =>
      'จะ(~할 것이다)·กำลัง(~하고 있다)·เคย(~한 적이 있다)는 동사 앞에 와요. แล้ว(이미 ~했다)는 동사와 목적어 뒤에 와요.';

  @override
  String get wordOrderRule9Title => '시간 표현은 문장 앞이나 끝, 장소는 동사 뒤';

  @override
  String get wordOrderRule9Body => '시간 표현은 문장 맨 앞이나 끝에 와요. 장소는 동사 뒤에 놓아요.';

  @override
  String get wordOrderRule10Title => '공손한 종결 표현은 맨 끝에';

  @override
  String get wordOrderRule10Body =>
      '남성은 ครับ을 써요. 여성은 보통 ค่ะ, 질문에서는 คะ를 써요. ไหม·แล้ว 또는 นะ(~네요)·เลย·ด้วย 같은 문말 표현보다도 뒤에 붙어요. นะ 뒤의 여성 종결 표현은 คะ(นะคะ)예요.';

  @override
  String get wordOrderTipsTitle => '순서 맞추기 팁';

  @override
  String get wordOrderTipsBody =>
      '장소나 ‘이 〇〇’가 문장 전체의 화제라면 맨 앞에 놓기\n동작·상태를 나타내는 말을 찾기. ‘누가’는 그 앞, ‘무엇을’과 ‘어디로’는 그 뒤\n수식하는 말·수·นี้·มาก은 수식받는 말 뒤\nกับ·ใน 등은 명사 앞, อยาก·ต้อง은 동사 앞\nไหม·แล้ว·นะ·ครับ/ค่ะ/คะ는 문장 끝부분';

  @override
  String get wordOrderEx1aGloss => '투어|이|사람|많다';

  @override
  String get wordOrderEx1aMeaning => '이 투어는 사람이 많다';

  @override
  String get wordOrderEx1bGloss => '공항|사람|많다';

  @override
  String get wordOrderEx1bMeaning => '공항은 사람이 많다';

  @override
  String get wordOrderRule1Note =>
      '화제와 같은 대상을 뒤에서 ‘그들’ 등으로 다시 말하지 않는 것이 자연스러워요.';

  @override
  String get wordOrderEx2aGloss => '보고서|이|내일|사용하다|가능하다|?';

  @override
  String get wordOrderEx2aMeaning => '이 보고서, 내일 쓸 수 있어?';

  @override
  String get wordOrderEx3aGloss => '나|먹다|밥';

  @override
  String get wordOrderEx3aMeaning => '나는 밥을 먹는다';

  @override
  String get wordOrderRule3Note => '분명히 알 수 있는 ‘누가’와 ‘무엇을’은 자주 생략돼요.';

  @override
  String get wordOrderEx4aGloss => '집|크다';

  @override
  String get wordOrderEx4aMeaning => '큰 집';

  @override
  String get wordOrderEx4bGloss => '집|~의|나';

  @override
  String get wordOrderEx4bMeaning => '내 집';

  @override
  String get wordOrderRule4Note =>
      'บ้านใหญ่는 ‘집이 크다’라는 문장도 될 수 있어요. 형용사가 그대로 서술어가 되므로 เป็น은 필요하지 않아요. ของ은 생략하기도 해요.';

  @override
  String get wordOrderEx5aGloss => '고양이|2|마리';

  @override
  String get wordOrderEx5aMeaning => '고양이 2마리';

  @override
  String get wordOrderEx5bGloss => '고양이|2|마리|이';

  @override
  String get wordOrderEx5bMeaning => '이 고양이 2마리';

  @override
  String get wordOrderEx6aGloss => '나|~않다|먹다|맵다';

  @override
  String get wordOrderEx6aMeaning => '나는 매운 것을 먹지 않는다';

  @override
  String get wordOrderEx6bGloss => '나|~하지 않았다|가다';

  @override
  String get wordOrderEx6bMeaning => '나는 가지 않았다';

  @override
  String get wordOrderEx6cGloss => '가다|할 수 없다';

  @override
  String get wordOrderEx6cMeaning => '갈 수 없다';

  @override
  String get wordOrderRule6Note =>
      'ไม่ได้+동사는 ‘실제로 ~하지 않았다·하고 있지 않다’라는 뜻이에요. ‘~할 수 없다’의 ไม่ได้는 동사 뒤에 와요.';

  @override
  String get wordOrderEx7aGloss => '너|먹다|무엇';

  @override
  String get wordOrderEx7aMeaning => '무엇을 먹어?';

  @override
  String get wordOrderEx7bGloss => '가다|어디';

  @override
  String get wordOrderEx7bMeaning => '어디에 가?';

  @override
  String get wordOrderEx7cGloss => '먹다|?';

  @override
  String get wordOrderEx7cMeaning => '먹어?';

  @override
  String get wordOrderEx8aGloss => '나|~할 예정이다|가다';

  @override
  String get wordOrderEx8aMeaning => '나는 갈 거예요';

  @override
  String get wordOrderEx8bGloss => '먹다|밥|이미 ~했다';

  @override
  String get wordOrderEx8bMeaning => '이미 밥을 먹었다';

  @override
  String get wordOrderEx9aGloss => '내일|나|~할 예정이다|가다|치앙마이';

  @override
  String get wordOrderEx9aMeaning => '내일 치앙마이에 갈 거예요';

  @override
  String get wordOrderEx9bGloss => '나|일하다|~에서|방콕';

  @override
  String get wordOrderEx9bMeaning => '저는 방콕에서 일해요';

  @override
  String get wordOrderEx10aGloss => '먹다|?|공손함(여성)';

  @override
  String get wordOrderEx10aMeaning => '먹어요?';

  @override
  String get wordOrderEx10bGloss => '먹다|이미 ~했다|공손함(여성)';

  @override
  String get wordOrderEx10bMeaning => '이미 먹었어요';

  @override
  String get wordOrderRule5Note =>
      'แมวตัวหนึ่ง처럼 분류사 뒤에 หนึ่ง을 놓으면 ‘어떤 고양이 한 마리’라는 뜻이 돼요.';

  @override
  String get wordOrderEx10cGloss => '맛있다|~네요|공손함(여성)';

  @override
  String get wordOrderEx10cMeaning => '맛있네요';

  @override
  String get wordOrderRule11Title => '문장으로 꾸밀 때는 ‘명사 → ที่ → 설명’';

  @override
  String get wordOrderRule11Body =>
      '‘내가 좋아하는 가게’처럼 문장으로 명사를 꾸밀 때도 설명은 뒤에 와요. 명사 뒤에 ที่를 놓고 그 뒤에 설명을 잇는 것이 기본이에요.';

  @override
  String get wordOrderEx11aGloss => '가게|(연결어)|나|좋아하다';

  @override
  String get wordOrderEx11aMeaning => '내가 좋아하는 가게';

  @override
  String get wordOrderRule12Title => '‘~와/과’, ‘~위에’ 등은 명사 앞에';

  @override
  String get wordOrderRule12Body =>
      'กับ(~와/과)·ใน(~안에서)·บน(~위에)·ให้(~에게)·ที่(~에서)는 명사 앞에 놓아요. 한국어의 조사 ‘~와/과’, ‘~에서’와 반대예요.';

  @override
  String get wordOrderEx12aGloss => '나|가다|~와/과|친구';

  @override
  String get wordOrderEx12aMeaning => '나는 친구와 간다';

  @override
  String get wordOrderEx12bGloss => '고양이|있다|~위에|책상';

  @override
  String get wordOrderEx12bMeaning => '고양이는 책상 위에 있다';

  @override
  String get wordOrderRule13Title => '‘매우’, ‘조금’은 뒤에';

  @override
  String get wordOrderRule13Body =>
      'มาก(매우)·จริงๆ(정말)·นิดหน่อย(조금)은 형용사나 동사 뒤에 놓아요. 한국어와 반대예요.';

  @override
  String get wordOrderEx13aGloss => '요리|이|맛있다|매우';

  @override
  String get wordOrderEx13aMeaning => '이 요리는 매우 맛있다';

  @override
  String get wordOrderRule14Title => '비교할 때는 ‘형용사 → กว่า → 비교 대상’';

  @override
  String get wordOrderRule14Body =>
      '‘A는 B보다 ~하다’는 ‘A+형용사+กว่า+B’로 말해요. ‘가장 ~하다’는 형용사 뒤에 ที่สุด을 붙여요.';

  @override
  String get wordOrderEx14aGloss => '오늘|덥다|~보다|어제';

  @override
  String get wordOrderEx14aMeaning => '오늘은 어제보다 덥다';

  @override
  String get wordOrderEx14bGloss => '것|이|좋다|가장';

  @override
  String get wordOrderEx14bMeaning => '이것이 가장 좋다';

  @override
  String get wordOrderRule15Title => '‘~하고 싶다’는 동사 앞, ‘할 수 있다’는 뒤';

  @override
  String get wordOrderRule15Body =>
      'อยาก(~하고 싶다)·ต้อง(~해야 한다)·ควร(~하는 게 좋다)는 동사 앞에 와요. ได้(할 수 있다)는 동사와 목적어 뒤에 와요.';

  @override
  String get wordOrderEx15aGloss => '나|~하고 싶다|먹다|쏨땀';

  @override
  String get wordOrderEx15aMeaning => '나는 쏨땀을 먹고 싶다';

  @override
  String get wordOrderEx15bGloss => '나|말하다|태국어|할 수 있다';

  @override
  String get wordOrderEx15bMeaning => '나는 태국어를 말할 수 있다';

  @override
  String get wordOrderRule16Title => '동사는 이어서 나란히 놓기';

  @override
  String get wordOrderRule16Body =>
      '동사를 이어 놓으면 목적(ไป + ซื้อ + ของ)·순서(อาบน้ำ + นอน)·방법(เดิน + กลับ + บ้าน)을 나타낼 수 있어요. 기본적으로 의미의 흐름에 따라 배열해요.';

  @override
  String get wordOrderEx16aGloss => '나|가다|사다|물건';

  @override
  String get wordOrderEx16aMeaning => '나는 쇼핑하러 간다';

  @override
  String get wordOrderEx16bGloss => '집다|물|오다';

  @override
  String get wordOrderEx16bMeaning => '물을 가져오다';

  @override
  String get wordOrderEx16cGloss => '걷다|돌아가다|집';

  @override
  String get wordOrderEx16cMeaning => '걸어서 집에 돌아가다';

  @override
  String get wordOrderRule17Title => '뒤의 동사로 결과·계속을 나타내기';

  @override
  String get wordOrderRule17Body =>
      '동사 뒤에 หมด(모두 ~하다)·เสร็จ(~을 마치다)를 놓으면 동작의 결과를 나타내요. ต่อ(계속하다)는 그 동작을 이어 간다는 뜻이에요.';

  @override
  String get wordOrderEx17aGloss => '먹다|다 없어지다';

  @override
  String get wordOrderEx17aMeaning => '전부 먹다';

  @override
  String get wordOrderEx17bGloss => '먹다|끝내다';

  @override
  String get wordOrderEx17bMeaning => '다 먹다';

  @override
  String get wordOrderEx17cGloss => '먹다|계속하다';

  @override
  String get wordOrderEx17cMeaning => '계속 먹다';

  @override
  String get wordOrderRule18Title => '같은 동사를 반복하기(ๆ)';

  @override
  String get wordOrderRule18Body =>
      'ๆ는 바로 앞말을 반복하는 기호예요. 동사를 겹치면 가볍게(ลองๆ ดู)·~했다 ~했다(เดินๆ หยุดๆ)·별생각 없이 또는 잠시(ดูๆ ไปก่อน)라는 뜻을 나타낼 수 있어요.';

  @override
  String get wordOrderEx18aGloss => '가볍게 시도하다|보다';

  @override
  String get wordOrderEx18aMeaning => '가볍게 한번 해 보다';

  @override
  String get wordOrderEx18bGloss => '걷기도 하다|멈추기도 하다';

  @override
  String get wordOrderEx18bMeaning => '걷다가 멈추기를 반복하다';

  @override
  String get wordOrderEx18cGloss => '잠시 지켜보다|이어 가다|우선';

  @override
  String get wordOrderEx18cMeaning => '일단 지켜보다';

  @override
  String get wordOrderRule18Note =>
      '동사 외의 말도 겹쳐 써요. เร็วๆ(빨리)·บ่อยๆ(자주), 명사인 เด็กๆ(아이들) 등이 있어요.';

  @override
  String get thaiScriptGuideTitle => '태국 문자 가이드';

  @override
  String get thaiScriptGuideHeading => '태국 문자를 구성 요소로 나누어 읽기';

  @override
  String get thaiScriptGuideIntro =>
      '처음부터 모두 외우지 않아도 괜찮아요. 자주 나오는 자음과 모음부터 단어 속에서 찾아보세요. 카드를 누르면 소리를 들을 수 있어요.';

  @override
  String get thaiScriptBasicsTitle => '1. 태국 문자의 구조';

  @override
  String get thaiScriptBasicsBody =>
      '한 음절은 주로 자음자+모음 기호+성조 기호로 이루어져요. 받침 자음이 붙기도 해요.';

  @override
  String get thaiScriptBasicsDirection =>
      '글은 왼쪽에서 오른쪽으로 읽어요. 영어처럼 단어마다 띄어 쓰지 않고 문장이나 의미 단위 사이를 띄어요.';

  @override
  String get thaiScriptBasicsVowelPosition =>
      '모음 기호는 자음의 뒤뿐 아니라 앞·위·아래 또는 자음을 둘러싸는 위치에 붙어요. 쓰인 순서와 소리 순서는 항상 같지 않아요.';

  @override
  String get thaiScriptConsonantsTitle => '2. 자주 쓰는 자음';

  @override
  String get thaiScriptConsonantsBody =>
      '큰 글자는 자음자이고 그 아래는 글자 이름이에요. ‘첫소리’는 음절 처음, ‘끝소리’는 마지막에 올 때의 소리예요. 고·중·저자음 분류는 성조를 정하는 단서예요. 카드를 눌러 글자 이름을 들어 보세요.';

  @override
  String get thaiScriptConsonantCarrierNote =>
      'อ는 소리가 없는 자음이에요. 모음만 있는 소리를 쓸 때 모음 기호를 붙이는 받침대가 돼요 (อา = aa, อิ = i).';

  @override
  String thaiScriptConsonantSounds(String initial, String finalSound) {
    return '첫소리 $initial · 끝소리 $finalSound';
  }

  @override
  String get thaiScriptVowelsTitle => '3. 모음 기호의 위치와 길이';

  @override
  String get thaiScriptVowelsBody =>
      'อ를 자음 대신 받침대로 삼아 기호의 위치를 봐요. 모음에는 짧은소리와 긴소리가 있으며 길이가 달라지면 다른 단어가 돼요.';

  @override
  String get thaiScriptVowelPositions => '자음 앞|자음 뒤|자음 위|자음 아래|자음을 둘러쌈';

  @override
  String get thaiScriptVowelPairsTitle => '짧은 모음과 긴 모음';

  @override
  String get thaiScriptVowelPairsBody =>
      '읽기에 같은 모음이 두 번 쓰이면 길게 늘여요. 짧은 형태에는 ะ가 붙거나 단어 안에서 모양이 달라지기도 해요.';

  @override
  String get thaiScriptToneMarksTitle => '4. 성조 기호';

  @override
  String get thaiScriptToneMarksBody =>
      '자음 위에 붙는 네 가지 기호예요. 기호 하나가 음의 오르내림을 직접 나타내는 것이 아니라 자음 분류와의 조합으로 성조가 정해져요.';

  @override
  String get thaiScriptToneRule =>
      '성조는 자음 분류(고·중·저)×성조 기호×음절 종류(모음 길이·받침 자음)로 정해져요. 기호가 없는 음절에도 성조가 있어요.';

  @override
  String get thaiScriptOpenToneGuide => '성조 규칙 자세히 보기';

  @override
  String get thaiScriptToneGuideNote =>
      '우선 성조 기호를 찾을 수 있으면 충분해요. 조합표는 성조 가이드에서 확인할 수 있어요.';

  @override
  String get thaiScriptWordsTitle => '5. 실제 단어를 나누어 읽기';

  @override
  String get thaiScriptWordsBody =>
      '적힌 순서만 보지 말고 자음·모음·성조 기호를 찾아보세요. 같은 색 카드는 같은 역할이에요. 단어를 누르면 소리를 들을 수 있어요.';

  @override
  String get thaiScriptWordMeanings => '~않다|좋다|우리·나|먹다|오다';

  @override
  String get thaiScriptConsonantLabel => '자음';

  @override
  String get thaiScriptFinalConsonantLabel => '받침 자음';

  @override
  String get thaiScriptVowelLabel => '모음';

  @override
  String get thaiScriptToneMarkLabel => '성조 기호';

  @override
  String get pronGuideTitle => '태국어 발음 가이드';

  @override
  String get pronGuideHeading => '태국어 발음의 핵심';

  @override
  String get pronGuideIntro =>
      '앱의 발음 표기는 로마자에 기호를 더한 방식이에요. 한국어에 없는 소리의 차이를 발음 기호와 함께 익혀 보세요. 성조는 ‘성조 가이드’에서 설명해요.';

  @override
  String get pronSymbolsTitle => '발음 기호';

  @override
  String get pronSymbolsBody => '한국에서 일반적으로 쓰는 로마자 표기와 다른 기호만 모았어요.';

  @override
  String get pronSymbolsDescs =>
      'ɛ는 ‘에’보다 입을 크게 벌린 소리, ɔ는 ‘오’보다 입을 둥글고 크게 벌린 소리|입술을 좌우로 편 채 내는 ‘우’ 소리|입을 반쯤 벌리고 힘을 빼서 내는 ‘으’와 ‘어’ 사이의 소리|같은 모음이 두 번 이어지면 길게 늘이기|k는 숨을 거의 내보내지 않는 ‘ㄲ’에 가까운 소리, kh는 숨을 세게 내보내는 ‘ㅋ’ 소리|h가 붙으면 숨을 세게 내보내기. t·p는 숨을 내보내지 않기|코로 울리는 ‘ㅇ’ 받침 소리. 단어 첫머리에도 옴|성조. 기호가 없으면 평평하게, à는 낮게, â는 내려가게, á는 높게, ǎ는 올라가게';

  @override
  String get pronAspTitle => '숨을 내보내는 소리와 내보내지 않는 소리';

  @override
  String get pronAspBody =>
      'kh·th·ph·ch는 숨을 세게 내보내고, k·t·p·j는 숨을 거의 내보내지 않아요. 한국어의 거센소리와 된소리 차이에 가깝지만 완전히 같지는 않으며, 태국어에서는 서로 다른 단어가 돼요.';

  @override
  String get pronAspMeanings => '닭|달걀|눈|칠하다|던지다|데려가다';

  @override
  String get pronAspNote =>
      '입 앞에 손을 대고 말해 보세요. kh·th·ph에서는 바람이 느껴지고 k·t·p에서는 거의 느껴지지 않으면 잘 구별한 거예요.';

  @override
  String get pronLengthTitle => '장모음과 단모음';

  @override
  String get pronLengthBody =>
      'aa·ii처럼 같은 모음이 두 번 이어진 표기는 길게 늘여요. 길이만 달라도 서로 다른 단어가 돼요.';

  @override
  String get pronLengthMeanings => '들어가다|밥|그|하얗다';

  @override
  String get pronVowelTitle => '비슷한 모음 구별하기';

  @override
  String get pronVowelBody =>
      'e와 ɛ, o와 ɔ, u와 ʉ는 한국어로 옮기면 비슷하게 들릴 수 있어요. ɛ·ɔ는 입을 크게 벌리고, ʉ는 입술을 둥글게 하지 않고 발음해요.';

  @override
  String get pronVowelMeanings => '아이|햇볕|책상|방|보다|손|돈|걷다';

  @override
  String get pronFinalTitle => '어말 k·t·p는 소리를 터뜨리지 않기';

  @override
  String get pronFinalBody =>
      '어말의 k·t·p는 조음 위치에서 막은 채 끝내고 뒤에 ‘으’ 모음을 붙이지 않아요. n과 ng도 구별해요.';

  @override
  String get pronFinalMeanings => '새|차|~와/과|접시|얇다';

  @override
  String get pronFinalNote => '태국 문자에서는 어말의 ด·ส·ช 등도 t, บ·พ 등도 p 소리가 돼요.';

  @override
  String get pronCasualTitle => '회화에서 달라지는 발음';

  @override
  String get pronCasualBody =>
      '회화에서는 표기된 발음과 다르게 말하는 경우가 많아요. r이 l로 바뀌거나, 자음이 두 개 이어질 때 뒤 자음이 탈락하거나, 성조가 바뀌기도 해요.';

  @override
  String get pronCasualMeanings => '사랑하다|공손함(남성)|~인가요?|나(여성)';

  @override
  String get pronCasualNote =>
      '줄어든 발음 형태를 알면 듣기에 도움이 돼요. 말할 때는 표기된 대로 발음해도 통해요.';

  @override
  String get guideRoleQuizWordOrder =>
      '순서 맞추기 퀴즈: 종합 퀴즈의 일부로 예문에 있는 네 단어를 올바른 순서로 배열해요. 답변 후 ‘어순 자세히 알아보기’에서 어순 가이드를 열 수 있어요.';

  @override
  String get guideHowSettingsGuides =>
      '‘태국 문자 가이드’, ‘발음 가이드’, ‘성조 가이드’, ‘어순 가이드’에서 문자·발음·성조·어순 규칙을 다시 볼 수 있어요.';

  @override
  String streakChipDays(int count) {
    return '$count일';
  }

  @override
  String get streakChipStart => '오늘부터';

  @override
  String streakTitle(int count) {
    return '예문 $count일 연속';
  }

  @override
  String get streakRestart => '1개 만들면 다시 시작';

  @override
  String get streakStart => '오늘 예문 하나로 기록을 시작해요';

  @override
  String streakBest(int count) {
    return '최장 $count일';
  }

  @override
  String streakNextMilestone(int count, int target) {
    return '$target일까지 $count일 남음';
  }

  @override
  String get streakToday => '오늘';

  @override
  String get streakWeekdayLetters => '월화수목금토일';

  @override
  String get firstStepsTitle => '학습 순서';

  @override
  String get firstStepsListenSentence => '예문 음성 듣기';

  @override
  String get firstStepsListenSentenceHint => '예문 아래의 ‘모범 발음 듣기’를 눌러요';

  @override
  String get firstStepsOpenDetail => '예문 카드를 눌러 ‘상세’ 보기';

  @override
  String get firstStepsOpenDetailHint => '발음 연습과 단어별 성조를 볼 수 있어요';

  @override
  String get firstStepsQuiz => '확인 퀴즈 풀기';

  @override
  String get firstStepsQuizHint => '한 문제로 익혔는지 확인해요';

  @override
  String get firstStepsQuizStart => '풀기';

  @override
  String get detailGuideTitle => '이 화면에서 할 수 있어요';

  @override
  String get detailGuidePractice => '발음 연습하기';

  @override
  String get detailGuidePracticeHint => '모범 발음을 듣고 녹음하면 성조가 맞는지 확인해요';

  @override
  String get detailGuideWords => '단어를 눌러 성조 규칙 보기';

  @override
  String get detailGuideWordsHint => '글자 조합으로 이 성조가 되는 이유를 설명해요';

  @override
  String get detailGuideUsage => '사용법 읽기';

  @override
  String get detailGuideUsageHint => '어떤 상황에서 누구에게 쓰는지 알 수 있어요';

  @override
  String get detailGuideBackToQuiz => '학습으로 돌아가 확인 퀴즈 풀기';
}
