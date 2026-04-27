import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;
import 'package:kala_ai_create_images_videos_with_ai/core/services/model_cache_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class OnDeviceInpaintService {
  static Interpreter? _interpreter;
  static IsolateInterpreter? _isolateInterpreter;
  static Future<void>? _initFuture;
  static int _inputCount = 1;

  static Future<void> _ensureInitialized() async {
    if (_interpreter != null && _isolateInterpreter != null) return;
    if (_initFuture != null) return _initFuture!;
    _initFuture = _init();
    try {
      await _initFuture;
    } finally {
      // Allow retry if init failed.
      _initFuture = null;
    }
  }

  static Future<void> warmup() async {
    final sw = Stopwatch()..start();
    await _ensureInitialized();
    sw.stop();
    debugPrint('🧠 LaMa session warmup ready in ${sw.elapsedMilliseconds}ms');
  }

  static Future<void> _init() async {
    final opts = InterpreterOptions()..threads = 2;
    final modelPath = await ModelCacheService.ensureInpaintModelDownloaded();
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw Exception('LaMa model is not available at $modelPath');
    }
    _interpreter = Interpreter.fromFile(modelFile, options: opts);
    _interpreter!.allocateTensors();
    _isolateInterpreter =
        await IsolateInterpreter.create(address: _interpreter!.address);

    final in0 = _interpreter!.getInputTensor(0);
    try {
      _interpreter!.getInputTensor(1);
      _inputCount = 2;
    } catch (_) {
      _inputCount = 1;
    }
    final out0 = _interpreter!.getOutputTensor(0);
    String in1Info = 'none';
    if (_inputCount > 1) {
      final in1 = _interpreter!.getInputTensor(1);
      in1Info = 'in1(shape=${in1.shape}, type=${in1.type.name})';
    }
    debugPrint(
      '🧠 LaMa model loaded: $modelPath '
      'inputCount=$_inputCount '
      'in0(shape=${in0.shape}, type=${in0.type.name}) '
      '$in1Info '
      'out0(shape=${out0.shape}, type=${out0.type.name})',
    );
  }

  static Future<Uint8List> inpaint({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
  }) async {
    await _ensureInitialized();
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw Exception('LaMa interpreter failed to initialize');
    }

    final input0 = interpreter.getInputTensor(0);
    final input1 = _inputCount > 1 ? interpreter.getInputTensor(1) : null;
    final output = interpreter.getOutputTensor(0);

    try {
      final prepared = await compute(
        _prepareLamaInputsIsolate,
        <String, dynamic>{
          'image': imageBytes,
          'mask': maskBytes,
          'inputCount': _inputCount,
          'input0Shape': input0.shape,
          'input0Type': input0.type.name,
          'input1Shape': input1?.shape,
          'input1Type': input1?.type.name,
          'outputShape': output.shape,
          'outputType': output.type.name,
        },
      );

      final width = prepared['targetW'] as int;
      final height = prepared['targetH'] as int;
      final hasMaskedRegion = prepared['hasMaskedRegion'] as bool;
      if (!hasMaskedRegion) {
        return prepared['passthroughPng'] as Uint8List;
      }

      final outputShape = (prepared['outputShapeResolved'] as List).cast<int>();
      final outputType = prepared['outputTypeResolved'] as String;
      final outputLen = prepared['outputLen'] as int;

      // tflite_flutter matches output buffer rank to the model tensor (e.g. [1,512,512,3]).
      // A flat Float32List is treated as shape [N] and fails copyTo; use nested tensors
      // like inputs, then flatten for RGB extraction.
      late final Object outputForRun;
      Map<String, Object>? floatLayout;
      if (outputType == 'float32') {
        final layout = _lamaOutputLayout(outputShape);
        final h = layout['h']! as int;
        final w = layout['w']! as int;
        final c = layout['c']! as int;
        final isNhwc = layout['isNhwc']! as bool;
        if (h * w * c != outputLen) {
          throw StateError(
            'LaMa output size mismatch: len=$outputLen, h=$h w=$w c=$c',
          );
        }
        floatLayout = layout;
        outputForRun = _toNestedTensor(
          Float32List(outputLen),
          h: h,
          w: w,
          c: c,
          isNhwc: isNhwc,
        );
      } else {
        outputForRun = outputType == 'int8'
            ? Int8List(outputLen)
            : Uint8List(outputLen);
      }

      // STRICT: inference must run on isolate-backed interpreter only.
      final iso = _isolateInterpreter;
      if (iso == null) {
        throw Exception('LaMa isolate interpreter is not initialized');
      }
      if (_inputCount > 1) {
        await iso.runForMultipleInputs(
          <Object>[prepared['input0'] as Object, prepared['input1'] as Object],
          <int, Object>{0: outputForRun},
        );
      } else {
        await iso.run(
          prepared['input0'] as Object,
          outputForRun,
        );
      }

      final Object bufferForExtract;
      if (outputType == 'float32' && floatLayout != null) {
        bufferForExtract = _flattenNestedFloatOutput(
          outputForRun,
          h: floatLayout['h']! as int,
          w: floatLayout['w']! as int,
          c: floatLayout['c']! as int,
          isNhwc: floatLayout['isNhwc']! as bool,
        );
      } else {
        bufferForExtract = outputForRun;
      }

      final inferredRgb = _extractModelOutputRgb(
        bufferForExtract,
        outputShape: outputShape,
        outputType: outputType,
      );

      return await compute(
        _composeBackToOriginalPngIsolate,
        <String, dynamic>{
          'srcRgba': prepared['srcRgba'],
          'srcW': prepared['srcW'],
          'srcH': prepared['srcH'],
          'targetW': width,
          'targetH': height,
          'targetMask': prepared['targetMask'],
          'inferredRgb': inferredRgb,
        },
      );
    } catch (e, st) {
      debugPrint(
        '❌ LaMa inpaint failed: $e '
        '(inputCount=$_inputCount in0=${input0.shape}/${input0.type.name} '
        'in1=${input1?.shape}/${input1?.type.name} '
        'out0=${output.shape}/${output.type.name})',
      );
      debugPrintStack(stackTrace: st, label: 'LaMa inpaint stack');
      rethrow;
    }
  }
}

