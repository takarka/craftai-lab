import 'package:flutter/material.dart';

void main() {
  runApp(const BuilderApp());
}

class BuilderApp extends StatelessWidget {
  const BuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Builder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Builder')),
        body: const SizedBox.expand(),
      ),
    );
  }
}
