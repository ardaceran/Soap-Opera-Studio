import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() => runApp(const SoapOperaApp());

class SoapOperaApp extends StatelessWidget {
  const SoapOperaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soap Opera Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LoginScreen(),
    );
  }
}
