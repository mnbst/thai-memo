import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/review_provider.dart';

/// 復習タブ画面: PageViewで1文ずつ表示
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final reviews = ref.watch(reviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('復習'),
        actions: [
          if (reviews.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(reviewProvider.notifier).clear(),
              tooltip: 'クリア',
            ),
        ],
      ),
      body: reviews.isEmpty
          ? const Center(child: Text('まだ復習データがありません'))
          : Column(
              children: [
                // ページインジケーター
                if (reviews.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_currentPage + 1} / ${reviews.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    itemCount: reviews.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (context, index) =>
                        _ReviewPage(review: reviews[index]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReviewPage extends StatelessWidget {
  final ReviewData review;
  const _ReviewPage({required this.review});

  @override
  Widget build(BuildContext context) {
    final notes = review.reviewNotes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 例文カード
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review.thaiText,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          fontSize: 32,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    review.pronunciation,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    review.japaneseTranslation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),

          // 構造化された補足解説
          if (!notes.isEmpty) ...[
            const SizedBox(height: 16),

            // 文法ポイント
            if (notes.grammarPoints.isNotEmpty)
              _SectionCard(
                icon: Icons.menu_book,
                title: '文法ポイント',
                children: notes.grammarPoints
                    .map((p) => _LabelDetail(label: p.label, detail: p.detail))
                    .toList(),
              ),

            // 発音・声調
            if (notes.pronunciationTips.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.record_voice_over,
                title: '発音・声調',
                children: notes.pronunciationTips
                    .map((p) => _ThaiTip(
                        thai: p.thai, roman: p.roman, tip: p.tip))
                    .toList(),
              ),
            ],

            // 関連表現
            if (notes.relatedExpressions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.swap_horiz,
                title: '関連表現',
                children: notes.relatedExpressions
                    .map((e) => _RelatedRow(
                        thai: e.thai, roman: e.roman, meaning: e.meaning))
                    .toList(),
              ),
            ],
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// セクションカード
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// ラベル + 詳細テキスト
class _LabelDetail extends StatelessWidget {
  final String label;
  final String detail;
  const _LabelDetail({required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// タイ語 + ローマ字 + 解説
class _ThaiTip extends StatelessWidget {
  final String thai;
  final String roman;
  final String tip;
  const _ThaiTip({required this.thai, required this.roman, required this.tip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: thai,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              TextSpan(
                text: '  $roman',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Text(
            tip,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 関連表現の行
class _RelatedRow extends StatelessWidget {
  final String thai;
  final String roman;
  final String meaning;
  const _RelatedRow(
      {required this.thai, required this.roman, required this.meaning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: thai,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: ' ($roman)',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              meaning,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