Uint8List _extractModelOutputRgb(
  Object outputBuffer, {
  required List<int> outputShape,
  required String outputType,
}) {
  final flat = <double>[];
  if (outputBuffer is Float32List) {
    for (final v in outputBuffer) {
      flat.add(v.toDouble());
    }
  } else if (outputBuffer is Uint8List) {
    for (final v in outputBuffer) {
      flat.add(v / 255.0);
    }
  } else if (outputBuffer is Int8List) {
    for (final v in outputBuffer) {
      flat.add((v + 128).clamp(0, 255) / 255.0);
    }
  } else {
    throw Exception('Unsupported LaMa output buffer: ${outputBuffer.runtimeType}');
  }

  if (flat.isEmpty) {
    throw Exception('LaMa output buffer is empty');
  }

  int h;
  int w;
  int c;
  bool nhwc = true;
  if (outputShape.length == 4) {
    final d1 = outputShape[1];
    final d2 = outputShape[2];
    final d3 = outputShape[3];
    if (d3 == 3 || d3 == 1) {
      h = d1;
      w = d2;
      c = d3;
      nhwc = true;
    } else {
      h = d2;
      w = d3;
      c = d1;
      nhwc = false;
    }
  } else {
    throw Exception('Unsupported LaMa output shape: $outputShape');
  }
  if (c < 3) {
    throw Exception('LaMa output channels must be >=3, got $c');
  }

  var minV = double.infinity;
  var maxV = -double.infinity;
  for (final v in flat) {
    if (!v.isFinite) {
      throw Exception('LaMa output contains non-finite values');
    }
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }

  int toByte(double v) {
    if (outputType == 'uint8') {
      return (v * 255.0).round().clamp(0, 255);
    }
    if (maxV <= 1.5 && minV >= -1.5) {
      if (minV < 0) {
        return ((v + 1.0) * 127.5).round().clamp(0, 255);
      }
      return (v * 255.0).round().clamp(0, 255);
    }
    return v.round().clamp(0, 255);
  }

  final rgb = Uint8List(h * w * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final outIdx = (y * w + x) * 3;
      if (nhwc) {
        final base = (y * w + x) * c;
        rgb[outIdx] = toByte(flat[base]);
        rgb[outIdx + 1] = toByte(flat[base + 1]);
        rgb[outIdx + 2] = toByte(flat[base + 2]);
      } else {
        final idx = y * w + x;
        rgb[outIdx] = toByte(flat[idx]);
        rgb[outIdx + 1] = toByte(flat[h * w + idx]);
        rgb[outIdx + 2] = toByte(flat[2 * h * w + idx]);
      }
    }
  }
  return rgb;
}

