import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/auth_screen.dart';
import '../ui/shared/shell.dart';
import 'controller.dart';
import 'theme.dart';

class WhatsGramApp extends ConsumerWidget {
  const WhatsGramApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return MaterialApp(
      title: 'WhatsGram',
      debugShowCheckedModeBanner: false,
      theme: WhatsGramTheme.build(Brightness.light),
      darkTheme: WhatsGramTheme.build(Brightness.dark),
      themeMode: app.theme,
      home: app.ready && app.workspace != null
          ? WhatsGramShell(app: app)
          : AuthScreen(app: app),
    );
  }
}
