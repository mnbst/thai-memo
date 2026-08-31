/// サーバーが返す識別子が表示用ラベルに変換されることを検証する。
///
/// `context.topic` / `context.style` には2つの形が来る。日本語の識別子
/// （`仕事（報告・連絡・相談、…）`）と、英語ユーザー向けにサーバーが訳した
/// 英語ラベル（`Work (reporting, meetings, …)`）。どちらも括弧の中は補足
/// なので画面には出さない。マッピングが漏れると、英語UIの中にその項目だけ
/// 日本語で出るか、補足が丸ごとチップからはみ出す。
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

    test('サーバーが返す英語ラベルも括弧の前だけにする', () {
      // constants_data.go:topicLabelsEN の全値。半角括弧なので、全角だけを
      // 見ていると補足まで画面に出る。
      const labels = {
        'Greetings (morning, noon, night, first meeting, reunion, farewell, phone)':
            'Greetings',
        'Food (ordering, impressions, street stalls, spice level, allergies)':
            'Food',
        'Travel (hotels, directions, sights, airport, tours)': 'Travel',
        'Work (reporting, meetings, overtime requests, chatting with coworkers)':
            'Work',
        'Family (introductions, parenting, thanking parents, siblings, family events)':
            'Family',
        'Shopping (haggling, size and color, returns, night markets)':
            'Shopping',
        'Getting around (Grab, BTS, motorbike taxi, songthaew, traffic)':
            'Getting around',
        'Health (describing symptoms, pharmacy, massage, checkups)': 'Health',
        'Weather (heat, rainy season, storms, sun protection)': 'Weather',
        'Hobbies (Muay Thai, music, movies, golf, social media, games)':
            'Hobbies',
        'School (in class, homework, exams, after school, language school)':
            'School',
        'Religion and faith (temple etiquette, alms giving, amulets, speaking to monks, Buddhist holidays)':
            'Religion',
        'Traditions and festivals (Songkran, Loi Krathong, royal ceremonies, regional dishes)':
            'Traditions and festivals',
        'Etiquette (the wai, honorifics, taboos, table manners, gifts)':
            'Etiquette',
        'Romance (confessions, dates, sweet talk, long distance, breakups, making up)':
            'Dating and romance',
        'Thai BL drama (confessions, misunderstandings, reunions, jealousy, betrayal, making up, kabedon, nicknames)':
            'Thai BL dramas',
      };
      labels.forEach((identifier, expected) {
        expect(topicLabel(en, identifier).name, expected, reason: identifier);
      });
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

    test('サーバーが返す英語ラベルも括弧の前だけにする', () {
      // constants_data.go:styleLabelsEN の全値。
      const labels = {
        'News article style (objective, formal reporting)': 'News style',
        'Casual spoken style (how friends talk)': 'Casual spoken',
        'Polite style (formal, respectful expressions)': 'Polite',
        'Social media / text message style (abbreviations, emoji, short phrases)':
            'Texting and social media',
        'Narrative / literary style (descriptive, written language)':
            'Narrative',
      };
      labels.forEach((identifier, expected) {
        expect(styleLabel(en, identifier), expected, reason: identifier);
      });
    });

    test('未知の文体はそのまま出す', () {
      expect(styleLabel(en, '未知の文体'), '未知の文体');
    });
  });
}
