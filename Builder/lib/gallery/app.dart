import 'package:flutter/material.dart';

import '../ui_kit/ui_kit.dart';
import 'catalog.dart';

class BuilderGalleryApp extends StatelessWidget {
  const BuilderGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = ['foundations', 'controls', 'compositions', 'character'];
    final section = sections.indexOf(
      Uri.base.queryParameters['section'] ?? 'foundations',
    );
    return MaterialApp(
      title: 'Craft Builder · UI Kit · DEV',
      debugShowCheckedModeBanner: false,
      theme: BuilderTheme.light,
      home: BuilderCatalog(initialSection: section < 0 ? 0 : section),
    );
  }
}
