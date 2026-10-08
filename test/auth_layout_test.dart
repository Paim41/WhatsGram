import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsgram/app/controller.dart';
import 'package:whatsgram/features/auth/auth_screen.dart';

void main() {
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('login fits $size with large text and never implies success', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController();
      app.authorization = {
        '@type': 'authorizationStateWaitCode',
        'code_info': {
          'type': {'@type': 'authenticationCodeTypeTelegramMessage'},
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: AuthScreen(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verification code'), findsOneWidget);
      expect(find.textContaining('TelegramMessage'), findsOneWidget);
      expect(app.ready, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
