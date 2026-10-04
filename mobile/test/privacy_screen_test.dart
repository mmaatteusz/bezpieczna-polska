import 'package:bezpieczna_polska/privacy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy screen scrolls at 200% text on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    const url = 'https://bezpiecznapolska.pl/privacy';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PrivacyScreen(
          policyUrl: url,
          openLink: (value) => opened = value,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Otwórz pełną politykę prywatności'),
      250,
      maxScrolls: 40,
    );
    await tester.tap(find.text('Otwórz pełną politykę prywatności'));
    expect(opened, url);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing URL does not offer a broken policy link', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyScreen(policyUrl: '', openLink: (_) => fail('No URL')),
      ),
    );
    expect(find.text('Otwórz pełną politykę prywatności'), findsNothing);
  });
}
