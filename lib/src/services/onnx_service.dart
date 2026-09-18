import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// 테스트·PC 재현에서 ONNX Runtime 플러그인 대신 추론을 맡는 쪽.
/// 모델 출력 텐서들을 순서대로(데이터, 형태) 돌려준다.
typedef InferenceBackend = Future<List<({Float32List data, List<int> shape})>>
    Function(String asset, Float32List chw, int size);

/// Raw model outputs: detection head (rank 3) + mask prototypes (rank 4).
class RawOutputs {
  final Float32List det;
  final List<int> detShape;
  final Float32List proto;
  final List<int> protoShape;
  RawOutputs(this.det, this.detShape, this.proto, this.protoShape);
}

/// Wraps a cached ONNX Runtime session (loaded once from a bundled asset).
///
/// 앱은 모델을 두 개 쓴다 — 수간·그을음 **분할**과 수고봉 **경계 검출**. 서로
/// 다른 세션이 필요하므로 인스턴스를 나눠 쓴다([instance], [pole]).
class OnnxService {
  OnnxService._();

  /// 수간·그을음 분할 모델 세션.
  static final OnnxService instance = OnnxService._();

  /// 수고봉 1 m 경계 검출 모델 세션.
  static final OnnxService pole = OnnxService._();

  /// 설정하면 모든 세션이 플러그인 대신 이 함수로 추론한다. 앱의 Dart 분석 코드를
  /// 그대로 PC에서 돌려 현장 사진을 재현할 때 쓴다(test/field_replay_test.dart).
  @visibleForTesting
  static InferenceBackend? testBackend;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  String? _loadedAsset;
  int inputSize = 640;

  bool get isLoaded =>
      _session != null || (testBackend != null && _loadedAsset != null);
  String? get loadedAsset => _loadedAsset;

  Future<void> load(String assetPath) async {
    if (testBackend != null) {
      _loadedAsset = assetPath;
      inputSize = assetPath.contains('1280') ? 1280 : 640;
      return;
    }
    if (_loadedAsset == assetPath && _session != null) return;
    await _session?.close();
    _session = await _ort.createSessionFromAsset(assetPath);
    _loadedAsset = assetPath;
    inputSize = assetPath.contains('1280') ? 1280 : 640;
  }

  /// 에셋이 없으면 조용히 실패한다(수고봉 모델은 선택 사항이라 앱이 죽으면 안 됨).
  Future<bool> tryLoad(String assetPath) async {
    try {
      await load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<RawOutputs> infer(Float32List chw, int size) async {
    final tb = testBackend;
    if (tb != null) {
      final outs = await tb(_loadedAsset!, chw, size);
      final det = outs.firstWhere((o) => o.shape.length == 3);
      final proto = outs.firstWhere((o) => o.shape.length == 4);
      return RawOutputs(det.data, det.shape, proto.data, proto.shape);
    }
    final s = _session;
    if (s == null) {
      throw StateError('ONNX session not loaded');
    }
    final input = await OrtValue.fromList(chw, [1, 3, size, size]);
    final inputName = s.inputNames.first;
    final outputs = await s.run({inputName: input});

    Float32List? det;
    List<int>? detShape;
    Float32List? proto;
    List<int>? protoShape;
    for (final name in s.outputNames) {
      final v = outputs[name];
      if (v == null) continue;
      final sh = v.shape;
      final flat = await v.asFlattenedList();
      final data = Float32List.fromList(flat.cast<double>());
      if (sh.length == 3) {
        det = data;
        detShape = sh;
      } else if (sh.length == 4) {
        proto = data;
        protoShape = sh;
      }
      await v.dispose();
    }
    await input.dispose();
    if (det == null || proto == null) {
      throw StateError('Unexpected model outputs (need one rank-3 and one rank-4 tensor)');
    }
    return RawOutputs(det, detShape!, proto, protoShape!);
  }

  /// 단일 rank-3 출력만 내는 검출 모델용(수고봉 경계). 형태 [1, 4+nc, anchors].
  Future<({Float32List data, List<int> shape})> inferDetect(
      Float32List chw, int size) async {
    final tb = testBackend;
    if (tb != null) {
      final o = (await tb(_loadedAsset!, chw, size))
          .firstWhere((o) => o.shape.length == 3);
      return (data: o.data, shape: o.shape);
    }
    final s = _session;
    if (s == null) {
      throw StateError('ONNX session not loaded');
    }
    final input = await OrtValue.fromList(chw, [1, 3, size, size]);
    final outputs = await s.run({s.inputNames.first: input});
    Float32List? out;
    List<int>? shape;
    for (final name in s.outputNames) {
      final v = outputs[name];
      if (v == null) continue;
      if (v.shape.length == 3) {
        final flat = await v.asFlattenedList();
        out = Float32List.fromList(flat.cast<double>());
        shape = v.shape;
      }
      await v.dispose();
    }
    await input.dispose();
    if (out == null) throw StateError('Unexpected pole-model output');
    return (data: out, shape: shape!);
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _loadedAsset = null;
  }
}
