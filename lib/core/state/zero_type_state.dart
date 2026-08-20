enum ZeroTypeStatus {
  idle,
  /// 已開麥克風，但還在等它真的送出聲音（藍牙 HFP 協商）。
  /// 這段還不算錄音：圖示不變色，收到的音訊會被丟掉。
  warmingUp,
  recording,
  cancelling,
  saving,
  transcribing,
  done,
  error,
}

class ZeroTypeState {
  const ZeroTypeState({
    this.status = ZeroTypeStatus.idle,
    this.quick = false,
    this.amplitude = 0.0,
    this.errorMessage,
    this.result,
  });

  final ZeroTypeStatus status;

  /// 這次是精簡模式熱鍵按下的（講完自動停、貼上後自動送出），不是全局熱鍵。
  final bool quick;
  final double amplitude;
  final String? errorMessage;
  final String? result;

  bool get isActive => status != ZeroTypeStatus.idle;

  ZeroTypeState copyWith({
    ZeroTypeStatus? status,
    bool? quick,
    double? amplitude,
    String? errorMessage,
    String? result,
  }) =>
      ZeroTypeState(
        status: status ?? this.status,
        quick: quick ?? this.quick,
        amplitude: amplitude ?? this.amplitude,
        errorMessage: errorMessage ?? this.errorMessage,
        result: result ?? this.result,
      );
}
