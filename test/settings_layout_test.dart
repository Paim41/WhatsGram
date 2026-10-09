import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/app/controller.dart';
import 'package:whatsgram/app/theme.dart';
import 'package:whatsgram/features/media/export_manager.dart';
import 'package:whatsgram/features/settings/settings_screen.dart';
import 'package:whatsgram/workspace/sync/workspace_sync.dart';
import 'conversation_layout_test.dart' show ConversationClient;
import 'workspace_sync_test.dart' show MemoryStore;

class SettingsTestApp extends AppController {
  @override
  Future<void> savePreferences() async => notifyListeners();
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(360, 740),
    const Size(1440, 960),
  ]) {
    testWidgets('settings selection stays stable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const preview = bool.fromEnvironment('EXPORT_PREVIEWS');
      if (preview) {
        await tester.runAsync(() async {
          final font = FontLoader('PreviewFont')
            ..addFont(
              File(
                'C:/Windows/Fonts/segoeui.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              File(
                'C:/Projects/WhatsGramFlutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes().then(ByteData.sublistView),
            );
          await icons.load();
        });
      }
      final client = ConversationClient();
      final app = SettingsTestApp()
        ..client = client
        ..me = {'id': 10, 'first_name': 'Test account'}
        ..workspace = WorkspaceSync(client, MemoryStore(), '10')
        ..exports = ExportManager(client, MemoryStore(), '10');
      final boundary = GlobalKey();
      final theme = WhatsGramTheme.build(
        size.width > 900 ? Brightness.dark : Brightness.light,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: preview
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'PreviewFont'),
                )
              : theme,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(size.width == 360 ? 1.5 : 1),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: AnimatedBuilder(
                  animation: app,
                  builder: (_, _) => SettingsScreen(app: app),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('System'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('media-video')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const ValueKey('media-video')));
      final nextBefore = tester.getTopLeft(
        find.text('Maximum automatic export size'),
      );
      await tester.tap(find.byKey(const ValueKey('media-video')));
      await tester.pumpAndSettle();
      expect(app.exports!.preferences.categories, contains('video'));
      expect(tester.getRect(find.byKey(const ValueKey('media-video'))), before);
      expect(
        tester.getTopLeft(find.text('Maximum automatic export size')),
        nextBefore,
      );
      expect(tester.takeException(), isNull);
      if (preview) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/images/settings-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/images/settings-top-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
