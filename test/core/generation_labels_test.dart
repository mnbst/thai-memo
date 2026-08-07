/// サーバーが返す識別子が英語ラベルに変換されることを検証する。
///
/// `context.topic` / `context.style` は履歴画面の集計キーなので、英語版でも
/// サーバーは日本語の識別子のまま返す。表示だけをここで訳しているため、
/// マッピングが漏れると英語UIの中にその項目だけ日本語で出る。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/constants/generation_labels.dart';
import 'package:thai_memo/l10n/app_localizations.dart';

void main() {
  late L10n en;
  late L10n ja;

  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
    ja = await L10n.delegate.load(const Locale('ja'));
  });

  group('topicLabel', () {
    test('サブテーマ付きの識別子でも括弧の前で引ける', () {
      // 実際に生成された値。LLM は「仕事（同僚雑談）」のように括弧を足してくる。
      expect(topicLabel(en, '仕事（同僚雑談）').name, 'Work');
      expect(topicLabel(en, '仕事').name, 'Work');
      expect(topicLabel(ja, '仕事（同僚雑談）').name, '仕事');
    });

    test('未知のテーマはそのまま出す（訳せないより日本語で出る方がまし）', () {
      expect(topicLabel(en, '未知のテーマ').name, '未知のテーマ');
    });
  });

  group('styleLabel', () {
    test('STYLES の全値が英語ラベルに変換される', () {
      const styles = {
        'ニュース記事体（客観的・フォーマルな報道文体）': 'News style',
        '口語体（友達同士のカジュアルな話し言葉）': 'Casual spoken',
        '丁寧語（フォーマルな敬語・丁寧な表現）': 'Polite',
        'SNS・テキストメッセージ（略語・絵文字・短い表現）': 'Texting and social media',
        '物語・文学体（描写的・書き言葉的な表現）': 'Narrative',
      };
      styles.forEach((identifier, expected) {
        expect(styleLabel(en, identifier), expected, reason: identifier);
      });
    });

    test('未知の文体はそのまま出す', () {
      expect(styleLabel(en, '未知の文体'), '未知の文体');
    });
  });
}
