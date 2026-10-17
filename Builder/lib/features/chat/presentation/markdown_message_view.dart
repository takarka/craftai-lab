import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../ui_kit/ui_kit.dart';

class MarkdownMessageView extends StatelessWidget {
  final String text;

  const MarkdownMessageView({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: BuilderType.body.copyWith(color: BuilderColors.ink),
        h1: BuilderType.h1,
        h2: BuilderType.h2,
        h3: BuilderType.h3,
        code: BuilderType.mono.copyWith(
          backgroundColor: BuilderColors.background,
          color: BuilderColors.primary,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: BuilderColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BuilderColors.line),
        ),
      ),
    );
  }
}
