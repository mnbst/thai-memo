import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';
import 'package:thai_memo/data/sentence_repository.dart';

class _Api extends Fake implements BackendApiService {}

class _Db extends Fake implements DatabaseHelper {
  List<Map<String, dynamic>> sentences = [];
  List<Map<String, dynamic>> words = [];
  int wordQueries = 0;
  @override
  Future<List<Map<String, dynamic>>> getAllSentences() async => sentences;
  @override
  Future<List<Map<String, dynamic>>> getAllWordBreakdowns() async {
    wordQueries++;
    return words;
  }
}

void main() {
  test('履歴の並びと単語の所属・順序を保ち、単語の無い例文も返す', () async {
    final db = _Db();
    db.sentences = [
      for (final id in ['b', 'a', 'empty'])
        ThaiSentence(
            id: id,
            thaiText: 'ไทย',
            pronunciation: 'thai',
            japaneseTranslation: 'タイ',
            wordBreakdowns: const []).toDatabase(),
    ];
    db.words = [
      for (final (owner, id, order) in [
        ('a', 'a1', 0),
        ('a', 'a2', 1),
        ('b', 'b1', 0)
      ])
        WordBreakdown(
                id: id,
                sentenceId: owner,
                wordText: 'ไทย',
                pronunciation: 'thai',
                meaning: 'タイ',
                wordOrder: order)
            .toDatabase(),
    ];
    final repository =
        SentenceRepository(databaseHelper: db, apiService: _Api());
    final results = await repository.getAllSentences();
    expect(results.map((s) => s.id), ['b', 'a', 'empty']);
    expect(
        results.map((s) => s.wordBreakdowns.map((w) => w.id).toList()).toList(),
        [
          ['b1'],
          ['a1', 'a2'],
          []
        ]);
    expect(db.wordQueries, 1);
  });

  test('履歴が空なら単語を取得しない', () async {
    final db = _Db();
    final repository =
        SentenceRepository(databaseHelper: db, apiService: _Api());
    expect(await repository.getAllSentences(), isEmpty);
    expect(db.wordQueries, 0);
  });

  test('レスポンスの id をそのまま主キーにする（既読の宛先を揃えるため）', () {
    final sentence = BackendApiService.createThaiSentenceFromJson({
      'id': 'server-doc-1',
      'thai_text': 'ฉันกินข้าว',
      'pronunciation': 'chan kin khao',
      'japanese_translation': 'ご飯を食べます',
      'word_breakdown': const [],
    });

    expect(sentence.id, 'server-doc-1');
  });

  test('id を返さない旧サーバーのレスポンスでも読める', () {
    final sentence = BackendApiService.createThaiSentenceFromJson({
      'thai_text': 'ฉันกินข้าว',
      'pronunciation': 'chan kin khao',
      'japanese_translation': 'ご飯を食べます',
      'word_breakdown': const [],
    });

    expect(sentence.id, isNull);
  });
}
