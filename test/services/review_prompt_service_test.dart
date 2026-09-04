import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/services/review_prompt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_review_prompt');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<ReviewPromptService> service({
    TargetPlatform platform = TargetPlatform.iOS,
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return ReviewPromptService(
      channel: channel,
      preferences: preferences,
      platform: platform,
      now: () => now ?? DateTime(2026),
    );
  }

  test('skips until enough quiz completions and total answers exist', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    final reviewPromptService = await service();

    for (var i = 0; i < 3; i++) {
      final outcome = await reviewPromptService.maybeRequestAfterQuizCompleted(
        sessionCorrect: 5,
        sessionTotal: 5,
        totalAnswered: 5,
      );

      expect(outcome, ReviewPromptOutcome.skippedNotEnoughExperience);
    }

    expect(calls, isEmpty);
  });

  test('requests on iOS after the second strong quiz completion', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getAppVersion':
          return '1.2.1+0';
        case 'requestReview':
          return true;
      }
      return null;
    });

    final reviewPromptService = await service();
    await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 5,
      sessionTotal: 5,
      totalAnswered: 5,
    );

    final outcome = await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 4,
      sessionTotal: 5,
      totalAnswered: 10,
    );

    expect(outcome, ReviewPromptOutcome.requested);
    expect(calls, ['getAppVersion', 'requestReview']);
  });

  test('does not request twice for the same app version', () async {
    SharedPreferences.setMockInitialValues({});
    var requestCount = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAppVersion':
          return '1.2.1+0';
        case 'requestReview':
          requestCount++;
          return true;
      }
      return null;
    });

    final reviewPromptService = await service();
    await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 5,
      sessionTotal: 5,
      totalAnswered: 5,
    );
    expect(
      await reviewPromptService.maybeRequestAfterQuizCompleted(
        sessionCorrect: 4,
        sessionTotal: 5,
        totalAnswered: 10,
      ),
      ReviewPromptOutcome.requested,
    );

    expect(
      await reviewPromptService.maybeRequestAfterQuizCompleted(
        sessionCorrect: 5,
        sessionTotal: 5,
        totalAnswered: 25,
      ),
      ReviewPromptOutcome.skippedAlreadyRequestedThisVersion,
    );
    expect(requestCount, 1);
  });

  test('skips low scoring quiz completions', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    final reviewPromptService = await service();
    await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 5,
      sessionTotal: 5,
      totalAnswered: 5,
    );

    final outcome = await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 3,
      sessionTotal: 5,
      totalAnswered: 10,
    );

    expect(outcome, ReviewPromptOutcome.skippedLowSessionScore);
    expect(calls, isEmpty);
  });

  test('keeps Android as unsupported for future Play review work', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    final reviewPromptService = await service(platform: TargetPlatform.android);

    final outcome = await reviewPromptService.maybeRequestAfterQuizCompleted(
      sessionCorrect: 5,
      sessionTotal: 5,
      totalAnswered: 20,
    );

    expect(outcome, ReviewPromptOutcome.skippedUnsupportedPlatform);
    expect(calls, isEmpty);
  });

  test('does not request from sentence generation on the first day', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    final reviewPromptService = await service(now: DateTime(2026, 9, 1));

    for (var i = 0; i < 20; i++) {
      expect(
        await reviewPromptService.maybeRequestAfterSentenceGenerated(),
        ReviewPromptOutcome.skippedNotEnoughExperience,
      );
    }

    expect(calls, isEmpty);
  });

  test('requests from sentence generation after use across days', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getAppVersion':
          return '1.2.1+0';
        case 'requestReview':
          return true;
      }
      return null;
    });

    // 3日に分けて、3回ずつ生成する。
    for (final day in [1, 2]) {
      final s = await service(now: DateTime(2026, 9, day));
      for (var i = 0; i < 3; i++) {
        expect(
          await s.maybeRequestAfterSentenceGenerated(),
          ReviewPromptOutcome.skippedNotEnoughExperience,
        );
      }
    }

    final third = await service(now: DateTime(2026, 9, 3));
    expect(
      await third.maybeRequestAfterSentenceGenerated(),
      ReviewPromptOutcome.skippedNotEnoughExperience,
    );
    expect(
      await third.maybeRequestAfterSentenceGenerated(),
      ReviewPromptOutcome.requested,
    );
    expect(calls, ['getAppVersion', 'requestReview']);
  });

  test('shares the version guard across quiz and sentence paths', () async {
    SharedPreferences.setMockInitialValues({});
    var requestCount = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAppVersion':
          return '1.2.1+0';
        case 'requestReview':
          requestCount++;
          return true;
      }
      return null;
    });

    for (final day in [1, 2]) {
      final s = await service(now: DateTime(2026, 9, day));
      for (var i = 0; i < 4; i++) {
        await s.maybeRequestAfterSentenceGenerated();
      }
    }
    final third = await service(now: DateTime(2026, 9, 3));
    expect(
      await third.maybeRequestAfterSentenceGenerated(),
      ReviewPromptOutcome.requested,
    );

    // 同一バージョンではクイズ経路からも重ねて依頼しない。
    await third.maybeRequestAfterQuizCompleted(
      sessionCorrect: 5,
      sessionTotal: 5,
      totalAnswered: 5,
    );
    expect(
      await third.maybeRequestAfterQuizCompleted(
        sessionCorrect: 5,
        sessionTotal: 5,
        totalAnswered: 20,
      ),
      ReviewPromptOutcome.skippedAlreadyRequestedThisVersion,
    );
    expect(requestCount, 1);
  });
}
