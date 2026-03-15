import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import 'tone_guide_screen.dart';

/// Settings screen
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        children: [
          _buildAccountSection(),
          const SizedBox(height: 24),
          _buildThemeSection(),
          const SizedBox(height: 24),
          _buildNotificationSection(),
          const SizedBox(height: 24),
          _buildLearningSection(),
          const SizedBox(height: 24),
          _buildStatisticsSection(),
          const SizedBox(height: 24),
          _buildAboutSection(),
        ],
      ),
    );
  }

  /// Build account section
  Widget _buildAccountSection() {
    final authState = ref.watch(authControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'アカウント',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person),
              title: Text(authState.displayName ?? 'ユーザー'),
              subtitle:
                  authState.email != null ? Text(authState.email!) : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.workspace_premium),
              title: const Text('プラン'),
              trailing: Consumer(
                builder: (context, ref, _) {
                  final isPremium = ref.watch(isPremiumProvider);
                  return Chip(
                    label: Text(isPremium ? 'Premium' : 'Free'),
                    backgroundColor: isPremium
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    labelStyle: TextStyle(
                      color: isPremium
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: authState.isLoading ? null : _deleteAccount,
                  child: Text(
                    'アカウントを削除',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: authState.isLoading ? null : _signOut,
                  child: const Text('サインアウト'),
                ),
              ],
            ),
            if (authState.isLoading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サインアウト'),
        content: const Text('サインアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('サインアウト'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final error =
        await ref.read(authControllerProvider.notifier).signOut();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウント削除'),
        content: const Text('アカウントを削除すると、サーバーおよび端末のすべての学習データが完全に削除されます。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '削除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final error =
        await ref.read(authControllerProvider.notifier).deleteAccount();
    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        ref.invalidate(allSentencesProvider);
        ref.invalidate(favoriteSentencesProvider);
        ref.invalidate(sentenceCountProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウントとすべてのデータを削除しました'),
          ),
        );
      }
    }
  }

  /// Build theme section
  Widget _buildThemeSection() {
    final themeMode = ref.watch(themeModeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.palette,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'テーマ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('システム'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('ライト'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('ダーク'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (Set<ThemeMode> newSelection) {
                ref
                    .read(settingsControllerProvider.notifier)
                    .setThemeMode(newSelection.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build notification section
  Widget _buildNotificationSection() {
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '通知',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('クイズ通知'),
              subtitle: const Text('クイズのリマインダーを受け取る'),
              value: notificationsEnabled,
              onChanged: (value) {
                ref
                    .read(settingsControllerProvider.notifier)
                    .setNotificationEnabled(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build learning section
  Widget _buildLearningSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.school,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '学習',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.graphic_eq,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('声調ガイド'),
              subtitle: const Text('タイ語の声調ルールを学ぶ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ToneGuideScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build statistics section
  Widget _buildStatisticsSection() {
    final sentenceCountAsync = ref.watch(sentenceCountProvider);
    final favoriteCountAsync = ref.watch(favoriteSentencesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '統計',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '合計例文数',
                    sentenceCountAsync.when(
                      data: (count) => '$count',
                      loading: () => '...',
                      error: (_, __) => 'エラー',
                    ),
                    Icons.article,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'お気に入り',
                    favoriteCountAsync.when(
                      data: (favorites) => '${favorites.length}',
                      loading: () => '...',
                      error: (_, __) => 'エラー',
                    ),
                    Icons.favorite,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build stat item
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build about section
  Widget _buildAboutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'アプリについて',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${AppConfig.appName} v${AppConfig.appVersion}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '毎日タイ語を学習しましょう',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