/// Resolved H/W/C and NHWC vs NCHW for LaMa output tensor (4D only).
Map<String, Object> _lamaOutputLayout(List<int> s) {
  if (s.length != 4) {
    throw Exception('LaMa output shape must be 4D, got $s');
  }
  if (s[3] >= 1 && s[3] <= 4) {
    return <String, Object>{
      'h': s[1],
      'w': s[2],
      'c': s[3],
      'isNhwc': true,
    };
  }
  if (s[1] >= 1 && s[1] <= 4) {
    return <String, Object>{
      'h': s[2],
      'w': s[3],
      'c': s[1],
      'isNhwc': false,
    };
  }
  throw Exception('Unrecognized LaMa output layout: $s');
}

/// Read nested [1][H][W][C] or [1][C][H][W] float output back to a flat buffer.
Float32List _flattenNestedFloatOutput(
  Object nested, {
  required int h,
  required int w,
  required int c,
  required bool isNhwc,
}) {
  final out = Float32List(h * w * c);
  final batch = nested as List;
  final root = batch[0] as List;
  if (isNhwc) {
    for (var y = 0; y < h; y++) {
      final row = root[y] as List;
      for (var x = 0; x < w; x++) {
        final px = row[x] as List;
        final idx = y * w + x;
        for (var ch = 0; ch < c; ch++) {
          out[idx * c + ch] = (px[ch] as num).toDouble();
        }
      }
    }
  } else {
    for (var ch = 0; ch < c; ch++) {
      final chPlane = root[ch] as List;
      for (var y = 0; y < h; y++) {
        final row = chPlane[y] as List;
        for (var x = 0; x < w; x++) {
          out[ch * h * w + y * w + x] = (row[x] as num).toDouble();
        }
      }
    }
  }
  return out;
}

Map<String, dynamic> _prepareLamaInputsIsolate(Map<String, dynamic> payload) {
  final imageBytes = payload['image']!;
  final maskBytes = payload['mask']!;
  final inputCount = payload['inputCount'] as int;
  final input0Shape = (payload['input0Shape'] as List).cast<int>();
  final input0Type = payload['input0Type'] as String;
  final input1Shape = (payload['input1Shape'] as List?)?.cast<int>();
  final input1Type = payload['input1Type'] as String?;
  final outputShape = (payload['outputShape'] as List).cast<int>();
  final outputType = payload['outputType'] as String;

  final src = imglib.decodeImage(imageBytes);
  final maskRaw = imglib.decodeImage(maskBytes);
  if (src == null || maskRaw == null) {
    throw Exception('Failed to decode source image or mask');
  }

  final srcW = src.width;
  final srcH = src.height;
  final info0 = _shapeInfo(input0Shape, srcW, srcH);
  final targetW = info0['w'] as int;
  final targetH = info0['h'] as int;

  final resized = imglib.copyResize(
    src,
    width: targetW,
    height: targetH,
    interpolation: imglib.Interpolation.cubic,
  );
  final mask = (maskRaw.width == targetW && maskRaw.height == targetH)
      ? maskRaw
      : imglib.copyResize(
          maskRaw,
          width: targetW,
          height: targetH,
          interpolation: imglib.Interpolation.nearest,
        );

  final rgb = Uint8List(targetW * targetH * 3);
  final mask01 = Float32List(targetW * targetH); // 1 = remove/inpaint
  var hasMaskedRegion = false;
  for (var y = 0; y < targetH; y++) {
    for (var x = 0; x < targetW; x++) {
      final idx = y * targetW + x;
      final p = resized.getPixel(x, y);
      rgb[idx * 3] = p.r.toInt();
      rgb[idx * 3 + 1] = p.g.toInt();
      rgb[idx * 3 + 2] = p.b.toInt();
      final m = mask.getPixel(x, y);
      final alpha = m.a.toInt();
      final lum = 0.299 * m.r + 0.587 * m.g + 0.114 * m.b;
      final remove = alpha > 12 || lum > 64;
      if (remove) hasMaskedRegion = true;
      mask01[idx] = remove ? 1.0 : 0.0;
    }
  }

  final input0 = _buildInputPayload(
    rgb: rgb,
    mask01: mask01,
    shape: input0Shape,
    type: input0Type,
    srcW: targetW,
    srcH: targetH,
    isMaskTensor: inputCount > 1 && _isLikelyMaskShape(input0Shape),
  );

  Map<String, Object>? input1;
  if (inputCount > 1 && input1Shape != null && input1Type != null) {
    input1 = _buildInputPayload(
      rgb: rgb,
      mask01: mask01,
      shape: input1Shape,
      type: input1Type,
      srcW: targetW,
      srcH: targetH,
      isMaskTensor: _isLikelyMaskShape(input1Shape),
    );
  }

  final outputShapeResolved = _resolveTensorShape(outputShape, targetW, targetH);
  final outLen = outputShapeResolved.fold<int>(1, (p, e) => p * (e <= 0 ? 1 : e));

  return <String, dynamic>{
    'srcW': srcW,
    'srcH': srcH,
    'srcRgba': src.getBytes(order: imglib.ChannelOrder.rgba),
    'targetW': targetW,
    'targetH': targetH,
    'targetMask': Uint8List.fromList(mask01.map((e) => e > 0.5 ? 1 : 0).toList()),
    'hasMaskedRegion': hasMaskedRegion,
    'input0': input0['nested'],
    'input0Flat': input0['flat'],
    'input1': input1?['nested'],
    'input1Flat': input1?['flat'],
    'outputShapeResolved': outputShapeResolved,
    'outputTypeResolved': outputType,
    'outputLen': outLen,
    'passthroughPng': Uint8List.fromList(imglib.encodePng(src)),
  };
}

