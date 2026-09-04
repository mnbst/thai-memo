import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/services/interview_reporter.dart';

import '../helpers/fake_firebase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirestore firestore;
  late FakeFirebaseAuth auth;

  InterviewReporter reporter() =>
      InterviewReporter(firestore: firestore, auth: auth);

  setUp(() {
    firestore = FakeFirestore();
    auth = FakeFirebaseAuth()
      ..user = FakeUser(uid: 'u1', isAnonymous: true);
  });

  test('ヒアリング未通過なら何も書かない', () async {
    SharedPreferences.setMockInitialValues({});
    await reporter().report();
    expect(firestore.users, isEmpty);
  });

  test('回答を users doc へ書き、同期済みを記録する', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyInterviewCompleted: true,
      '${AppConfig.prefKeyInterviewPrefix}level': 'chars',
      '${AppConfig.prefKeyInterviewPrefix}goal': 'work',
    });

    await reporter().report();

    expect(firestore.users['u1']?['interview'], {
      'level': 'chars',
      'goal': 'work',
    });
    expect(firestore.users['u1']?['interview_answer_count'], 2);
    // level は分析用。語彙スコア（estimated_vocab / 旧 vocab_floor）には
    // 一切入れない。
    expect(firestore.users['u1']?.containsKey('vocab_floor'), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConfig.prefKeyInterviewSynced), isTrue);
  });

  test('level を答えても語彙スコアのフィールドは書かない', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyInterviewCompleted: true,
      '${AppConfig.prefKeyInterviewPrefix}level': 'conv',
    });

    await reporter().report();

    final doc = firestore.users['u1'] ?? {};
    expect(doc.containsKey('vocab_floor'), isFalse);
    expect(doc.containsKey('estimated_vocab'), isFalse);
    expect(doc['interview'], {'level': 'conv'});
  });

  test('全問スキップでも件数0として残す', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyInterviewCompleted: true,
    });

    await reporter().report();

    expect(firestore.users['u1']?['interview'], isEmpty);
    expect(firestore.users['u1']?['interview_answer_count'], 0);
  });

  test('同期済みなら二度と書かない', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyInterviewCompleted: true,
      AppConfig.prefKeyInterviewSynced: true,
      '${AppConfig.prefKeyInterviewPrefix}level': 'chars',
    });

    await reporter().report();

    expect(firestore.users, isEmpty);
  });

  test('未サインインなら書かず、同期済みにもしない（次回起動で再送）', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyInterviewCompleted: true,
      '${AppConfig.prefKeyInterviewPrefix}level': 'chars',
    });
    auth.user = null;

    await reporter().report();

    expect(firestore.users, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConfig.prefKeyInterviewSynced), isNull);
  });

  test('設問キーの定義が画面と一致している', () {
    // 画面側の _questions は private なので、prefs に書かれるキーで確認する。
    expect(
      AppConfig.interviewQuestionKeys,
      containsAll(['level', 'goal', 'time', 'struggle']),
    );
  });
}
