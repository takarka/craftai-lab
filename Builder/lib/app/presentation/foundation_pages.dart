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

class StartupPage extends ConsumerWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    if (session.hasError) {
      return FoundationPage(
        title: strings.appTitle,
        message: strings.sessionUnavailable,
      );
    }
    return Scaffold(
      body: Center(
        child: Semantics(
          label: strings.starting,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return FoundationPage(
      title: strings.onboardingTitle,
      message: strings.onboardingPending,
    );
  }
}
