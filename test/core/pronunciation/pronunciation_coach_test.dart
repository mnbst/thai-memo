import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_coach.dart';
import 'package:thai_memo/core/pronunciation/segment_coach.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/pronunciation/transcript_match.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

SyllableScore _score({
  required int index,
  required ThaiTone tone,
  required ToneVerdict verdict,
  bool? shapeAgrees,
  bool? stepAgrees,
  double referenceStep = 0,
}) =>
    SyllableScore(
      syllableIndex: index,
      tone: tone,
      verdict: verdict,
      shapeAgrees: shapeAgrees,
      stepAgrees: stepAgrees,
      referenceStep: referenceStep,
    );

void main() {
  group('coachingTipOf', () {
    test('直すところが無ければ返さない', () {
      expect(
        coachingTipOf([
          _score(
            index: 0,
            tone: ThaiTone.mid,
            verdict: ToneVerdict.correct,
            shapeAgrees: true,
            stepAgrees: true,
          ),
        ]),
        isNull,
      );
    });

    test('最も多く外している声調と軸を選ぶ', () {
      final tip = coachingTipOf([
        _score(
          index: 0,
          tone: ThaiTone.high,
          verdict: ToneVerdict.wrong,
          shapeAgrees: false,
          stepAgrees: false,
        ),
        _score(
          index: 1,
          tone: ThaiTone.falling,
          verdict: ToneVerdict.wrong,
          shapeAgrees: false,
          stepAgrees: false,
        ),
        _score(
          index: 2,
          tone: ThaiTone.falling,
          verdict: ToneVerdict.wrong,
          shapeAgrees: false,
          stepAgrees: false,
        ),
      ]);

      expect(tip!.tone, ThaiTone.falling);
      expect(tip.issue, CoachIssue.shape);
      expect(tip.syllableIndex, 1);
    });

    test('形が合っていれば入り方を指す', () {
      final tip = coachingTipOf([
        _score(
          index: 3,
          tone: ThaiTone.low,
          verdict: ToneVerdict.wrong,
          shapeAgrees: true,
          stepAgrees: false,
          referenceStep: -0.4,
        ),
      ]);

      expect(tip!.issue, CoachIssue.step);
      expect(tip.stepUp, isFalse);
    });

    test('お手本が上がって入るなら stepUp', () {
      final tip = coachingTipOf([
        _score(
          index: 1,
          tone: ThaiTone.high,
          verdict: ToneVerdict.wrong,
          shapeAgrees: true,
          stepAgrees: false,
          referenceStep: 0.5,
        ),
      ]);

      expect(tip!.stepUp, isTrue);
    });

    test('wrong が無ければ close を見る', () {
      final tip = coachingTipOf([
        _score(
          index: 0,
          tone: ThaiTone.rising,
          verdict: ToneVerdict.close,
          shapeAgrees: false,
          stepAgrees: true,
        ),
      ]);

      expect(tip!.tone, ThaiTone.rising);
      expect(tip.issue, CoachIssue.shape);
    });

    test('wrong があれば close より優先する', () {
      final tip = coachingTipOf([
        _score(
          index: 0,
          tone: ThaiTone.rising,
          verdict: ToneVerdict.close,
          shapeAgrees: false,
          stepAgrees: true,
        ),
        _score(
          index: 1,
          tone: ThaiTone.mid,
          verdict: ToneVerdict.wrong,
          shapeAgrees: false,
          stepAgrees: false,
        ),
      ]);

      expect(tip!.tone, ThaiTone.mid);
    });

    test('測れていない音節（両軸 null）には助言しない', () {
      expect(
        coachingTipOf([
          _score(index: 0, tone: ThaiTone.mid, verdict: ToneVerdict.wrong),
        ]),
        isNull,
      );
    });

    test('代表音節に書かれている声調記号を載せる', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 1,
            tone: ThaiTone.falling,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        toneMarks: const ['', '้', '่'],
      );

      expect(tip!.toneMark, '้');
    });

    test('無記号の音節では記号を出さない', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.rising,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        toneMarks: const [''],
      );

      expect(tip!.toneMark, isEmpty);
    });

    test('記号列が音節数より短くても落ちない', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 5,
            tone: ThaiTone.high,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        toneMarks: const ['่'],
      );

      expect(tip!.toneMark, isEmpty);
    });

    test('代表音節のローマ字を載せる', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 1,
            tone: ThaiTone.low,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        toneMarks: const ['', '่', ''],
        romans: const ['sa', 'wàt', 'dii'],
      );

      expect(tip!.roman, 'wàt');
      expect(tip.toneMark, '่');
    });

    test('声調が全部合っていても、聞き取られなかった語があれば名指しする', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.mid,
            verdict: ToneVerdict.correct,
            shapeAgrees: true,
            stepAgrees: true,
          ),
        ],
        recognition: const [
          WordRecognition.recognized,
          WordRecognition.missing,
        ],
        wordTexts: const ['ผม', 'ครับ'],
      );

      expect(tip!.issue, CoachIssue.notRecognized);
      expect(tip.wordText, 'ครับ');
    });

    test('聞き取られなかった語には、子音・母音の直す点を1つ載せる', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.mid,
            verdict: ToneVerdict.correct,
            shapeAgrees: true,
            stepAgrees: true,
          ),
        ],
        recognition: const [WordRecognition.missing],
        wordTexts: const ['ปาก'],
        romans: const ['pàak'],
        segmentPointOfWord: (index) => index == 0
            ? const SegmentPoint(
                issue: SegmentIssue.unaspirated,
                syllableIndex: 0,
                label: 'ป',
                aspirated: 'พ',
              )
            : null,
      );

      expect(tip!.issue, CoachIssue.notRecognized);
      expect(tip.segment?.issue, SegmentIssue.unaspirated);
      // 指した音節のローマ字が載る（声調の助言と同じ見せ方にするため）。
      expect(tip.roman, 'pàak');
    });

    test('直す点が取れなければ語を名指しするだけ', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.mid,
            verdict: ToneVerdict.correct,
            shapeAgrees: true,
            stepAgrees: true,
          ),
        ],
        recognition: const [WordRecognition.missing],
        wordTexts: const ['มา'],
        segmentPointOfWord: (_) => null,
      );

      expect(tip!.issue, CoachIssue.notRecognized);
      expect(tip.segment, isNull);
    });

    test('声調の助言がある回は認識より優先する', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.falling,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        recognition: const [WordRecognition.missing],
        wordTexts: const ['ครับ'],
      );

      expect(tip!.issue, CoachIssue.shape);
    });

    test('音声認識に非対応の端末では認識を根拠にしない', () {
      expect(
        coachingTipOf(
          const <SyllableScore>[],
          recognition: const [WordRecognition.unavailable],
          wordTexts: const ['ครับ'],
        ),
        isNull,
      );
    });

    test('助言の声調はローマ字の記号から読む（採点側の声調より優先）', () {
      // สิงห์: 黙字 ์ を末子音と見て死音節に落とすと低声になるが、実際は上昇声。
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.low,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        romans: const ['sǐng'],
      );

      expect(tip!.tone, ThaiTone.rising);
    });

    test('結合文字で来たローマ字も読む（サーバーはこちらで返す）', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.low,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        romans: const ['si\u030Cng'],
      );

      expect(tip!.tone, ThaiTone.rising);
    });

    test('ローマ字が取れない語では採点側の声調を使う', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.low,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        romans: const [''],
      );

      expect(tip!.tone, ThaiTone.low);
    });

    test('記号の無いローマ字は平声として読む', () {
      final tip = coachingTipOf(
        [
          _score(
            index: 0,
            tone: ThaiTone.low,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ],
        romans: const ['dii'],
      );

      expect(tip!.tone, ThaiTone.mid);
    });

    test('声調が決まらない音節は対象外', () {
      expect(
        coachingTipOf([
          _score(
            index: 0,
            tone: ThaiTone.unknown,
            verdict: ToneVerdict.wrong,
            shapeAgrees: false,
            stepAgrees: false,
          ),
        ]),
        isNull,
      );
    });
  });
}
