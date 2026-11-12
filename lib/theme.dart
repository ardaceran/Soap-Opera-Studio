import 'package:flutter/material.dart';

const Color kGold = Color(0xFFE6B450);
const Color kBg = Color(0xFF120A10);
const Color kCard = Color(0xFF1E131B);
const Color kGreen = Color(0xFF4CAF7A);
const Color kBlue = Color(0xFF5AA9E6);
const Color kGrey = Color(0xFF8A7F86);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8E1B3A),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      elevation: 0,
      centerTitle: false,
    ),
  );
}

String usd(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
