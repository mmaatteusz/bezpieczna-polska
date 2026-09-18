import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

void main() {
  setUpAll(() async {
    for (final f in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(f.key);
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('test/fonts/${f.value}').readAsBytesSync()),
        ),
      );
      await loader.load();
    }
  });
  testWidgets('phone layout, offline map, navigation and deliberate SOS', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final r = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(SafetyApp(repository: r));
    await tester.pumpAndSettle();
    expect(find.text('Brak bieżącej oceny sytuacji'), findsNWidgets(2));
    expect(find.text('Skonfiguruj serwer danych'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/status.png'),
    );
    await tester.runAsync(() async {
      await rootBundle.loadString('assets/europe.geojson');
      await tester.tap(find.text('Mapa').last);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/map.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Schronienie').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Brak zweryfikowanego pakietu schronienia'),
      findsOneWidget,
    );
    await tester.tap(find.text('Pomoc').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('112 • Numer alarmowy'));
    await tester.pumpAndSettle();
    expect(find.text('Otworzyć telefon z numerem 112?'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('200 percent font on phone does not overflow status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final r = DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Home(repository: r, onTheme: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
