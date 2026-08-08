import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../presentation/providers/settings_provider.dart';

/// BuildContext を持たない層（provider・usecase）から文言を引くための入口。
///
/// UI は `L10n.of(context)` を使うこと。こちらは MaterialApp の locale ではなく
/// 設定値から直に引くが、`MaterialApp.locale` も同じ設定に追従しているので一致する。
final l10nProvider = Provider<L10n>((ref) {
  return lookupL10n(ref.watch(appLanguageProvider).locale);
});
