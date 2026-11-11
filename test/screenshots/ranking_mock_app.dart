// =============================================================================
// ranking_mock_app.dart
// ランキング画面（順位カード・分布・周辺の一覧）を Firestore なしのダミーで出す。
// 帯のラベルや人数の折り返しなど、表示崩れをシミュレーターで確かめるためのモック。
//
//   flutter run -t test/screenshots/ranking_mock_app.dart
//
// 右下のボタンで自分のスコアを切り替え、色つきの帯が動くことを確かめる。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/leaderboard_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/ranking_screen.dart';

void main() => runApp(const _MockApp());

/// 切り替える自分のスコア
const _myVocabs = [100, 42, 250, 1800, 3500];

/// 帯ごとの人数（vocabBands と同じ並び。足りない帯は 0）
const _bandCounts = [412, 1873, 236, 98, 31, 14, 6, 4, 1];

int _countAt(int i) => i < _bandCounts.length ? _bandCounts[i] : 0;

int _rankOf(int vocab) {
  var above = 0;
  for (var i = 0; i < vocabBands.length; i++) {
    if (vocabBands[i].min > vocab) above += _countAt(i);
  }
  return above + 1;
}

VocabDistribution _distribution(int myVocab) {
  final mine = bandOf(myVocab);
  final bands = [
    for (var i = 0; i < vocabBands.length; i++)
      VocabBand(
        min: vocabBands[i].min,
        max: vocabBands[i].max,
        count: _countAt(i),
        isMine: vocabBands[i] == mine,
      ),
  ];
  return VocabDistribution(
    bands: bands,
    total: bands.fold(0, (sum, band) => sum + band.count),
  );
}

List<LeaderboardEntry> _rows(int myVocab) {
  LeaderboardEntry other(String uid, String? name, int vocab) =>
      LeaderboardEntry(
        uid: uid,
        nickname: name,
        vocab: vocab,
        rank: _rankOf(vocab),
        isMe: false,
      );
  return [
    other('mock-top1-AAAA', 'สมชาย', 4120),
    other('mock-top2-BBBB', 'มาลี', 2930),
    other('mock-top3-CCCC', null, 2480),
    other('mock-up-DDDD', 'ประเสริฐ', myVocab + 1),
    LeaderboardEntry(
      uid: 'mock-me-EEEE',
      nickname: null,
      vocab: myVocab,
      rank: _rankOf(myVocab),
      isMe: true,
    ),
    other('mock-down-FFFF', null, myVocab - 1),
  ]..sort((a, b) => b.vocab.compareTo(a.vocab));
}

class _MockApp extends StatefulWidget {
  const _MockApp();

  @override
  State<_MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<_MockApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final vocab = _myVocabs[_index];
    return ProviderScope(
      key: ValueKey(vocab),
      overrides: [
        vocabStatsProvider.overrideWith(
            (ref) => Stream.value(VocabStats(estimatedVocab: vocab))),
        myRankProvider.overrideWith((ref) async => _rankOf(vocab)),
        vocabDistributionProvider
            .overrideWith((ref) async => _distribution(vocab)),
        leaderboardRowsProvider.overrideWith((ref) async => _rows(vocab)),
        effectivePremiumProvider.overrideWithValue(vocab > 100),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: const RankingScreen(),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                setState(() => _index = (_index + 1) % _myVocabs.length),
            label: Text('自分 $vocab語 → 切替'),
          ),
        ),
      ),
    );
  }
}
