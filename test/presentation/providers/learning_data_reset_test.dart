import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/domain/delete_sentence_usecase.dart';
import 'package:thai_memo/domain/generate_sentence_usecase.dart';
import 'package:thai_memo/domain/get_sentences_usecase.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/providers/learning_data_reset_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';
import 'package:thai_memo/services/daily_set_progress_store.dart';

import '../../helpers/fake_firebase.dart';

final _sentence = ThaiSentence(
    id: 's',
    thaiText: 'ไทย',
    pronunciation: 'thai',
    japaneseTranslation: 'タイ',
    wordBreakdowns: const []);
const _question = QuizQuestion(
    sentenceId: 's',
    thaiText: 'ไทย',
    blankText: '_____',
    correctAnswer: 'ไทย',
    choices: ['ไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
    pronunciation: 'thai',
    explanation: 'タイ');

class _Repo extends Fake implements SentenceRepository {
  @override
  Future<ThaiSentence?> getSentenceById(String id) async => _sentence;
}

class _Db extends Fake implements DatabaseHelper {}

class _Api extends Fake implements BackendApiService {
  Completer<void>? gate;
  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    await gate?.future;
    return [_question];
  }
}

class _Cloud extends DailySetProgressStore {
  @override
  Future<DailySetRef?> fetchLatestDeliveredSet() async => null;

  Completer<void>? gate;
  DailySetProgressSnapshot remote = const DailySetProgressSnapshot();
  @override
  Future<DailySetProgressSnapshot?> merge(
      DailySetProgressSnapshot local) async {
    await gate?.future;
    return remote = mergeDailySetProgress(remote, local);
  }

  @override
  Future<ThaiSentence?> fetchSentence(String id) async => _sentence;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Cloud cloud;
  late _Api api;
  late bool databaseDeleted;
  late bool failRemote;
  late int resetCalls;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'kept_until_success': true,
      'vocab_stats_user-1_ja': '{}',
      'vocab_stats_other-user_ja': '{}',
    });
    cloud = _Cloud();
    api = _Api();
    databaseDeleted = false;
    failRemote = false;
    resetCalls = 0;
    final repo = _Repo();
    final analytics = FakeAnalyticsService();
    container = ProviderContainer(overrides: [
      sentenceRepositoryProvider.overrideWithValue(repo),
      dailySetProgressStoreProvider.overrideWithValue(cloud),
      sentenceControllerProvider.overrideWith((ref) => SentenceController(
            GenerateSentenceUseCase(repo),
            GetSentencesUseCase(repo),
            DeleteSentenceUseCase(repo),
            analytics,
            () => 'free',
            () => null,
            () => false,
            () => lookupL10n(const Locale('ja')),
          )),
      quizControllerProvider.overrideWith((ref) => QuizController(
          api, analytics, () => lookupL10n(const Locale('ja')),
          databaseHelper: _Db(),
          progressStore: ref.read(learningProgressStoreProvider))),
      learningDataResetProvider.overrideWith((ref) => LearningDataReset(
            ref,
            resetRemote: () async {
              resetCalls++;
              if (failRemote) throw StateError('offline');
              cloud.remote = const DailySetProgressSnapshot();
            },
            deleteDatabase: () async {
              databaseDeleted = true;
            },
            currentUid: () => 'user-1',
          )),
    ]);
  });
  tearDown(() => container.dispose());

  test('同期と事前生成を待ってからリセットし、保存・表示・クラウドを空にする', () async {
    cloud.gate = Completer<void>();
    api.gate = Completer<void>();
    final sets = container.read(dailySetProvider.notifier);
    final quiz = container.read(quizControllerProvider.notifier);
    container.read(sentenceControllerProvider.notifier).showSentence(_sentence);
    await sets.start([_sentence]);
    final preparation = quiz.prepareQuiz(_sentence);
    final resetter = container.read(learningDataResetProvider);
    final reset = resetter.reset();
    expect(identical(reset, resetter.reset()), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(resetCalls, 0);
    cloud.gate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(resetCalls, 0);
    api.gate!.complete();
    await preparation;
    await reset;
    expect(resetCalls, 1);
    expect(databaseDeleted, isTrue);
    expect(container.read(dailySetProvider).isActive, isFalse);
    expect(
        container.read(sentenceControllerProvider), isA<SentenceStateEmpty>());
    expect(container.read(quizControllerProvider), isA<QuizInitial>());
    expect(quiz.hasQuizFor('s'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('kept_until_success'), isTrue);
    expect(prefs.containsKey('vocab_stats_user-1_ja'), isFalse);
    expect(prefs.containsKey('vocab_stats_other-user_ja'), isTrue);
    await sets.syncFromCloud();
    expect(cloud.remote.active, isNull);
    expect(container.read(dailySetProvider).isActive, isFalse);
  });

  test('サーバー失敗時は端末データと表示を保持し、同期を再開できる', () async {
    failRemote = true;
    final sets = container.read(dailySetProvider.notifier);
    await sets.start([_sentence]);
    await sets.settled;
    container.read(sentenceControllerProvider.notifier).showSentence(_sentence);
    await expectLater(
        container.read(learningDataResetProvider).reset(), throwsStateError);
    expect(databaseDeleted, isFalse);
    expect(container.read(dailySetProvider).current?.id, 's');
    expect(container.read(sentenceControllerProvider),
        isA<SentenceStateSuccess>());
    expect(
        (await SharedPreferences.getInstance()).getBool('kept_until_success'),
        isTrue);
    cloud.remote = const DailySetProgressSnapshot();
    await sets.syncFromCloud();
    expect(cloud.remote.active?.setId, 's');
  });

  test('アカウント削除後の端末掃除ではリセットAPIを呼ばない', () async {
    await container.read(learningDataResetProvider).clearLocal();
    expect(databaseDeleted, isTrue);
    expect(resetCalls, 0);
    expect(
        container.read(sentenceControllerProvider), isA<SentenceStateEmpty>());
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('サインアウト時は対象ユーザーの学習キャッシュだけを消し、端末設定を残す', () async {
    await container.read(learningDataResetProvider).clearUserLocal('user-1');
    final prefs = await SharedPreferences.getInstance();
    expect(databaseDeleted, isTrue);
    expect(resetCalls, 0);
    expect(prefs.getBool('kept_until_success'), isTrue);
    expect(prefs.containsKey('vocab_stats_user-1_ja'), isFalse);
    expect(prefs.containsKey('vocab_stats_other-user_ja'), isTrue);
  });
}