Map<String, int> _shapeInfo(List<int> shape, int fallbackW, int fallbackH) {
  if (shape.length != 4) {
    throw Exception('Expected 4D tensor shape, got $shape');
  }
  int safe(int v, int fb) => v <= 0 ? fb : v;
  if (shape[3] >= 1 && shape[3] <= 4) {
    return <String, int>{
      'h': safe(shape[1], fallbackH),
      'w': safe(shape[2], fallbackW),
      'c': safe(shape[3], 3),
    };
  }
  if (shape[1] >= 1 && shape[1] <= 4) {
    return <String, int>{
      'h': safe(shape[2], fallbackH),
      'w': safe(shape[3], fallbackW),
      'c': safe(shape[1], 3),
    };
  }
  return <String, int>{'h': fallbackH, 'w': fallbackW, 'c': 3};
}

bool _isLikelyMaskShape(List<int> shape) {
  if (shape.length != 4) return false;
  final nhwc = shape[3];
  final nchw = shape[1];
  return nhwc == 1 || nchw == 1;
}

List<int> _resolveTensorShape(List<int> shape, int fallbackW, int fallbackH) {
  if (shape.length != 4) {
    throw Exception('Expected 4D tensor shape, got $shape');
  }
  int safe(int v, int fb) => v <= 0 ? fb : v;
  if (shape[3] >= 1 && shape[3] <= 4) {
    return <int>[
      safe(shape[0], 1),
      safe(shape[1], fallbackH),
      safe(shape[2], fallbackW),
      safe(shape[3], 3),
    ];
  }
  if (shape[1] >= 1 && shape[1] <= 4) {
    return <int>[
      safe(shape[0], 1),
      safe(shape[1], 3),
      safe(shape[2], fallbackH),
      safe(shape[3], fallbackW),
    ];
  }
  return <int>[1, fallbackH, fallbackW, 3];
}

