import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/generation_constants.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import 'tone_guide_screen.dart';

/// Settings screen
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _customPromptFocusNode = FocusNode();
  String? _pendingCustomPrompt;

  @override
  void initState() {
    super.initState();
    _customPromptFocusNode.addListener(_onCustomPromptFocusChange);
  }

  @override
  void dispose() {
    _customPromptFocusNode.removeListener(_onCustomPromptFocusChange);
    _customPromptFocusNode.dispose();
    super.dispose();
  }

  void _onCustomPromptFocusChange() {
    if (!_customPromptFocusNode.hasFocus && _pendingCustomPrompt != null) {
      ref.read(settingsControllerProvider.notifier).setGenerationParam(
            GenerationConstants.customPromptKey,
            _pendingCustomPrompt!.isEmpty ? null : _pendingCustomPrompt,
          );
      _pendingCustomPrompt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        children: [
          _buildThemeSection(),
          const SizedBox(height: 24),
          _buildNotificationSection(),
          const SizedBox(height: 24),
          _buildLearningSection(),
          const SizedBox(height: 24),
          _buildGenerationSettingsSection(),
          const SizedBox(height: 24),
          _buildStatisticsSection(),
          const SizedBox(height: 24),
          _buildAboutSection(),
        ],
      ),
    );
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

  /// Build generation settings section
  Widget _buildGenerationSettingsSection() {
    final params = ref.watch(generationParamsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '今日のタイ語設定',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...GenerationConstants.parameterLabels.entries.map((entry) {
              final key = entry.key;
              final label = entry.value;
              final options = GenerationConstants.parameterOptions[key]!;
              final currentValue = params[key];

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildParamDropdown(key, label, options, currentValue),
              );
            }),
            const SizedBox(height: 8),
            _buildCustomPromptField(params[GenerationConstants.customPromptKey]),
          ],
        ),
      ),
    );
  }

  Widget _buildParamDropdown(
    String key,
    String label,
    List<String> options,
    String? currentValue,
  ) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: currentValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('ランダム'),
        ),
        ...options.map((option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: (value) {
        ref
            .read(settingsControllerProvider.notifier)
            .setGenerationParam(key, value);
      },
    );
  }

  Widget _buildCustomPromptField(String? currentValue) {
    return TextFormField(
      key: ValueKey(currentValue),
      initialValue: currentValue,
      focusNode: _customPromptFocusNode,
      maxLength: GenerationConstants.customPromptMaxLength,
      decoration: const InputDecoration(
        labelText: '自由メモ（例文に反映されます）',
        hintText: '例: レストランでの会話',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        _pendingCustomPrompt = value;
      },
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
