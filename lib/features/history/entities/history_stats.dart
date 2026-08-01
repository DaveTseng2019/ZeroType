class HistoryStats {
  const HistoryStats({
    required this.totalCount,
    required this.totalCostUsd,
  });

  final int totalCount;
  final double totalCostUsd;

  static const zero = HistoryStats(totalCount: 0, totalCostUsd: 0.0);

  HistoryStats addRecord(double? costUsd) => HistoryStats(
        totalCount: totalCount + 1,
        totalCostUsd: totalCostUsd + (costUsd ?? 0.0),
      );

  Map<String, dynamic> toJson() => {
        'totalCount': totalCount,
        'totalCostUsd': totalCostUsd,
      };

  factory HistoryStats.fromJson(Map<String, dynamic> json) => HistoryStats(
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        totalCostUsd: (json['totalCostUsd'] as num?)?.toDouble() ?? 0.0,
      );
}
