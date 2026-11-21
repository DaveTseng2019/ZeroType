import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/local_stt_diagnosis.dart';

const _reservedLog = [
  '18:19:12 模型就緒 cuda:0，耗時 9.5 秒（已暖機）',
  'INFO:     Application startup complete.',
  "ERROR:    [Errno 13] error while attempting to bind on address ('127.0.0.1', 8123): [winerror 10013] 嘗試存取通訊端被拒絕，因為存取權限不足。",
  'INFO:     Waiting for application shutdown.',
  'INFO:     Application shutdown complete.',
];

void main() {
  test('實際記錄 → portReserved、port 8123', () {
    final f = diagnoseLocalSttLog(_reservedLog);
    expect(f, isNotNull);
    expect(f!.kind, LocalSttFailureKind.portReserved);
    expect(f.port, 8123);
    expect(f.tail, _reservedLog);
  });

  test('winerror 10048 → portInUse', () {
    final f = diagnoseLocalSttLog([
      "ERROR:    [Errno 10048] error while attempting to bind on address ('127.0.0.1', 8123): [winerror 10048] 通常每個通訊端位址只允許使用一次。",
    ]);
    expect(f!.kind, LocalSttFailureKind.portInUse);
    expect(f.port, 8123);
  });

  test('其他 winerror → crashed，仍帶 port', () {
    final f = diagnoseLocalSttLog([
      "ERROR:    error while attempting to bind on address ('0.0.0.0', 9000): [WinError 99999] x",
    ]);
    expect(f!.kind, LocalSttFailureKind.crashed);
    expect(f.port, 9000);
  });

  test('Traceback → crashed，沒有 port', () {
    final f = diagnoseLocalSttLog([
      'Traceback (most recent call last):',
      '  File "shim.py", line 1, in <module>',
      'ImportError: boom',
    ]);
    expect(f!.kind, LocalSttFailureKind.crashed);
    expect(f.port, isNull);
  });

  test('正常啟動訊息 → null', () {
    expect(
      diagnoseLocalSttLog([
        '18:19:12 模型就緒 cuda:0，耗時 9.5 秒（已暖機）',
        'INFO:     Application startup complete.',
        'INFO:     Uvicorn running on http://127.0.0.1:8123 (Press CTRL+C to quit)',
      ]),
      isNull,
    );
  });

  test('空清單 → null', () {
    expect(diagnoseLocalSttLog(const []), isNull);
  });

  test('tail 最多 10 行，且不含空白行', () {
    final lines = [
      for (var i = 0; i < 20; i++) ...['line $i', ''],
      'Traceback (most recent call last)',
    ];
    final f = diagnoseLocalSttLog(lines)!;
    expect(f.tail.length, 10);
    expect(f.tail.last, 'Traceback (most recent call last)');
    expect(f.tail.every((l) => l.trim().isNotEmpty), isTrue);
  });
}