Map<String, Object> _buildInputPayload({
  required Uint8List rgb,
  required Float32List mask01,
  required List<int> shape,
  required String type,
  required int srcW,
  required int srcH,
  required bool isMaskTensor,
}) {
  final info = _shapeInfo(shape, srcW, srcH);
  final h = info['h']!;
  final w = info['w']!;
  final c = info['c']!;
  final isNhwc = shape[3] >= 1 && shape[3] <= 4;

  final values = Float32List(h * w * c);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final r = rgb[idx * 3] / 255.0;
      final g = rgb[idx * 3 + 1] / 255.0;
      final b = rgb[idx * 3 + 2] / 255.0;
      final m = mask01[idx];
      final keep = 1.0 - m;
      final maskedR = r * keep;
      final maskedG = g * keep;
      final maskedB = b * keep;
      for (var ch = 0; ch < c; ch++) {
        final v = isMaskTensor
            ? m
            : (c >= 4
                ? (ch == 3
                    ? m
                    : (ch == 0 ? maskedR : (ch == 1 ? maskedG : maskedB)))
                : (ch == 0 ? maskedR : (ch == 1 ? maskedG : maskedB)));
        if (isNhwc) {
          values[(idx * c) + ch] = v;
        } else {
          values[ch * h * w + idx] = v;
        }
      }
    }
  }

  if (type == 'uint8') {
    final flat = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      flat[i] = (values[i] * 255.0).round().clamp(0, 255);
    }
    return <String, Object>{
      'flat': flat,
      'nested': _toNestedTensor(flat, h: h, w: w, c: c, isNhwc: isNhwc),
    };
  }
  if (type == 'int8') {
    final flat = Int8List(values.length);
    for (var i = 0; i < values.length; i++) {
      flat[i] = ((values[i] * 255.0).round() - 128).clamp(-128, 127);
    }
    return <String, Object>{
      'flat': flat,
      'nested': _toNestedTensor(flat, h: h, w: w, c: c, isNhwc: isNhwc),
    };
  }
  return <String, Object>{
    'flat': values,
    'nested': _toNestedTensor(values, h: h, w: w, c: c, isNhwc: isNhwc),
  };
}

Object _toNestedTensor(
  Object flat, {
  required int h,
  required int w,
  required int c,
  required bool isNhwc,
}) {
  num at(int index) {
    if (flat is Float32List) return flat[index];
    if (flat is Uint8List) return flat[index];
    if (flat is Int8List) return flat[index];
    throw Exception('Unsupported flat tensor type: ${flat.runtimeType}');
  }

  if (isNhwc) {
    return <List<List<List<num>>>>[
      List<List<List<num>>>.generate(
        h,
        (y) => List<List<num>>.generate(
          w,
          (x) {
            final base = (y * w + x) * c;
            return List<num>.generate(c, (ch) => at(base + ch));
          },
          growable: false,
        ),
        growable: false,
      ),
    ];
  }

  return <List<List<List<num>>>>[
    List<List<List<num>>>.generate(
      c,
      (ch) => List<List<num>>.generate(
        h,
        (y) => List<num>.generate(
          w,
          (x) => at(ch * h * w + y * w + x),
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    ),
  ];
}

Uint8List _composeBackToOriginalPngIsolate(Map<String, dynamic> payload) {
  final srcRgba = payload['srcRgba'] as Uint8List;
  final srcW = payload['srcW'] as int;
  final srcH = payload['srcH'] as int;
  final targetW = payload['targetW'] as int;
  final targetH = payload['targetH'] as int;
  final targetMask = payload['targetMask'] as Uint8List; // 1=inpaint
  final inferredRgb = payload['inferredRgb'] as Uint8List;

  final srcImg = imglib.Image.fromBytes(
    width: srcW,
    height: srcH,
    bytes: srcRgba.buffer,
    numChannels: 4,
    order: imglib.ChannelOrder.rgba,
  );
  final srcAtTarget = (srcW == targetW && srcH == targetH)
      ? srcImg
      : imglib.copyResize(
          srcImg,
          width: targetW,
          height: targetH,
          interpolation: imglib.Interpolation.cubic,
        );

  final composed = imglib.Image(width: targetW, height: targetH);
  for (var y = 0; y < targetH; y++) {
    for (var x = 0; x < targetW; x++) {
      final idx = y * targetW + x;
      if (targetMask[idx] == 1) {
        composed.setPixelRgba(
          x,
          y,
          inferredRgb[idx * 3],
          inferredRgb[idx * 3 + 1],
          inferredRgb[idx * 3 + 2],
          255,
        );
      } else {
        final p = srcAtTarget.getPixel(x, y);
        composed.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }
  }

  final out = (targetW == srcW && targetH == srcH)
      ? composed
      : imglib.copyResize(
          composed,
          width: srcW,
          height: srcH,
          interpolation: imglib.Interpolation.cubic,
        );
  return Uint8List.fromList(
    imglib.encodePng(
      out,
    ),
  );
}
