import 'package:flutter/material.dart';
import 'screens/chat_list_screen.dart';

void main() {
  runApp(const AnogramApp());
}

class AnogramApp extends StatelessWidget {
  const AnogramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anongram',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF40A7E3)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1419),
      ),
      home: const ChatListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
