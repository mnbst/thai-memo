import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/l10n/app_language.dart';
import '../../data/datasources/backend_api_service.dart';
import '../../l10n/app_localizations.dart';
import '../../data/datasources/local/database_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/premium_trial_ended_dialog.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/topic_picker.dart';
import '../widgets/vocab_score_dialog.dart';
import 'contact_form_screen.dart';
import 'paywall_screen.dart';
import 'ranking_screen.dart';
import 'tone_guide_screen.dart';

/// Settings screen
class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = 'settings';

  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).settingsTitle)),
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
                  L10n.of(context).settingsAccount,
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
                authState.isLinked
                    ? (authState.displayName ?? L10n.of(context).settingsUser)
                    : L10n.of(context).settingsGuest,
              ),
              subtitle: authState.isLinked
                  ? (authState.email != null ? Text(authState.email!) : null)
                  : Text(L10n.of(context).settingsNotSignedIn),
            ),
            Consumer(
              builder: (context, ref, _) {
                final isPremium = ref.watch(isPremiumProvider);
                // 体験中は課金と同じ機能が使えているので、そのことを出す。
                // 「課金しているか」の表示なので Premium とは別ラベルにする。
                final trialActive =
                    !isPremium && ref.watch(effectivePremiumProvider);
                final label = isPremium
                    ? 'Premium'
                    : trialActive
                        ? L10n.of(context).settingsPlanTrial
                        : 'Free';
                final highlighted = isPremium || trialActive;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.workspace_premium),
                  title: Text(L10n.of(context).settingsPlan),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(label),
                        backgroundColor: highlighted
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        labelStyle: TextStyle(
                          color: highlighted
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
                      L10n.of(context).settingsDeleteAccount,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: authState.isLoading ? null : _signOut,
                    child: Text(L10n.of(context).settingsSignOut),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: authState.isLoading ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: Text(L10n.of(context).settingsSignInToSave),
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
        title: Text(L10n.of(context).settingsSignOut),
        content: Text(L10n.of(context).settingsSignOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.of(context).settingsSignOut),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // uid が変わる前に通知登録を解除する。旧 doc にトークンが残ると、同じ端末に
    // 使ったアカウントの数だけ毎日例文が届く。
    await ref
        .read(settingsControllerProvider.notifier)
        .unregisterPushForSignOut();

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
        title: Text(L10n.of(context).settingsDeleteAccountTitle),
        content: Text(L10n.of(context).settingsDeleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              L10n.of(context).commonDelete,
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
          SnackBar(
            content: Text(L10n.of(context).settingsAccountDeleted),
          ),
        );
      }
    }
  }

  /// Build display section
  Widget _buildDisplaySection() {
    final currentFont = ref.watch(fontFamilyProvider);
    final l10n = L10n.of(context);

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
                  l10n.settingsDisplay,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 言語は初回起動でストア地域から1回決めて保存し、以後は再評価しない。
            // 自動判定を外すと**戻す手段が無く**、ストア地域と実際の使用言語が
            // 違うユーザー（日本在住の英語話者、海外在住の日本語話者）は
            // 再インストールするまで読めない言語で使い続けることになる。
            // 履歴に日英が混ざる点はダイアログの注記で伝える。
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.translate),
              title: Text(l10n.settingsLanguage),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref.watch(appLanguageProvider).displayName,
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
              onTap: () => _showLanguagePicker(ref.read(appLanguageProvider)),
            ),
            // 体験終了ダイアログは期限が来ないと出ないので、見た目の確認用に
            // dev だけ手動で開けるようにしておく。
            if (AppConfig.isDev)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_bottom_rounded),
                title: const Text('プレミアム体験終了ダイアログ（dev）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final open = await showPremiumTrialEndedDialog(context);
                  if (!open || !mounted) return;
                  await PaywallBottomSheet.show(context,
                      source: 'trial_ended_preview');
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.font_download_outlined),
              title: Text(l10n.settingsFont),
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

  /// 訳文・UI の言語切替。既存の例文の訳は作成時の言語のまま残る。
  void _showLanguagePicker(AppLanguage current) {
    final l10n = L10n.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsLanguagePickerTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<AppLanguage>(
              groupValue: current,
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(settingsControllerProvider.notifier)
                    .setAppLanguage(value);
                Navigator.pop(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: AppLanguage.values
                    .map(
                      (lang) => RadioListTile<AppLanguage>(
                        value: lang,
                        // 切替前でも読めるよう、選択肢はそれぞれの言語で表示する
                        title: Text(lang.displayName),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsLanguageNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFontPicker(ThaiFont current) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).settingsFontPickerTitle),
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
                          Text(L10n.of(context).settingsFontSample,
                              style: const TextStyle(fontSize: 10)),
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
            child: Text(L10n.of(context).commonCancel),
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
                  L10n.of(context).settingsLearningStatus,
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
              L10n.of(context).settingsLearningSection,
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
                Icons.leaderboard,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(L10n.of(context).settingsRanking),
              subtitle: Text(L10n.of(context).rankingSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Cupertino ルートにすると Android でも右スワイプで戻れる
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    settings: const RouteSettings(name: RankingScreen.routeName),
                    builder: (context) => const RankingScreen(),
                  ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.graphic_eq,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(L10n.of(context).settingsToneGuide),
              subtitle: Text(L10n.of(context).settingsToneGuideSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
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
                L10n.of(context).settingsResetLearningData,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle:
                  Text(L10n.of(context).settingsResetLearningDataSubtitle),
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
      contentPadding: EdgeInsets.zero,
      secondary: Icon(
        Icons.notifications_active,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(L10n.of(context).settingsDailyNotification),
      subtitle: Text(L10n.of(context).settingsDailyNotificationSubtitle),
      value: enabled,
      onChanged: (value) async {
        final applied = await ref
            .read(settingsControllerProvider.notifier)
            .setDailyReminderEnabled(value);
        if (!applied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(L10n.of(context).settingsAllowNotificationInOsSettings),
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
      title: Text(L10n.of(context).settingsNotificationTime),
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
        title: Text(L10n.of(context).settingsNotificationTime),
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
    // Premium またはトライアル中はテーマ選択可。
    final canSelect = ref.watch(effectivePremiumProvider);
    final currentTopic = ref.watch(generationParamsProvider)['topic'];

    final displayLabel = canSelect
        ? topicShortLabel(L10n.of(context), currentTopic)
        : L10n.of(context).settingsTopicRandom;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.category,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(L10n.of(context).settingsTopic),
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
        title: Text(L10n.of(context).settingsResetTitle),
        content: Text(L10n.of(context).settingsResetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              L10n.of(context).commonReset,
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
          SnackBar(content: Text(L10n.of(context).settingsResetDone)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).settingsResetFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildVocabScoreInline() {
    final statsAsync = ref.watch(vocabStatsProvider);
    // 体験中はサーバー側も語彙上限を外しているので、表示も合わせる。
    final isPremium = ref.watch(effectivePremiumProvider);

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return statsAsync.when(
      data: (stats) {
        final displayVocab = isPremium
            ? stats.estimatedVocab
            : stats.estimatedVocab.clamp(0, freeVocabScoreLimit).toInt();
        final level =
            vocabLevelLabel(L10n.of(context), vocabLevel(displayVocab));
        final threshold =
            isPremium ? _nextVocabThreshold(displayVocab) : freeVocabScoreLimit;
        final progress = (displayVocab / threshold).clamp(0.0, 1.0).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  L10n.of(context).vocabWords(displayVocab),
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
                  ? L10n.of(context)
                      .settingsNextLevelIn(threshold - displayVocab)
                  : L10n.of(context)
                      .settingsFreeVocabLimit(freeVocabScoreLimit),
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
          SnackBar(content: Text(L10n.of(context).settingsCouldNotOpenUrl)),
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
                  L10n.of(context).settingsAbout,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${L10n.of(context).appTitle} v${AppConfig.appVersion}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              L10n.of(context).settingsTagline,
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
              title: Text(L10n.of(context).settingsPrivacyPolicy),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConfig.privacyPolicyUrl),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(L10n.of(context).settingsTerms),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _launchUrl(AppConfig.termsOfServiceUrl),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: Text(L10n.of(context).settingsContact),
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
