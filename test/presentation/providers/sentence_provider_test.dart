import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/sentence_repository.dart';
import 'package:thai_memo/domain/delete_sentence_usecase.dart';
import 'package:thai_memo/domain/generate_sentence_usecase.dart';
import 'package:thai_memo/domain/get_sentences_usecase.dart';
import 'package:thai_memo/presentation/providers/sentence_provider.dart';

import '../../helpers/fake_firebase.dart';

class _FakeSentenceRepository extends Fake implements SentenceRepository {}

ThaiSentence _sentence() => ThaiSentence(
      id: 'sentence-1',
      thaiText: 'สวัสดี',
      pronunciation: 'sawatdi',
      japaneseTranslation: 'こんにちは',
      wordBreakdowns: const [],
    );

void main() {
  late String tier;
  late bool trialActive;
  late Map<String, String?>? capturedParams;
  late FakeAnalyticsService analytics;

  SentenceController createController({
    Future<ThaiSentence> Function({Map<String, String?> generationParams})?
        generate,
    Future<ThaiSentence?> Function()? getMostRecent,
  }) {
    final repo = _FakeSentenceRepository();
    return SentenceController(
      GenerateSentenceUseCase(repo),
      GetSentencesUseCase(repo),
      DeleteSentenceUseCase(repo),
      analytics,
      () => tier,
      () => '旅行',
      () => trialActive,
      () => lookupL10n(const Locale('ja')),
      generateSentence: generate ??
          ({Map<String, String?> generationParams = const {}}) async {
            capturedParams = generationParams;
            return _sentence();
          },
      getMostRecentSentence: getMostRecent ?? () async => null,
    );
  }

  setUp(() {
    tier = 'free';
    trialActive = false;
    capturedParams = null;
    analytics = FakeAnalyticsService();
  });

  test('freeでもトライアル中ならtopicを維持してpremium_trialを送る', () async {
    trialActive = true;
    final controller = createController();

    await controller.generateSentence(
      generationParams: const {'topic': '旅行', 'style': '丁寧'},
    );

    expect(capturedParams, {
      'topic': '旅行',
      'style': '丁寧',
      'premium_trial': 'true',
    });
    expect(controller.state, isA<SentenceStateSuccess>());
  });

  test('freeかつトライアルなしならtopicを送らない', () async {
    final controller = createController();

    await controller.generateSentence(
      generationParams: const {'topic': '旅行', 'style': '丁寧'},
    );

    expect(capturedParams, {'style': '丁寧'});
  });

  test('premiumならtopicを維持しpremium_trialは送らない', () async {
    tier = 'premium';
    final controller = createController();

    await controller.generateSentence(
      generationParams: const {'topic': '旅行', 'style': '丁寧'},
    );

    expect(capturedParams, {'topic': '旅行', 'style': '丁寧'});
  });

  group('analytics', () {
    test('トライアル生成はtier=freeでもtopicを記録する', () async {
      trialActive = true;
      final controller = createController();

      await controller.generateSentence(
        generationParams: const {'topic': '旅行'},
      );

      expect(analytics.generateSentenceEvents.single, {
        'tier': 'free',
        'topic': '旅行',
        'source': 'manual_single',
        'count': 1,
      });
    });

    test('トライアルなしのfree生成はtopicを記録しない', () async {
      final controller = createController();

      await controller.generateSentence(
        generationParams: const {'topic': '旅行'},
      );

      expect(analytics.generateSentenceEvents.single['topic'], isNull);
    });
  });

  // 当初のバグ（自動生成経路だけ tier フィルタを通らず topic が落ちる）の回帰テスト
  group('loadOrGenerateToday', () {
    test('未生成のfreeユーザーはtopicを送らずdaily_autoで記録する', () async {
      final controller = createController();

      await controller.loadOrGenerateToday(
        dailySentenceGenerated: false,
        generationParams: const {'topic': '旅行', 'style': '丁寧'},
      );

      expect(capturedParams, {'style': '丁寧'});
      expect(analytics.generateSentenceEvents.single['source'], 'daily_auto');
      expect(controller.state, isA<SentenceStateSuccess>());
    });

    test('未生成のpremiumユーザーは設定のtopicを反映する', () async {
      tier = 'premium';
      final controller = createController();

      await controller.loadOrGenerateToday(
        dailySentenceGenerated: false,
        generationParams: const {'topic': '旅行'},
      );

      expect(capturedParams, {'topic': '旅行'});
    });

    test('未生成のトライアル中ユーザーはtopic維持＋premium_trialを送る', () async {
      trialActive = true;
      final controller = createController();

      await controller.loadOrGenerateToday(
        dailySentenceGenerated: false,
        generationParams: const {'topic': '旅行'},
      );

      expect(capturedParams, {'topic': '旅行', 'premium_trial': 'true'});
      });

    test('生成済みなら最新を表示し生成しない', () async {
      final controller = createController(
        getMostRecent: () async => _sentence(),
      );

      await controller.loadOrGenerateToday(
        dailySentenceGenerated: true,
        generationParams: const {'topic': '旅行'},
      );

      expect(capturedParams, isNull);
      expect(analytics.generateSentenceEvents, isEmpty);
      expect(controller.state, isA<SentenceStateSuccess>());
    });

    test('生成済みでもローカルDBが空なら生成にフォールバックする', () async {
      final controller = createController();

      await controller.loadOrGenerateToday(
        dailySentenceGenerated: true,
        generationParams: const {'topic': '旅行'},
      );

      expect(capturedParams, isNotNull);
    });

    test('生成失敗時は既存の最新例文を表示する', () async {
      final controller = createController(
        generate: ({Map<String, String?> generationParams = const {}}) async {
          throw StateError('boom');
        },
        getMostRecent: () async => _sentence(),
      );

      await controller.loadOrGenerateToday(dailySentenceGenerated: false);

      expect(controller.state, isA<SentenceStateSuccess>());
    });

    test('生成失敗かつ既存例文もなければ空状態になる', () async {
      final controller = createController(
        generate: ({Map<String, String?> generationParams = const {}}) async {
          throw StateError('boom');
        },
      );

      await controller.loadOrGenerateToday(dailySentenceGenerated: false);

      expect(controller.state, isA<SentenceStateEmpty>());
    });
  });
}
