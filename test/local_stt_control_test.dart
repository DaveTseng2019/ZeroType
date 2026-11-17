import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/local_stt_control.dart';

void main() {
  late Directory dir;
  late List<String> executed;
  late LocalSttControl control;

  File request() => File('${dir.path}/${LocalSttControl.requestName}');
  Map<String, dynamic> result() => jsonDecode(
      File('${dir.path}/${LocalSttControl.resultName}').readAsStringSync())
      as Map<String, dynamic>;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lsc_test_');
    executed = [];
    control = LocalSttControl(
      dir: dir,
      execute: (c) async {
        executed.add(c);
        return c == 'stop' ? 'stopped' : 'restarted';
      },
    );
  });

  tearDown(() async {
    await control.dispose();
    dir.deleteSync(recursive: true);
  });

  test('執行請求、刪掉請求檔、結果帶回 id', () async {
    request().writeAsStringSync('restart abc123\n');
    await control.processPending();
    expect(executed, ['restart']);
    expect(request().existsSync(), isFalse);
    expect(result()['id'], 'abc123');
    expect(result()['command'], 'restart');
    expect(result()['result'], 'restarted');
  });

  test('大小寫不分', () async {
    request().writeAsStringSync('STOP');
    await control.processPending();
    expect(executed, ['stop']);
    expect(result()['result'], 'stopped');
  });

  test('不認得的指令不執行，結果寫 unknownCommand', () async {
    request().writeAsStringSync('format c:');
    await control.processPending();
    expect(executed, isEmpty);
    expect(result()['result'], 'unknownCommand');
  });

  test('空的請求檔視為寫到一半，留著不處理', () async {
    request().writeAsStringSync('');
    await control.processPending();
    expect(executed, isEmpty);
    expect(request().existsSync(), isTrue);
  });

  test('啟動前留下的請求丟掉不執行', () async {
    request().writeAsStringSync('stop old1');
    await control.start();
    expect(executed, isEmpty);
    expect(request().existsSync(), isFalse);
    expect(result()['id'], 'old1');
    expect(result()['result'], 'ignoredStale');
  });

  test('啟動後寫入的請求由監看觸發', () async {
    await control.start();
    request().writeAsStringSync('restart w1');
    for (var i = 0; i < 50 && executed.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(executed, ['restart']);
    expect(result()['id'], 'w1');
  });

  test('執行丟例外時結果寫 error', () async {
    final failing = LocalSttControl(
      dir: dir,
      execute: (_) async => throw StateError('boom'),
    );
    request().writeAsStringSync('start');
    await failing.processPending();
    expect(result()['result'], startsWith('error:'));
  });
}
