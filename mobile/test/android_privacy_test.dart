import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main(){
  test('Android manifest removes unused location permissions',(){
    final text=File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for(final permission in ['ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION']){
      final line=text.split('\n').firstWhere((value)=>value.contains(permission));
      expect(line,contains('tools:node="remove"'));
    }
  });
}
