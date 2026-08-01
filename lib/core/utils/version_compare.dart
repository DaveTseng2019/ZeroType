/// 逐段比對版本號（例如 1.0.10 > 1.0.9），字串比較會比錯。
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(latest);
  final b = parts(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
