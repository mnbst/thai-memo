import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/sentence_audio_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('取れないときは止まらずに null を返す（端末の読み上げへ戻せる）', () async {
    // テストには path_provider の実体が無いので、保存先を開けずに失敗する。
    final cache = SentenceAudioCache();
    const source = SentenceAudioSource(text: 'สวัสดีครับ');

    expect(
      await cache.fileFor(source).timeout(const Duration(seconds: 2)),
      isNull,
    );
    // 同じ文の2回目も、前回の取得の後始末で止まらない。
    expect(
      await cache.fileFor(source).timeout(const Duration(seconds: 2)),
      isNull,
    );
  });

  test('絵文字と空白の違いは同じ文として扱う', () {
    expect(
      SentenceAudioCache.normalize(' สวัสดี  ครับ 🙏 '),
      SentenceAudioCache.normalize('สวัสดี ครับ'),
    );
  });

  test('上限を超えたら最後に聞いたのが古い順に消す', () async {
    final dir = await Directory.systemTemp.createTemp('sentence_audio');
    addTearDown(() => dir.delete(recursive: true));
    final base = DateTime(2026, 10, 1);
    Future<File> put(String name, int days) async {
      final f = File('${dir.path}/$name.mp3');
      await f.writeAsBytes(List.filled(100, 0));
      await f.setLastModified(base.add(Duration(days: days)));
      return f;
    }

    final oldest = await put('a', 0);
    final middle = await put('b', 1);
    final newest = await put('c', 2);
    final other = File('${dir.path}/note.txt')..writeAsStringSync('x' * 500);

    await SentenceAudioCache.prune(dir, 200);

    expect(oldest.existsSync(), isFalse);
    expect(middle.existsSync(), isTrue);
    expect(newest.existsSync(), isTrue);
    expect(other.existsSync(), isTrue, reason: 'mp3 以外は数えない・消さない');
  });
}
