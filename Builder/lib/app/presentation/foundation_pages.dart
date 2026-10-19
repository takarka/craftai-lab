import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui_kit/ui_kit.dart';
import '../localization/app_localizations.dart';
import '../providers.dart';

class FoundationPage extends StatelessWidget {
  const FoundationPage({super.key, required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: const [LanguageSelector()]),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: BuilderCard(child: Text(message)),
          ),
        ),
      ),
    ),
  );
}

class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: AppLocalizations.of(context).languageLabel,
    icon: const Icon(Icons.language),
    onSelected: (language) =>
        ref.read(appLocaleProvider.notifier).select(Locale(language)),
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'ru', child: Text('Русский')),
      PopupMenuItem(value: 'kk', child: Text('Қазақша')),
    ],
  );
}

class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});

  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _floatAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _floatAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(curved);
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(curved);
    _glowAnimation = Tween<double>(begin: 0.15, end: 0.45).animate(curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    if (session.hasError) {
      _controller.stop();
      return FoundationPage(
        title: strings.appTitle,
        message: strings.sessionUnavailable,
      );
    }
    return Scaffold(
      backgroundColor: BuilderColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Semantics(
              label: strings.starting,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Assistant Character with levitating & breathing animation
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Ambient radial glow behind the assistant
                          Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  BuilderColors.primaryTint.withValues(
                                    alpha: _glowAnimation.value,
                                  ),
                                  BuilderColors.primaryTint.withValues(
                                    alpha: 0.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Subtle dynamic ground shadow
                          Positioned(
                            bottom: 10 - (_floatAnimation.value * 0.35),
                            child: Container(
                              width: 80 + (_floatAnimation.value * 1.5),
                              height: 12,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: BuilderColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Hovering assistant character
                          Transform.translate(
                            offset: Offset(0, _floatAnimation.value),
                            child: Transform.scale(
                              scale: _scaleAnimation.value,
                              child: const BuilderCharacter(
                                size: 136,
                                mood: CharacterMood.idle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      // Title: Craft Builder
                      Text(
                        strings.appTitle,
                        style: BuilderType.h1.copyWith(
                          color: BuilderColors.ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Localized status (e.g. "Запуск Craft Builder")
                      Text(
                        strings.starting,
                        style: BuilderType.body.copyWith(
                          color: BuilderColors.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Sleek indeterminate progress bar
                      SizedBox(
                        width: 140,
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: const LinearProgressIndicator(
                            backgroundColor: BuilderColors.primaryTint,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              BuilderColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
