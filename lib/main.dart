import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/theme.dart';

import 'firebase_options.dart';
import 'flame/pages/menu_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const QuoridorApp());
}

class QuoridorApp extends StatelessWidget {
  const QuoridorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quoridor - Strategic Board Game',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const MenuPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
