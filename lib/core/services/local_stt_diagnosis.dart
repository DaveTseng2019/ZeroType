/// 本機辨識端點為什麼沒起來。純 Dart，不碰 FFI，方便單元測試。
enum LocalSttFailureKind { portReserved, portInUse, crashed }

class LocalSttFailure {
  const LocalSttFailure({required this.kind, this.port, required this.tail});

  final LocalSttFailureKind kind;

  /// 綁埠失敗時才有。
  final int? port;

  /// 記錄最後 10 行（非空白行）。
  final List<String> tail;
}

final _bindPattern = RegExp(
  r"error while attempting to bind on address \('[^']*', (\d+)\).*winerror (\d+)",
  caseSensitive: false,
);

/// 看記錄判斷端點為什麼沒起來；看不出失敗就回 null。
///
/// notes: 只認 uvicorn 的綁埠錯誤與 Python traceback 兩種。別的失敗型態
///        （例如被工作管理員殺掉）記錄裡沒有特徵，這裡看不出來，回 null。
LocalSttFailure? diagnoseLocalSttLog(List<String> lines) {
  final tail = lines.where((l) => l.trim().isNotEmpty).toList();
  final last = tail.length <= 10 ? tail : tail.sublist(tail.length - 10);

  for (final line in lines) {
    final m = _bindPattern.firstMatch(line);
    if (m == null) continue;
    final kind = switch (m.group(2)) {
      '10013' => LocalSttFailureKind.portReserved,
      '10048' => LocalSttFailureKind.portInUse,
      _ => LocalSttFailureKind.crashed,
    };
    return LocalSttFailure(
      kind: kind,
      port: int.tryParse(m.group(1)!),
      tail: last,
    );
  }

  if (lines.any((l) => l.contains('Traceback (most recent call last)'))) {
    return LocalSttFailure(kind: LocalSttFailureKind.crashed, tail: last);
  }
  return null;
}
