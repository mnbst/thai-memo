import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../data/datasources/backend_api_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/topic_picker.dart';
import '../widgets/vocab_score_dialog.dart';
import 'contact_form_screen.dart';
import 'paywall_screen.dart';
import 'tone_guide_screen.dart';

/// Settings screen
class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = 'settings';

  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// 毎日例文通知トグルの位置特定用（コーチマーク表示に使用）。
  final GlobalKey _dailyReminderTileKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    CoachMarkOverlay.dismiss();
    _scrollController.dispose();
    super.dispose();
  }

  /// 毎日例文通知のトグルをスポットライトで案内する（HomeScreenから呼ばれる）。
  ///
  /// OSの許可要求はここでは出さない。ユーザー自身がトグルを操作したときに
  /// [SettingsController.setDailyReminderEnabled] 経由で出す。iOSでは一度拒否
  /// されると二度と要求できないため、何のための通知かを伝えてから聞く。
  Future<void> showDailyReminderCoach() async {
    final target = _dailyReminderTileKey.currentContext;
    if (target == null) return;
    // 設定画面はスクロールするため、トグルを画面内に入れてから位置を確定させる。
    await Scrollable.ensureVisible(target, alignment: 0.3);
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dailyReminderTileKey.currentContext == null) return;
      CoachMarkOverlay.show(
        context,
        targetKey: _dailyReminderTileKey,
        icon: Icons.notifications_active,
        interactive: true,
        title: 'ここで通知をオンにできます',
        message: 'このスイッチをオンにすると、毎日きまった時刻に例文が届きます。'
            '通知する時刻はすぐ下の項目で変更できます。',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        children: [
          _buildAccountSection(),
          const SizedBox(height: 24),
          _buildLearningSection(),
          const SizedBox(height: 24),
          _buildDisplaySection(),
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
              title: Text(
                authState.isLinked ? (authState.displayName ?? 'ユーザー') : 'ゲスト',
              ),
              subtitle: authState.isLinked
                  ? (authState.email != null ? Text(authState.email!) : null)
                  : const Text('サインインしていません'),
            ),
            Consumer(
              builder: (context, ref, _) {
                final isPremium = ref.watch(isPremiumProvider);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.workspace_premium),
                  title: const Text('プラン'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
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
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => PaywallBottomSheet.show(
                    context,
                    source: 'settings_plan',
                  ),
                );
              },
            ),
            if (authState.isLinked)
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
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: authState.isLoading ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('サインインして進捗を保存'),
                ),
              ),
            if (authState.isLoading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    await showSignInSheet(context);
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

    // uid が変わる前に通知登録を解除する。旧 doc にトークンが残ると、同じ端末に
    // 使ったアカウントの数だけ毎日例文が届く。
    await ref.read(settingsControllerProvider.notifier).unregisterPushForSignOut();

    final error = await ref.read(authControllerProvider.notifier).signOut();
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
        content: const Text(
            'アカウントを削除すると、サーバーおよび端末のすべての学習データが完全に削除されます。この操作は元に戻せません。'),
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
        ref.invalidate(sentenceCountProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウントとすべてのデータを削除しました'),
          ),
        );
      }
    }
  }

  /// Build display section
  Widget _buildDisplaySection() {
    final currentFont = ref.watch(fontFamilyProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.text_fields,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '表示',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.font_download_outlined),
              title: const Text('フォント'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentFont.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => _showFontPicker(currentFont),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _thaiFontStyle(ThaiFont font) {
    const size = 20.0;
    switch (font) {
      case ThaiFont.notoSansThai:
        return GoogleFonts.notoSansThai(fontSize: size);
      case ThaiFont.mitr:
        return GoogleFonts.mitr(fontSize: size);
      case ThaiFont.sarabun:
        return GoogleFonts.sarabun(fontSize: size);
      case ThaiFont.krub:
        return GoogleFonts.krub(fontSize: size);
    }
  }

  void _showFontPicker(ThaiFont current) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォントを選択'),
        content: RadioGroup<ThaiFont>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(settingsControllerProvider.notifier)
                  .setFontFamily(value);
              Navigator.pop(context);
            }
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ThaiFont.values
                  .map(
                    (font) => RadioListTile<ThaiFont>(
                      value: font,
                      title: Text(font.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('例文', style: TextStyle(fontSize: 10)),
                          Text(
                            'สวัสดีครับ ฉันเรียนภาษาไทย',
                            style: _thaiFontStyle(font),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
        ],
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
                  Icons.bar_chart,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '学習状況',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildVocabScoreInline(),
            const SizedBox(height: 16),
            Divider(
                height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '学習設定',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
            ),
            _buildTopicSelectTile(),
            _buildDailyReminderTile(),
            _buildReminderTimeTile(),
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
                    settings:
                        const RouteSettings(name: ToneGuideScreen.routeName),
                    builder: (context) => const ToneGuideScreen(),
                  ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.restart_alt,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '学習データをリセット',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('端末の例文・クイズ履歴を削除'),
              onTap: _resetLearningData,
            ),
          ],
        ),
      ),
    );
  }

  /// 毎日例文のプッシュ通知トグル。
  ///
  /// OSの通知許可が拒否されている場合はアプリ側では有効にできないため、
  /// 状態をオフのままにして端末設定への案内を出す。
  Widget _buildDailyReminderTile() {
    final enabled = ref.watch(dailyReminderEnabledProvider);

    return SwitchListTile(
      key: _dailyReminderTileKey,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(
        Icons.notifications_active,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('毎日の例文通知'),
      subtitle: const Text('その日の例文をお知らせします'),
      value: enabled,
      onChanged: (value) async {
        final applied = await ref
            .read(settingsControllerProvider.notifier)
            .setDailyReminderEnabled(value);
        if (!applied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('端末の設定で通知を許可してください'),
            ),
          );
        }
      },
    );
  }

  /// 配信時刻の選択。サーバーは時単位で配信するため分は切り捨てる。
  Widget _buildReminderTimeTile() {
    final enabled = ref.watch(dailyReminderEnabledProvider);
    final hour = ref.watch(settingsControllerProvider).preferredGenerationHour;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        Icons.schedule,
        color: enabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: const Text('通知する時刻'),
      subtitle: Text('${hour.toString().padLeft(2, '0')}:00'),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled
          ? () async {
              final picked = await _pickReminderHour(hour);
              if (picked == null) return;
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setPreferredGenerationTime(
                    TimeOfDay(hour: picked, minute: 0),
                  );
            }
          : null,
    );
  }

  /// 配信は時単位なので、分を選ばせずに「時」だけ選ばせる。
  Future<int?> _pickReminderHour(int current) {
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('通知する時刻'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.builder(
              itemCount: 24,
              itemBuilder: (context, hour) => ListTile(
                selected: hour == current,
                title: Text('${hour.toString().padLeft(2, '0')}:00'),
                trailing: hour == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, hour),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicSelectTile() {
    final isPremium = ref.watch(isPremiumProvider);
    final trialRemaining =
        ref.watch(premiumTrialRemainingProvider).valueOrNull ?? 0;
    // Premium またはトライアル中はテーマ選択可。例文/クイズ画面のチップと判定を揃える。
    final canSelect = isPremium || trialRemaining > 0;
    final currentTopic = ref.watch(generationParamsProvider)['topic'];

    final displayLabel = canSelect ? topicShortLabel(currentTopic) : 'おまかせ';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.category,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('テーマ'),
      subtitle: Text(displayLabel),
      trailing: canSelect
          ? const Icon(Icons.chevron_right)
          : Icon(Icons.lock, color: Theme.of(context).colorScheme.outline),
      onTap: canSelect
          ? _showTopicPicker
          : () => PaywallBottomSheet.show(context, source: 'settings_topic'),
    );
  }

  Future<void> _showTopicPicker() => showTopicPicker(context, ref);

  Future<void> _resetLearningData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('学習データのリセット'),
        content: const Text('端末に保存されている例文・クイズ履歴・学習進捗がすべて削除されます。アカウントは維持されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'リセット',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await BackendApiService().resetLearningData();
      await DatabaseHelper.instance.deleteDatabase();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        ref.invalidate(allSentencesProvider);
        ref.invalidate(sentenceCountProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学習データをリセットしました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('リセットに失敗しました'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildVocabScoreInline() {
    final statsAsync = ref.watch(vocabStatsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return statsAsync.when(
      data: (stats) {
        final displayVocab = isPremium
            ? stats.estimatedVocab
            : stats.estimatedVocab.clamp(0, freeVocabScoreLimit).toInt();
        final level = vocabLevel(displayVocab);
        final threshold =
            isPremium ? _nextVocabThreshold(displayVocab) : freeVocabScoreLimit;
        final progress = (displayVocab / threshold).clamp(0.0, 1.0).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$displayVocab語',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(level),
                  visualDensity: VisualDensity.compact,
                  labelStyle: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPremium
                  ? '次のレベルまで あと${threshold - displayVocab}語'
                  : 'Freeプランは$freeVocabScoreLimit語が上限です',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  int _nextVocabThreshold(int vocab) {
    if (vocab < 100) return 100;
    if (vocab < 300) return 300;
    if (vocab < 600) return 600;
    if (vocab < 1500) return 1500;
    return 3000;
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URLを開けませんでした')),
        );
      }
    }
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
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('プライバシーポリシー'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConfig.privacyPolicyUrl),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: const Text('利用規約'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConfig.termsOfServiceUrl),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: const Text('お問い合わせ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(
                    name: ContactFormScreen.routeName,
                  ),
                  builder: (_) => const ContactFormScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
