import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef ModelTensor = ({Float32List data, List<int> shape});

/// Allows real-photo replays to use the bundled models on a desktop.
typedef InferenceBackend =
    Future<List<ModelTensor>> Function(String asset, Float32List chw, int size);

class RawOutputs {
  final Float32List det;
  final List<int> detShape;
  final Float32List proto;
  final List<int> protoShape;

  RawOutputs(this.det, this.detShape, this.proto, this.protoShape);
}

enum _Model {
  stem([1, 300, 38]),
  pole([1, 300, 6]);

  const _Model(this.detectionShape);

  final List<int> detectionShape;
  bool get hasPrototypes => this != pole;
}

const _inputSize = 640;
const _prototypeShape = [1, 32, 160, 160];

class ModelService {
  ModelService._(this._model);

  static final instance = ModelService._(_Model.stem);
  static final pole = ModelService._(_Model.pole);

  @visibleForTesting
  static InferenceBackend? testBackend;

  final _Model _model;
  String? _loadedAsset;
  int _address = 0;
  Future<void> _pending = Future.value();

  int get inputSize => _inputSize;
  String? get loadedAsset => _loadedAsset;
  bool get isLoaded =>
      _address != 0 || (testBackend != null && _loadedAsset != null);

  Future<T> _serial<T>(Future<T> Function() work) {
    final task = _pending.then((_) => work());
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> load(String assetPath) => _serial(() async {
    if (testBackend != null) {
      _loadedAsset = assetPath;
      return;
    }
    if (_address != 0 && _loadedAsset == assetPath) return;
    final base = await _stageModel(assetPath);
    final model = _model.index;
    final next = await compute(_open, (base, model));
    final previous = _address;
    _address = next;
    _loadedAsset = assetPath;
    if (previous != 0) await compute(_close, previous);
  });

  Future<bool> tryLoad(String assetPath) async {
    try {
      await load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<RawOutputs> infer(Float32List chw, int size) async {
    final outputs = await _infer(chw, size);
    final det = outputs.firstWhere((o) => o.shape.length == 3);
    final proto = outputs.firstWhere((o) => o.shape.length == 4);
    return RawOutputs(det.data, det.shape, proto.data, proto.shape);
  }

  Future<ModelTensor> inferDetect(Float32List chw, int size) async {
    final outputs = await _infer(chw, size);
    return outputs.firstWhere((o) => o.shape.length == 3);
  }

  Future<List<ModelTensor>> _infer(Float32List chw, int size) => _serial(
    () async {
      final asset = _loadedAsset;
      if (asset == null) throw StateError('Inference model not loaded');
      final backend = testBackend;
      if (backend != null) return backend(asset, chw, size);
      if (_address == 0) throw StateError('Native inference model not loaded');
      if (size != _inputSize || chw.length != 3 * size * size) {
        throw ArgumentError('Expected a 640 × 640 RGB input');
      }
      final input = TransferableTypedData.fromList([chw]);
      final address = _address;
      final model = _model;
      return compute(_run, (address, model, input));
    },
  );

  Future<void> dispose() => _serial(() async {
    final address = _address;
    _address = 0;
    _loadedAsset = null;
    if (address != 0) await compute(_close, address);
  });
}

Future<String> _stageModel(String asset) async {
  if (!asset.endsWith('.param')) {
    throw ArgumentError.value(asset, 'asset', 'Expected an ncnn .param file');
  }
  final weightsAsset = path.setExtension(asset, '.bin');
  final cache = await getTemporaryDirectory();
  final params = await rootBundle.load(asset);
  final weights = await rootBundle.load(weightsAsset);
  final paramsData = TransferableTypedData.fromList([
    params.buffer.asUint8List(params.offsetInBytes, params.lengthInBytes),
  ]);
  final weightsData = TransferableTypedData.fromList([
    weights.buffer.asUint8List(weights.offsetInBytes, weights.lengthInBytes),
  ]);
  final directory = path.join(cache.path, 'ncnn');
  final name = path.basenameWithoutExtension(asset);
  return compute(_writeModel, (directory, name, paramsData, weightsData));
}

String _writeModel(
  (String, String, TransferableTypedData, TransferableTypedData) request,
) {
  final (directory, name, params, weights) = request;
  final graphBytes = params.materialize().asUint8List();
  final weightBytes = weights.materialize().asUint8List();
  final graphHash = sha256.convert(graphBytes);
  final weightsHash = sha256.convert(weightBytes);
  final key = '$name-$graphHash-$weightsHash';
  final root = Directory(directory)..createSync(recursive: true);
  final base = path.join(root.path, key, name);
  final graphFile = File('$base.param');
  final weightsFile = File('$base.bin');
  if (graphFile.existsSync() &&
      weightsFile.existsSync() &&
      graphFile.lengthSync() == graphBytes.length &&
      weightsFile.lengthSync() == weightBytes.length) {
    return base;
  }

  final staging = root.createTempSync('staging-');
  try {
    File(path.join(staging.path, '$name.param')).writeAsBytesSync(graphBytes);
    File(path.join(staging.path, '$name.bin')).writeAsBytesSync(weightBytes);
    final target = Directory(path.dirname(base));
    // Only one service stages each model. A previous process may have left
    // an incomplete cache entry, so ensure both files are replaced together.
    if (target.existsSync()) target.deleteSync(recursive: true);
    staging.renameSync(target.path);
    return base;
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}

DynamicLibrary _library() {
  if (Platform.isAndroid) return DynamicLibrary.open('libbsi_ncnn.so');
  if (Platform.isIOS) return DynamicLibrary.process();
  throw UnsupportedError('Native inference is available on Android and iOS');
}

int _open((String, int) request) {
  final (base, model) = request;
  final open = _library()
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Int32),
        Pointer<Void> Function(Pointer<Utf8>, int)
      >('bsi_ncnn_open');
  final nativePath = base.toNativeUtf8(allocator: calloc);
  try {
    final handle = open(nativePath, model);
    if (handle == nullptr) throw StateError('Could not load inference model');
    return handle.address;
  } finally {
    calloc.free(nativePath);
  }
}

void _close(int address) {
  final close = _library()
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('bsi_ncnn_close');
  close(Pointer<Void>.fromAddress(address));
}

List<ModelTensor> _run((int, _Model, TransferableTypedData) request) {
  final (address, model, input) = request;
  final run = _library()
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Float>,
          Pointer<Float>,
          Pointer<Float>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Float>,
          Pointer<Float>,
          Pointer<Float>,
        )
      >('bsi_ncnn_run');
  final chw = input.materialize().asFloat32List();
  final headLength = model.detectionShape.reduce((a, b) => a * b);
  final protoLength = _prototypeShape.reduce((a, b) => a * b);
  final rgb = calloc<Float>(chw.length);
  final head = calloc<Float>(headLength);
  final masks = model.hasPrototypes ? calloc<Float>(protoLength) : nullptr;
  try {
    rgb.asTypedList(chw.length).setAll(0, chw);
    final backend = run(Pointer<Void>.fromAddress(address), rgb, head, masks);
    if (backend < 0) throw StateError('Inference failed');
    return [
      (
        data: Float32List.fromList(head.asTypedList(headLength)),
        shape: model.detectionShape,
      ),
      if (model.hasPrototypes)
        (
          data: Float32List.fromList(masks.asTypedList(protoLength)),
          shape: _prototypeShape,
        ),
    ];
  } finally {
    if (masks != nullptr) calloc.free(masks);
    calloc.free(head);
    calloc.free(rgb);
  }
}
