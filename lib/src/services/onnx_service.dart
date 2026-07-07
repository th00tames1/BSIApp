import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Raw model outputs: detection head (rank 3) + mask prototypes (rank 4).
class RawOutputs {
  final Float32List det;
  final List<int> detShape;
  final Float32List proto;
  final List<int> protoShape;
  RawOutputs(this.det, this.detShape, this.proto, this.protoShape);
}

/// Wraps a cached ONNX Runtime session (loaded once from a bundled asset).
class OnnxService {
  OnnxService._();
  static final OnnxService instance = OnnxService._();

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  String? _loadedAsset;
  int inputSize = 640;

  bool get isLoaded => _session != null;
  String? get loadedAsset => _loadedAsset;

  Future<void> load(String assetPath) async {
    if (_loadedAsset == assetPath && _session != null) return;
    await _session?.close();
    _session = await _ort.createSessionFromAsset(assetPath);
    _loadedAsset = assetPath;
    inputSize = assetPath.contains('1280') ? 1280 : 640;
  }

  Future<RawOutputs> infer(Float32List chw, int size) async {
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

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _loadedAsset = null;
  }
}
