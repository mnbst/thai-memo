import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analytics_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  static const routeName = 'onboarding';

  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.auto_awesome,
      colorType: _ColorType.primary,
      title: 'AIがタイ語例文を毎日生成',
      description: 'AIが毎日新しいタイ語例文を生成。\n単語ごとの発音・意味の解説や\n音声再生で無理なく学習できます。',
    ),
    _OnboardingPage(
      icon: Icons.edit_note,
      colorType: _ColorType.secondary,
      title: '例文+クイズで学習',
      description: 'まずは3例文でまとめクイズに挑戦！\n慣れたら5例文ごとにクイズが出題されます。\n毎日の学習サイクルで着実にレベルアップ。',
    ),
    _OnboardingPage(
      icon: Icons.trending_up,
      colorType: _ColorType.tertiary,
      title: 'クイズで語彙スコアUP',
      description: '間違えた単語は何度も出題されるので\n自然と覚えられます。\n語彙スコアに合わせて例文の難易度も変化。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(analyticsServiceProvider).logOnboardingStart());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _complete({required bool skipped}) {
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logOnboardingComplete(skipped: skipped),
    );
    widget.onComplete();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete(skipped: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!isLastPage)
            TextButton(
              onPressed: () => _complete(skipped: true),
              child: const Text('スキップ'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _PageContent(page: _pages[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  _DotIndicator(
                    count: _pages.length,
                    current: _currentPage,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _nextPage,
                      child: Text(isLastPage ? 'はじめる' : '次へ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ColorType { primary, secondary, tertiary }

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.colorType,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final _ColorType colorType;
  final String title;
  final String description;
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page});

  final _OnboardingPage page;

  Color _iconColor(ColorScheme cs) => switch (page.colorType) {
        _ColorType.primary => cs.primary,
        _ColorType.secondary => cs.secondary,
        _ColorType.tertiary => cs.tertiary,
      };

  Color _iconBackground(ColorScheme cs) => switch (page.colorType) {
        _ColorType.primary => cs.primaryContainer,
        _ColorType.secondary => cs.secondaryContainer,
        _ColorType.tertiary => cs.tertiaryContainer,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _iconBackground(cs),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 96,
              color: _iconColor(cs),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: tt.bodyLarge?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? cs.primary : cs.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
