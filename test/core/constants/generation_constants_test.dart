import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/constants/generation_constants.dart';

// サーバー側（functions/go/internal/sentence/prompts.go）と同じ取り決め。
// 毎日配信はサーバーの対応表を使うので、両方を同じ内容に保つ。
void main() {
  group('topicForInterviewGoal', () {
    test('候補はテーマ選択の一覧の中から選ぶ', () {
      for (final candidates in GenerationConstants.interviewGoalTopics.values) {
        for (final topic in candidates) {
          expect(GenerationConstants.pickerTopics, contains(topic));
        }
      }
    });

    test('学校・宗教・礼儀作法は候補に入れない（どの文言でも触れていない）', () {
      final excluded = {
        GenerationConstants.topics[12],
        GenerationConstants.topics[13],
        GenerationConstants.topics[15],
      };
      for (final candidates in GenerationConstants.interviewGoalTopics.values) {
        expect(candidates.toSet().intersection(excluded), isEmpty);
      }
    });

    test('考え方の画面が名指ししているテーマは必ず出せる', () {
      final promised = {
        // タイ旅行
        'travel': [GenerationConstants.travelTopic],
        // 仕事
        'work': [GenerationConstants.topics[2]],
        // タイ暮らし
        'live': [GenerationConstants.lifeTopic],
        // BLドラマ・伝統・祭り
        'culture': [
          GenerationConstants.topics[0],
          GenerationConstants.topics[14],
        ],
      };
      promised.forEach((goal, topics) {
        expect(
          GenerationConstants.interviewGoalTopics[goal],
          containsAll(topics),
        );
      });
    });

    test('候補が複数あるものは1つに固定しない', () {
      final picked = {
        for (var i = 0; i < 100; i++)
          GenerationConstants.topicForInterviewGoal('culture'),
      };
      expect(picked.length, greaterThan(1));
      expect(
        picked,
        everyElement(isIn(GenerationConstants.interviewGoalTopics['culture']!)),
      );
    });

    test('未回答・未知の goal では null（サーバーの自動選出に任せる）', () {
      expect(GenerationConstants.topicForInterviewGoal(null), isNull);
      expect(GenerationConstants.topicForInterviewGoal('unknown'), isNull);
    });
  });

  test('isGreetingTopic は正式名と旧版の短い名前をあいさつと判定する', () {
    expect(GenerationConstants.isGreetingTopic(GenerationConstants.topics[3]),
        isTrue);
    expect(GenerationConstants.isGreetingTopic('あいさつ'), isTrue);
    expect(GenerationConstants.isGreetingTopic(GenerationConstants.topics[2]),
        isFalse);
    expect(GenerationConstants.isGreetingTopic(null), isFalse);
  });

  group('pickerTopics', () {
    test('あいさつはテーマ選択にもヒアリングの候補にも出さない', () {
      final greeting = GenerationConstants.topics[3];
      expect(GenerationConstants.pickerTopics, isNot(contains(greeting)));
      for (final topics in GenerationConstants.interviewGoalTopics.values) {
        expect(topics, isNot(contains(greeting)));
      }
    });

    test('まとめたテーマを出し、その中身の個別テーマは出さない', () {
      final picker = GenerationConstants.pickerTopics;
      expect(
          picker,
          containsAll([
            GenerationConstants.lifeTopic,
            GenerationConstants.travelTopic,
          ]));
      for (final i in [4, 5, 6, 7, 8, 9, 10]) {
        expect(picker, isNot(contains(GenerationConstants.topics[i])));
      }
      expect(picker.toSet().length, picker.length);
    });

    test('英語版は暮らし・旅行を先頭、BL・推し活を末尾にし、項目は変えない', () {
      final en = GenerationConstants.pickerTopicsFor('en');
      expect(en.toSet(), GenerationConstants.pickerTopics.toSet());
      expect(en.length, GenerationConstants.pickerTopics.length);
      expect(en.take(2), [
        GenerationConstants.lifeTopic,
        GenerationConstants.travelTopic,
      ]);
      expect(en.skip(en.length - 2), [
        GenerationConstants.topics[0],
        GenerationConstants.topics[16],
      ]);
    });

    test('日本語版・韓国語版の並びは変えない', () {
      for (final code in ['ja', 'ko']) {
        expect(GenerationConstants.pickerTopicsFor(code),
            GenerationConstants.pickerTopics);
      }
    });
  });
}
