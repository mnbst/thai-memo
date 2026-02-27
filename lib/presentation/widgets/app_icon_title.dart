import 'package:flutter/material.dart';

/// AppBarのtitleにアイコン+テキストを表示するウィジェット
class AppIconTitle extends StatelessWidget {
  final String title;

  const AppIconTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/appicon.png', width: 28, height: 28),
        ),
        const SizedBox(width: 8),
        Text(title),
      ],
    );
  }
}
