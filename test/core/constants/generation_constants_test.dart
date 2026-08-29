import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/constants/generation_constants.dart';

// サーバー側（functions/go/internal/sentence/prompts.go）と同じ取り決め。
// 毎日配信はサーバーの対応表を使うので、両方を同じ内容に保つ。
void main() {
  group('topicForInterviewGoal', () {
    test('候補はテーマ一覧の中から選ぶ', () {
      for (final candidates in GenerationConstants.interviewGoalTopics.values) {
        for (final topic in candidates) {
          expect(GenerationConstants.topics, contains(topic));
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
        // 旅行・交通
        'travel': [
          GenerationConstants.topics[5],
          GenerationConstants.topics[8],
        ],
        // 仕事
        'work': [GenerationConstants.topics[2]],
        // 買い物・家族
        'live': [
          GenerationConstants.topics[7],
          GenerationConstants.topics[6],
        ],
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
          GenerationConstants.topicForInterviewGoal('travel'),
      };
      expect(picked.length, greaterThan(1));
      expect(
        picked,
        everyElement(isIn(GenerationConstants.interviewGoalTopics['travel']!)),
      );
    });

    test('未回答・未知の goal では null（サーバーの自動選出に任せる）', () {
      expect(GenerationConstants.topicForInterviewGoal(null), isNull);
      expect(GenerationConstants.topicForInterviewGoal('unknown'), isNull);
    });
  });
}
