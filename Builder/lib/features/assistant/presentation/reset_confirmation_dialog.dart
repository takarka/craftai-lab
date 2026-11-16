import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Legacy entry points now lead to the per-agent actions.
Future<void> showResetConfirmationDialog(
  BuildContext context, {
  required String ownerId,
}) async {
  context.go('/agents');
}
