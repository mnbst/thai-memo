import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/review_provider.dart';

/// 復習タブ画面
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(reviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('復習')),
      body: review == null
          ? const Center(child: Text('まだ復習データがありません'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(
                          AppConfig.defaultPadding * 1.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review.thaiText,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
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
                  const SizedBox(height: 16),
                  if (review.reviewNotes.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(
                            AppConfig.defaultPadding * 1.5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                                const SizedBox(width: 8),
                                Text(
                                  '補足解説',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              review.reviewNotes,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
