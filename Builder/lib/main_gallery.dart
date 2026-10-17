import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'gallery/app.dart';

void main() {
  if (kReleaseMode) {
    throw StateError('The UI Kit entrypoint is development-only.');
  }
  runApp(const BuilderGalleryApp());
}
