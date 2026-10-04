import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  const device = 'emulator-5554';
  Future<ProcessResult> adb(List<String> args) =>
      Process.run('adb', ['-s', device, ...args]);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 18443);
  final reverse = await adb(['reverse', 'tcp:18443', 'tcp:18443']);
  if (reverse.exitCode != 0) {
    throw StateError('Could not connect native tap driver: ${reverse.stderr}');
  }
  var taps = 0;
  server.listen((socket) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first;
      final request = jsonDecode(line) as Map<String, dynamic>;
      final x = request['x'] as int, y = request['y'] as int;
      if (x < 0 || y < 0 || x >= request['width'] || y >= request['height']) {
        throw StateError('Tap outside Flutter view');
      }
      var top = 0;
      if ((request['paddingTop'] as num) == 0) {
        final display = await adb(['shell', 'dumpsys', 'window', 'displays']);
        final dump = display.stdout as String;
        final stable =
            RegExp(r'(?:mStable|stable)=\[(\d+),(\d+)\]').firstMatch(dump) ??
            RegExp(r'(?:mStable|stable)=Rect\((\d+),\s*(\d+)').firstMatch(dump);
        if (stable == null) {
          throw StateError('Cannot resolve Android content origin: $dump');
        }
        top = int.parse(stable.group(2)!);
      }
      final capture = await Process.run('adb', [
        '-s',
        device,
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      if (capture.exitCode == 0) {
        final file = File('../output/native-map-before-tap-${++taps}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(capture.stdout as List<int>);
      }
      final result = await adb(['shell', 'input', 'tap', '$x', '${y + top}']);
      socket.writeln(
        jsonEncode({
          'ok': result.exitCode == 0,
          'screenX': x,
          'screenY': y + top,
          'error': result.stderr,
        }),
      );
      await socket.flush();
    } catch (error) {
      socket.writeln(jsonEncode({'ok': false, 'error': '$error'}));
      await socket.flush();
    } finally {
      await socket.close();
    }
  });
  try {
    await integrationDriver();
  } finally {
    await adb(['reverse', '--remove', 'tcp:18443']);
    await server.close();
  }
}
