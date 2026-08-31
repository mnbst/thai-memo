import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/l10n/app_language.dart';
import '../../core/theme/app_colors.dart';
import '../../data/datasources/backend_api_service.dart';
import '../../l10n/app_localizations.dart';
import '../../data/datasources/local/database_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/leaderboard_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../../services/push_notification_service.dart';
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
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppConfig.screenPadding,
          4,
          AppConfig.screenPadding,
          AppConfig.screenPadding,
        ),
        children: [
          // 語彙スコアは設定ではなく成果なので、設定の並びの外に置く。
          _buildVocabScoreCard(),
          _buildPremiumPitch(),
          _buildSection(l10n.settingsAccount, _buildAccountTiles()),
          _buildSection(l10n.settingsLearningSection, _buildLearningTiles()),
          _buildSection(l10n.settingsDisplay, _buildDisplayTiles()),
          _buildSection(l10n.settingsAbout, _buildAboutTiles()),
          const SizedBox(height: 28),
          _buildFooter(),
        ],
      ),
    );
  }

  /// 見出し＋1枚のカード。設定項目はカードを分けず、罫線で区切って積む。
  Widget _buildSection(String label, List<Widget> tiles) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08 * 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Divider(color: theme.colorScheme.outlineVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: AppConfig.defaultPadding,
                    endIndent: AppConfig.defaultPadding,
                  ),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Free 向けの課金導線。プラン行は「今どちらか」を示すだけなので、
  /// 何が増えるのかはここで別に見せる。
  Widget _buildPremiumPitch() {
    if (ref.watch(effectivePremiumProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Material(
        color: AppColors.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          onTap: () =>
              PaywallBottomSheet.show(context, source: 'settings_pitch'),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.42)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 20, color: AppColors.goldInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.premiumHint1Title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7A5E22),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.premiumHint1Body,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: const Color(0xFF8A7444)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.goldInk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// アプリ名とタグライン。読ませる情報ではないので、面を持たせず末尾に置く。
  Widget _buildFooter() {
    final theme = Theme.of(context);
    return Text(
      '${L10n.of(context).settingsTagline}　·　v${AppConfig.appVersion}',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  /// アカウントとプラン。
  List<Widget> _buildAccountTiles() {
    final authState = ref.watch(authControllerProvider);
    final nickname = ref.watch(myNicknameProvider).valueOrNull;
    final l10n = L10n.of(context);

    return [
      // 名前はランキングでの表示名（サーバー採番のタイ人名）を出す。
      // メールアドレスは本人以外が覗いても意味を持つ情報なので、設定を
      // 開いただけで画面に出しておく理由がない。
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(
          authState.isLinked
              ? (nickname ?? authState.displayName ?? l10n.settingsUser)
              : l10n.settingsGuest,
        ),
        subtitle: authState.isLinked
            ? (nickname != null ? Text(l10n.settingsRankingName) : null)
            : Text(l10n.settingsNotSignedIn),
        trailing: authState.isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      Consumer(
        builder: (context, ref, _) {
          // 体験中は課金と同じ機能が使えているので、そのことを出す。
          // 「課金しているか」の表示なので Premium とは別ラベルにする。
          // 判定が付くまでは何も出さない（free → 体験中 → Premium と
          // 段階的にぶれて見えるのを避ける）。
          final plan = ref.watch(planStatusProvider).valueOrNull;
          final label = switch (plan) {
            PlanStatus.premium => 'Premium',
            PlanStatus.trial => l10n.settingsPlanTrial,
            PlanStatus.free => 'Free',
            null => null,
          };
          final highlighted =
              plan == PlanStatus.premium || plan == PlanStatus.trial;
          final theme = Theme.of(context);
          return ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(l10n.settingsPlan),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: highlighted ? FontWeight.w700 : null,
                      color: highlighted
                          ? AppColors.goldInk
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () =>
                PaywallBottomSheet.show(context, source: 'settings_plan'),
          );
        },
      ),
      if (authState.isLinked)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: authState.isLoading ? null : _deleteAccount,
                child: Text(
                  l10n.settingsDeleteAccount,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: authState.isLoading ? null : _signOut,
                child: Text(l10n.settingsSignOut),
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.all(AppConfig.defaultPadding),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: authState.isLoading ? null : _signIn,
              icon: const Icon(Icons.login),
              label: Text(l10n.settingsSignInToSave),
            ),
          ),
        ),
    ];
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

  /// 表示（フォント・言語）。
  List<Widget> _buildDisplayTiles() {
    final currentFont = ref.watch(fontFamilyProvider);
    final l10n = L10n.of(context);

    return [
      ListTile(
        leading: const Icon(Icons.text_fields),
        title: Text(l10n.settingsFont),
        trailing: _buildValueTrailing(currentFont.displayName),
        onTap: () => _showFontPicker(currentFont),
      ),
      // 言語は初回起動でストア地域から1回決めて保存し、以後は再評価しない。
      // 自動判定を外すと**戻す手段が無く**、ストア地域と実際の使用言語が
      // 違うユーザー（日本在住の英語話者、海外在住の日本語話者）は
      // 再インストールするまで読めない言語で使い続けることになる。
      // 履歴に日英が混ざる点はダイアログの注記で伝える。
      ListTile(
        leading: const Icon(Icons.language),
        title: Text(l10n.settingsLanguage),
        subtitle: Text(l10n.settingsLanguageSubtitle),
        trailing: _buildValueTrailing(ref.watch(appLanguageProvider).displayName),
        onTap: () => _showLanguagePicker(ref.read(appLanguageProvider)),
      ),
      // 体験終了ダイアログは期限が来ないと出ないので、見た目の確認用に
      // dev だけ手動で開けるようにしておく。
      if (AppConfig.isDev)
        ListTile(
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
    ];
  }

  /// 右端の「現在の値 ＞」。行の主役は左のラベルなので、値は沈めて置く。
  Widget _buildValueTrailing(String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right),
      ],
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

  /// 学習設定。声調ガイドを先頭に置くのは、設定ではなく読み物で、
  /// ここを開いた人がいちばん手に取りやすいため。
  List<Widget> _buildLearningTiles() {
    final l10n = L10n.of(context);
    return [
      ListTile(
        leading: const Icon(Icons.graphic_eq),
        title: Text(l10n.settingsToneGuide),
        subtitle: Text(l10n.settingsToneGuideSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Cupertino ルートにすると Android でも右スワイプで戻れる
          Navigator.push(
            context,
            CupertinoPageRoute(
              settings: const RouteSettings(name: ToneGuideScreen.routeName),
              builder: (context) => const ToneGuideScreen(),
            ),
          );
        },
      ),
      _buildTopicSelectTile(),
      _buildDailyReminderTile(),
      _buildReminderTimeTile(),
      ListTile(
        leading: const Icon(Icons.leaderboard_outlined),
        title: Text(l10n.settingsRanking),
        subtitle: Text(l10n.rankingSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
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
        leading: Icon(
          Icons.restart_alt,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(
          l10n.settingsResetLearningData,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        subtitle: Text(l10n.settingsResetLearningDataSubtitle),
        onTap: _resetLearningData,
      ),
    ];
  }

  /// 毎日例文のプッシュ通知トグル。
  ///
  /// OSの通知許可が拒否されている場合はアプリ側では有効にできないため、
  /// 状態をオフのままにして端末設定への案内を出す。
  Widget _buildDailyReminderTile() {
    final enabled = ref.watch(dailyReminderEnabledProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(L10n.of(context).settingsDailyNotification),
      subtitle: Text(L10n.of(context).settingsDailyNotificationSubtitle),
      value: enabled,
      onChanged: (value) async {
        final result = await ref
            .read(settingsControllerProvider.notifier)
            .setDailyReminderEnabled(value);
        // pending（許可済み・登録待ち）でOS設定へ誘導すると誤解を招く。
        if (result == PushEnableResult.denied && mounted) {
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
      leading: const Icon(Icons.local_offer_outlined),
      title: Text(L10n.of(context).settingsTopic),
      // テーマは「今どれか」がすぐ要る情報なので、副題ではなく右端に置く。
      trailing: canSelect
          ? _buildValueTrailing(displayLabel)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                Icon(Icons.lock,
                    size: 18, color: Theme.of(context).colorScheme.outline),
              ],
            ),
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

  /// 語彙スコア。設定の中でここだけが成果なので、深藍の面で見せる。
  Widget _buildVocabScoreCard() {
    final statsAsync = ref.watch(vocabStatsProvider);
    // 体験中はサーバー側も語彙上限を外しているので、表示も合わせる。
    final isPremium = ref.watch(effectivePremiumProvider);
    final l10n = L10n.of(context);

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: AppColors.onIndigo),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return Card(
            color: AppColors.indigo,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.heroBorderRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: statsAsync.when(
                data: (stats) {
                  final displayVocab = isPremium
                      ? stats.estimatedVocab
                      : stats.estimatedVocab
                          .clamp(0, freeVocabScoreLimit)
                          .toInt();
                  final levelId = vocabLevel(displayVocab);
                  final level = vocabLevelLabel(l10n, levelId);
                  final threshold = isPremium
                      ? _nextVocabThreshold(displayVocab)
                      : freeVocabScoreLimit;
                  final progress =
                      (displayVocab / threshold).clamp(0.0, 1.0).toDouble();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              l10n.vocabScore,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.06 * 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.vocabWords(displayVocab),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: AppColors.gold,
                          backgroundColor: cs.onSurface.withValues(alpha: 0.14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(vocabLevelIcon(levelId),
                              size: 17, color: AppColors.gold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPremium
                                  ? '$level　·　'
                                      '${l10n.settingsNextLevelIn(threshold - displayVocab)}'
                                  : '$level　·　'
                                      '${l10n.settingsFreeVocabLimit(freeVocabScoreLimit)}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFFD8BE8A)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox(
                  height: 74,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, __) => SizedBox(
                  height: 74,
                  child: Center(
                    child: Text(
                      l10n.vocabScoreCalculating,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
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

  /// アプリについて。
  List<Widget> _buildAboutTiles() {
    final l10n = L10n.of(context);
    return [
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(l10n.settingsPrivacyPolicy),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _launchUrl(AppConfig.privacyPolicyUrl),
      ),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(l10n.settingsTerms),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _launchUrl(AppConfig.termsOfServiceUrl),
      ),
      ListTile(
        leading: const Icon(Icons.mail_outline),
        title: Text(l10n.settingsContact),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: ContactFormScreen.routeName),
            builder: (_) => const ContactFormScreen(),
          ),
        ),
      ),
    ];
  }
}
