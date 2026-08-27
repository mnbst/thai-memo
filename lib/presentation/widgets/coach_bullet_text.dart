import 'package:flutter/material.dart';

/// 本文中の一部だけを強調して描く。初回ガイドの吹き出しと同じ見せ方に揃える。
///
/// [emphasis] が本文に含まれない場合（訳の揺れ）はそのまま描く。強調が
/// 消えるだけで、文が欠けることはない。
class CoachEmphasizedText extends StatelessWidget {
  const CoachEmphasizedText({
    super.key,
    required this.text,
    required this.style,
    this.emphasis,
  });

  final String text;
  final String? emphasis;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = emphasis;
    if (target == null || target.isEmpty) return Text(text, style: style);
    final start = text.indexOf(target);
    if (start < 0) return Text(text, style: style);

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: target,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(start + target.length)),
        ],
      ),
    );
  }
}
