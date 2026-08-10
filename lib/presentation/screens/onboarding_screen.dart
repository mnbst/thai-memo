import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
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
      titleOf: _p1Title,
      descriptionOf: _p1Body,
    ),
    _OnboardingPage(
      icon: Icons.record_voice_over,
      colorType: _ColorType.secondary,
      titleOf: _p2Title,
      descriptionOf: _p2Body,
    ),
    _OnboardingPage(
      icon: Icons.quiz,
      colorType: _ColorType.tertiary,
      titleOf: _p3Title,
      descriptionOf: _p3Body,
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
              child: Text(L10n.of(context).onboardingSkip),
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
                      child: Text(isLastPage
                          ? L10n.of(context).onboardingStart
                          : L10n.of(context).onboardingNext),
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
    required this.titleOf,
    required this.descriptionOf,
  });

  final IconData icon;
  final _ColorType colorType;

  /// 文言は言語で変わるので、値ではなく引き方を持つ。
  final String Function(L10n) titleOf;
  final String Function(L10n) descriptionOf;
}

String _p1Title(L10n l10n) => l10n.onboarding1Title;
String _p1Body(L10n l10n) => l10n.onboarding1Body;
String _p2Title(L10n l10n) => l10n.onboarding2Title;
String _p2Body(L10n l10n) => l10n.onboarding2Body;
String _p3Title(L10n l10n) => l10n.onboarding3Title;
String _p3Body(L10n l10n) => l10n.onboarding3Body;

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
            page.titleOf(L10n.of(context)),
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.descriptionOf(L10n.of(context)),
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
