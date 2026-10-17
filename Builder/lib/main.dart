import 'package:flutter/material.dart';
import 'gallery/catalog.dart';
import 'ui_kit/ui_kit.dart';

void main() {
  runApp(const BuilderApp());
}

class BuilderApp extends StatelessWidget {
  const BuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final section = [
      'foundations',
      'controls',
      'compositions',
      'character',
    ].indexOf(Uri.base.queryParameters['section'] ?? 'foundations');
    return MaterialApp(
      title: 'Craft Builder · UI Kit',
      debugShowCheckedModeBanner: false,
      theme: BuilderTheme.light,
      home: BuilderCatalog(initialSection: section < 0 ? 0 : section),
    );
  }
}
