import 'package:flutter/material.dart';
import 'features/map/home_map_screen.dart';

void main() {
  runApp(const ShouldAIApp());
}

class ShouldAIApp extends StatelessWidget {
  const ShouldAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShouldAI',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      home: const HomeMapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
