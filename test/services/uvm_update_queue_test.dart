import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/services/uvm_update_queue.dart';

import '../helpers/fake_firebase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UvmUpdateQueue queue;
  final key = UvmUpdateQueue.pendingKey('u1');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queue = UvmUpdateQueue(
      auth: FakeFirebaseAuth()..user = FakeUser(uid: 'u1', isAnonymous: false),
    );
  });

  Map<String, dynamic> answer(String word) => {
        'results': [
          {'word': word, 'is_correct': true},
        ],
      };

  List<String> words(List<Map<String, dynamic>> sent) =>
      [for (final p in sent) (p['results'] as List).first['word'] as String];

  test('送れた回答は端末に残さない', () async {
    final sent = <Map<String, dynamic>>[];
    await queue.submit(answer('a'), (p) async => sent.add(p));

    expect(words(sent), ['a']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(key), isEmpty);
  });

  test('通信で落ちた回答は溜めて、次に送れたとき古い順に送る', () async {
    Future<void> offline(Map<String, dynamic> _) async =>
        throw FirebaseFunctionsException(code: 'unavailable', message: '');
    await queue.submit(answer('a'), offline);
    await queue.submit(answer('b'), offline);

    final sent = <Map<String, dynamic>>[];
    await queue.flush((p) async => sent.add(p));

    expect(words(sent), ['a', 'b']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(key), isEmpty);
  });

  test('何度送っても通らない回答は捨てて、後ろを止めない', () async {
    final sent = <Map<String, dynamic>>[];
    await queue.submit(answer('bad'), (p) async {
      throw FirebaseFunctionsException(code: 'invalid-argument', message: '');
    });
    await queue.submit(answer('ok'), (p) async => sent.add(p));

    expect(words(sent), ['ok']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(key), isEmpty);
  });

  test('初期化で溜めた回答を捨てる', () async {
    await queue.submit(answer('a'), (p) async => throw Exception('offline'));
    await queue.clear('u1');

    final sent = <Map<String, dynamic>>[];
    await queue.flush((p) async => sent.add(p));
    expect(sent, isEmpty);
  });
}
