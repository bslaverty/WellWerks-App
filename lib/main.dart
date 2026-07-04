import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const WellWerksApp());
}

class WellWerksApp extends StatelessWidget {
  const WellWerksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WellWerks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0C0D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFCDA56A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const HomeScreen(),
    );
  }
}
