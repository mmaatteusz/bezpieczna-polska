import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bezpieczna_polska/main.dart';
import 'package:bezpieczna_polska/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cached SG operational notice appears in the dedicated border section', (tester) async {
    final now=DateTime.now().toUtc();
    final status={
      'hazardLevel':'UNKNOWN',
      'displayText':'Brak wystarczających aktualnych danych',
      'validUntil':now.add(const Duration(minutes:5)).toIso8601String(),
    };
    final event={
      'id':'SG-20001',
      'title':'Utrudnienia na przejściu granicznym w Hrebennem',
      'description':'Straż Graniczna informuje o czasowych utrudnieniach w odprawach.',
      'eventType':'BORDER',
      'severity':'NORMAL',
      'verification':'CONFIRMED',
      'lifecycle':'UNKNOWN',
      'messageContext':'ACTUAL',
      'regions':['06'],
      'geographicScope':'REGIONAL',
      'publishedAt':null,
      'publicationDate':'2026-09-21',
      'retrievedAt':now.toIso8601String(),
      'validFrom':null,
      'validTo':null,
      'sources':[
        {'id':'SG','name':'Straż Graniczna','url':'https://www.strazgraniczna.pl/pl/aktualnosci/20001,Utrudnienia-na-przejsciu-granicznym-w-Hrebennem.html','tier':1}
      ],
      'instructions':<String>[],
      'officialWarning':false,
      'reviewed':false,
      'revision':1,
      'correction':null,
      'latitude':null,
      'longitude':null,
      'locationText':'Utrudnienia na przejściu granicznym w Hrebennem',
      'areaPrecision':'PROVINCE',
      'isDemo':false,
    };
    final snapshot={
      'schemaVersion':1,
      'regionId':'06',
      'serverTime':now.toIso8601String(),
      'status':status,
      'nationalStatus':status,
      'events':[event],
      'sources':[
        {
          'id':'SG',
          'name':'Straż Graniczna — operacyjne informacje graniczne',
          'url':'https://www.strazgraniczna.pl/pl/aktualnosci',
          'state':'HEALTHY',
          'healthStatus':'HEALTHY',
          'lastSuccess':now.toIso8601String(),
          'maxAgeSeconds':3600,
        }
      ],
    };
    SharedPreferences.setMockInitialValues({'snapshot::06':jsonEncode(snapshot),'region':'06'});
    final repo=DataRepository(await SharedPreferences.getInstance());
    await tester.pumpWidget(SafetyApp(repository:repo));
    await tester.pumpAndSettle();

    for (
      var i = 0;
      i < 10 && find.text('Granice • Straż Graniczna').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text('Granice • Straż Graniczna'), findsOneWidget);
    expect(
      find.textContaining('operacyjne informacje o zamknięciach'),
      findsOneWidget,
    );

  });
}
