import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../providers/auth_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import 'contact_form_screen.dart';
import 'paywall_screen.dart';
import 'tone_guide_screen.dart';

/// Settings screen
class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = 'settings';

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
          _buildDisplaySection(),
          const SizedBox(height: 24),
          _buildLearningSection(),
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
              subtitle: authState.email != null ? Text(authState.email!) : null,
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
                    settings:
                        const RouteSettings(name: ToneGuideScreen.routeName),
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
