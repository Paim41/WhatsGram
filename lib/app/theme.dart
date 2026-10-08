import 'dart:io';
import 'package:flutter/material.dart';

class WhatsGramTheme {
  static const blue = Color(0xff2489d4);
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: Platform.isWindows ? 'Segoe UI' : 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: brightness,
        primary: blue,
        surface: dark ? const Color(0xff17212b) : Colors.white,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xff0f1720)
          : const Color(0xfff4f8fc),
      dividerColor: dark ? const Color(0xff293746) : const Color(0xffe3ebf3),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff17212b) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: dark ? const Color(0xfff4f8fc) : const Color(0xff17212b),
      ),
    );
  }
}
