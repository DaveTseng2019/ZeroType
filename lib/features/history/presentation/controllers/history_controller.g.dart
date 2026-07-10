// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(historyStats)
final historyStatsProvider = HistoryStatsProvider._();

final class HistoryStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<HistoryStats>,
          HistoryStats,
          FutureOr<HistoryStats>
        >
    with $FutureModifier<HistoryStats>, $FutureProvider<HistoryStats> {
  HistoryStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyStatsHash();

  @$internal
  @override
  $FutureProviderElement<HistoryStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HistoryStats> create(Ref ref) {
    return historyStats(ref);
  }
}

String _$historyStatsHash() => r'e17bfbde16a5b6d6e1871b919abc782820e33801';

@ProviderFor(PlayingRecordId)
final playingRecordIdProvider = PlayingRecordIdProvider._();

final class PlayingRecordIdProvider
    extends $NotifierProvider<PlayingRecordId, String?> {
  PlayingRecordIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playingRecordIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playingRecordIdHash();

  @$internal
  @override
  PlayingRecordId create() => PlayingRecordId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$playingRecordIdHash() => r'eab479aa267ff7b9a45a0ce1758f3b1acecc45bb';

abstract class _$PlayingRecordId extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(HistoryController)
final historyControllerProvider = HistoryControllerProvider._();

final class HistoryControllerProvider
    extends
        $AsyncNotifierProvider<HistoryController, List<TranscriptionRecord>> {
  HistoryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyControllerHash();

  @$internal
  @override
  HistoryController create() => HistoryController();
}

String _$historyControllerHash() => r'57f40d89c0ede9d4646558a5314850fb8dc7e336';

abstract class _$HistoryController
    extends $AsyncNotifier<List<TranscriptionRecord>> {
  FutureOr<List<TranscriptionRecord>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<TranscriptionRecord>>,
              List<TranscriptionRecord>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<TranscriptionRecord>>,
                List<TranscriptionRecord>
              >,
              AsyncValue<List<TranscriptionRecord>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
