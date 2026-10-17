import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui_kit/ui_kit.dart';
import 'localization/app_localizations.dart';
import 'presentation/foundation_pages.dart';
import 'providers.dart';
import 'router/app_router.dart';

class BuilderApp extends ConsumerWidget {
  const BuilderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final configured = ref.watch(appConfigProvider) != null;
    if (!configured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BuilderTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => FoundationPage(
            title: AppLocalizations.of(context).appTitle,
            message: AppLocalizations.of(context).configurationError,
          ),
        ),
      );
    }
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: BuilderTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => ref.watch(developmentPreviewProvider)
          ? Column(
              children: [
                Material(
                  color: BuilderColors.warningTint,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        AppLocalizations.of(context).onbPreviewBanner,
                        style: BuilderType.small,
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            )
          : child!,
    );
  }
}
