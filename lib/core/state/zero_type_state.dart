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
    this.amplitude = 0.0,
    this.errorMessage,
    this.result,
  });

  final ZeroTypeStatus status;
  final double amplitude;
  final String? errorMessage;
  final String? result;

  bool get isActive => status != ZeroTypeStatus.idle;

  ZeroTypeState copyWith({
    ZeroTypeStatus? status,
    double? amplitude,
    String? errorMessage,
    String? result,
  }) =>
      ZeroTypeState(
        status: status ?? this.status,
        amplitude: amplitude ?? this.amplitude,
        errorMessage: errorMessage ?? this.errorMessage,
        result: result ?? this.result,
      );
}
