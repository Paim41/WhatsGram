import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/app/controller.dart';
import 'package:whatsgram/app/theme.dart';
import 'package:whatsgram/features/auth/auth_screen.dart';

void main() {
  testWidgets('export real welcome screen previews', (tester) async {
    final fontPath = const String.fromEnvironment('PREVIEW_FONT');
    if (fontPath.isEmpty) {
      throw StateError(
        'Provide PREVIEW_FONT pointing to a local TrueType font.',
      );
    }
    await tester.runAsync(() async {
      final loader = FontLoader('PreviewFont')
        ..addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    });
    final app = AppController();
    for (final entry in {
      'desktop': const Size(1200, 800),
      'mobile': const Size(390, 844),
    }.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WhatsGramTheme.build(Brightness.light).copyWith(
              textTheme: WhatsGramTheme.build(
                Brightness.light,
              ).textTheme.apply(fontFamily: 'PreviewFont'),
            ),
            home: AuthScreen(app: app),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/branding/whatsgram_logo.png'),
          tester.element(find.byType(AuthScreen)),
        );
      });
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/images').create(recursive: true);
        await File(
          'docs/images/welcome-${entry.key}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }, skip: !const bool.fromEnvironment('EXPORT_PREVIEWS'));
}
