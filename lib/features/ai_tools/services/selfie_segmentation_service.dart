import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class DetectedPersonRegion {
  final int id;
  final Rect bounds; // image-space bounds
  final Uint8List mask; // image-space binary mask: 255=person, 0=background

  DetectedPersonRegion({
    required this.id,
    required this.bounds,
    required this.mask,
  });
}

class SelfieSegmentationService {
  static const String _modelAssetPath = 'assets/models/selfie_segmentation.tflite';
  Interpreter? _interpreter;
  bool _tfliteUsable = true;
  SelfieSegmenter? _mlkitSegmenter;

  Future<void> init() async {
    if (_interpreter != null || !_tfliteUsable) return;
    final opts = InterpreterOptions()..threads = 2;
    try {
      // Prefer fromBuffer for release stability across Android devices.
      final raw = await rootBundle.load(_modelAssetPath);
      _interpreter =
          Interpreter.fromBuffer(raw.buffer.asUint8List(), options: opts);
      _interpreter!.allocateTensors();
      final input = _interpreter!.getInputTensor(0);
      final output = _interpreter!.getOutputTensor(0);
      debugPrint(
        '🧍 SelfieSeg loaded. inputShape=${input.shape} inputType=${input.type.name} '
        'outputShape=${output.shape} outputType=${output.type.name}',
      );
    } catch (e, st) {
      _tfliteUsable = false;
      _interpreter?.close();
      _interpreter = null;
      debugPrint('⚠️ TFLite selfie model unusable; falling back to ML Kit: $e');
      debugPrint('$st');
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _mlkitSegmenter?.close();
    _mlkitSegmenter = null;
  }

  Future<List<DetectedPersonRegion>> detectPeople(Uint8List imageBytes) async {
    final decoded = imglib.decodeImage(imageBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image for people detection');
    }
    try {
      await init();
      if (!_tfliteUsable || _interpreter == null) {
        return _detectPeopleWithMlKit(imageBytes, decoded.width, decoded.height);
      }
      final interpreter = _interpreter;
      if (interpreter == null) throw Exception('Interpreter not initialized');

      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final inputShape = inputTensor.shape; // Expected NHWC
      if (inputShape.length != 4) {
        throw Exception('Unexpected selfie model input shape: $inputShape');
      }

      final inH = inputShape[1];
      final inW = inputShape[2];
      final inC = inputShape[3];
      if (inC != 3) {
        throw Exception('Unexpected selfie model input channels: $inC');
      }

      final resized = imglib.copyResize(
        decoded,
        width: inW,
        height: inH,
        interpolation: imglib.Interpolation.linear,
      );

      final inputCandidates = await compute(
        _buildModelInputCandidates,
        <String, dynamic>{
          'rgba': resized.getBytes(order: imglib.ChannelOrder.rgba),
          'width': inW,
          'height': inH,
          'inputType': inputTensor.type.name,
        },
      );

      // Use setTo/invoke/data with fallback input representations to avoid
      // interpreter "Bad state: failed precondition" from strict shape checks.
      Object? acceptedInput;
      Object? lastError;
      for (final candidate in inputCandidates) {
        try {
          inputTensor.setTo(candidate);
          interpreter.invoke();
          acceptedInput = candidate;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (acceptedInput == null) {
        throw Exception(
          'Selfie segmentation invoke failed for all input representations. '
          'inputType=${inputTensor.type.name} inputShape=$inputShape '
          'error=$lastError',
        );
      }

      final outputShape = outputTensor.shape;
      final outElements =
          outputShape.fold<int>(1, (prev, e) => prev * (e <= 0 ? 1 : e));
      final outputType = outputTensor.type.name;
      final out = _tensorDataToFloat32(outputTensor.data, outElements, outputType);

      final regionsData = await compute(
        _extractPeopleRegions,
        <String, dynamic>{
          'output': out,
          'outputShape': outputShape,
          'srcW': decoded.width,
          'srcH': decoded.height,
        },
      );

      final List<DetectedPersonRegion> regions = [];
      final raw = regionsData['regions'] as List<dynamic>;
      for (final item in raw) {
        final m = item as Map<String, dynamic>;
        regions.add(
          DetectedPersonRegion(
            id: m['id'] as int,
            bounds: Rect.fromLTRB(
              (m['left'] as num).toDouble(),
              (m['top'] as num).toDouble(),
              (m['right'] as num).toDouble(),
              (m['bottom'] as num).toDouble(),
            ),
            mask: m['mask'] as Uint8List,
          ),
        );
      }
      return regions;
    } catch (e, st) {
      debugPrint('❌ SelfieSeg detectPeople failed: $e');
      debugPrint('$st');
      return _detectPeopleWithMlKit(imageBytes, decoded.width, decoded.height);
    }
  }

  Future<List<DetectedPersonRegion>> _detectPeopleWithMlKit(
    Uint8List imageBytes,
    int srcW,
    int srcH,
  ) async {
    _mlkitSegmenter ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/selfie_seg_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(imageBytes, flush: true);
    try {
      final input = InputImage.fromFilePath(file.path);
      final mask = await _mlkitSegmenter!.processImage(input);
      if (mask == null) return <DetectedPersonRegion>[];

      final regionsData = await compute(
        _extractPeopleRegions,
        <String, dynamic>{
          'output': mask.confidences,
          'outputShape': <int>[1, mask.height, mask.width, 1],
          'srcW': srcW,
          'srcH': srcH,
        },
      );

      final List<DetectedPersonRegion> regions = [];
      final raw = regionsData['regions'] as List<dynamic>;
      for (final item in raw) {
        final m = item as Map<String, dynamic>;
        regions.add(
          DetectedPersonRegion(
            id: m['id'] as int,
            bounds: Rect.fromLTRB(
              (m['left'] as num).toDouble(),
              (m['top'] as num).toDouble(),
              (m['right'] as num).toDouble(),
              (m['bottom'] as num).toDouble(),
            ),
            mask: m['mask'] as Uint8List,
          ),
        );
      }
      debugPrint('🧍 ML Kit fallback detected ${regions.length} people regions');
      return regions;
    } catch (e, st) {
      debugPrint('❌ ML Kit selfie fallback failed: $e');
      debugPrint('$st');
      throw Exception('Selfie segmentation failed: $e');
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}

List<Object> _buildModelInputCandidates(Map<String, dynamic> args) {
  final rgba = args['rgba'] as Uint8List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final inputType = args['inputType'] as String;
  final pxCount = width * height;
  final out = <Object>[];

  if (inputType == 'float32') {
    final nested = List.generate(
      1,
      (_) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) {
            final i = y * width + x;
            return <double>[
              rgba[i * 4] / 255.0,
              rgba[i * 4 + 1] / 255.0,
              rgba[i * 4 + 2] / 255.0,
            ];
          },
        ),
      ),
    );
    out.add(nested);

    // Flat fallback for some runtime builds.
    final flat = Float32List(pxCount * 3);
    var j = 0;
    for (var i = 0; i < pxCount; i++) {
      flat[j++] = rgba[i * 4] / 255.0;
      flat[j++] = rgba[i * 4 + 1] / 255.0;
      flat[j++] = rgba[i * 4 + 2] / 255.0;
    }
    out.add(flat);
    return out;
  }

  if (inputType == 'int8') {
    final nested = List.generate(
      1,
      (_) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) {
            final i = y * width + x;
            return <int>[
              (rgba[i * 4] - 128).clamp(-128, 127),
              (rgba[i * 4 + 1] - 128).clamp(-128, 127),
              (rgba[i * 4 + 2] - 128).clamp(-128, 127),
            ];
          },
        ),
      ),
    );
    out.add(nested);

    final flat = Int8List(pxCount * 3);
    var j = 0;
    for (var i = 0; i < pxCount; i++) {
      flat[j++] = (rgba[i * 4] - 128).clamp(-128, 127);
      flat[j++] = (rgba[i * 4 + 1] - 128).clamp(-128, 127);
      flat[j++] = (rgba[i * 4 + 2] - 128).clamp(-128, 127);
    }
    out.add(flat);
    return out;
  }

  // uint8 fallback
  final nested = List.generate(
    1,
    (_) => List.generate(
      height,
      (y) => List.generate(
        width,
        (x) {
          final i = y * width + x;
          return <int>[
            rgba[i * 4],
            rgba[i * 4 + 1],
            rgba[i * 4 + 2],
          ];
        },
      ),
    ),
  );
  out.add(nested);

  final flat = Uint8List(pxCount * 3);
  var j = 0;
  for (var i = 0; i < pxCount; i++) {
    flat[j++] = rgba[i * 4];
    flat[j++] = rgba[i * 4 + 1];
    flat[j++] = rgba[i * 4 + 2];
  }
  out.add(flat);
  return out;
}

Float32List _tensorDataToFloat32(
  Uint8List data,
  int expectedLen,
  String outputType,
) {
  final bool integerOutput = outputType == 'uint8' || outputType == 'int8';
  final out = Float32List(expectedLen);
  if (outputType == 'float32') {
    final view = Float32List.view(data.buffer, data.offsetInBytes);
    final n = view.length < expectedLen ? view.length : expectedLen;
    for (var i = 0; i < n; i++) {
      out[i] = view[i];
    }
    return out;
  }

  if (integerOutput) {
    if (outputType == 'int8') {
      final view = Int8List.view(data.buffer, data.offsetInBytes);
      final n = view.length < expectedLen ? view.length : expectedLen;
      for (var i = 0; i < n; i++) {
        out[i] = ((view[i] + 128).clamp(0, 255)) / 255.0;
      }
      return out;
    }
    final n = data.length < expectedLen ? data.length : expectedLen;
    for (var i = 0; i < n; i++) {
      out[i] = data[i] / 255.0;
    }
    return out;
  }

  return out;
}

Map<String, dynamic> _extractPeopleRegions(Map<String, dynamic> args) {
  final out = _coerceToFloat32(args['output']);
  final outputShape = (args['outputShape'] as List).cast<int>();
  final srcW = args['srcW'] as int;
  final srcH = args['srcH'] as int;

  int outH = 0;
  int outW = 0;
  int outC = 1;
  if (outputShape.length == 4) {
    // [1, H, W, C]
    outH = outputShape[1];
    outW = outputShape[2];
    outC = outputShape[3] <= 0 ? 1 : outputShape[3];
  } else if (outputShape.length == 3) {
    // [1, H, W]
    outH = outputShape[1];
    outW = outputShape[2];
  } else {
    throw Exception('Unsupported output shape: $outputShape');
  }

  final upsampled = Uint8List(srcW * srcH);
  for (var y = 0; y < srcH; y++) {
    final sy = (y * outH / srcH).floor().clamp(0, outH - 1);
    for (var x = 0; x < srcW; x++) {
      final sx = (x * outW / srcW).floor().clamp(0, outW - 1);
      final idx = (sy * outW + sx) * outC; // first channel
      final conf = out[idx];
      upsampled[y * srcW + x] = conf >= 0.5 ? 1 : 0;
    }
  }
  final dilateRadius = _maskDilateRadiusPx(srcW, srcH);
  final expanded = _dilateBinaryMask(
    source: upsampled,
    width: srcW,
    height: srcH,
    radius: dilateRadius,
  );

  final labels = Int32List(srcW * srcH);
  labels.fillRange(0, labels.length, -1);
  var nextLabel = 0;
  final Map<int, List<int>> componentPixels = <int, List<int>>{};

  for (var i = 0; i < expanded.length; i++) {
    if (expanded[i] == 0 || labels[i] >= 0) continue;
    final label = nextLabel++;
    final pixels = <int>[];
    final queue = <int>[i];
    labels[i] = label;
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      pixels.add(cur);
      final x = cur % srcW;
      final y = cur ~/ srcW;
      final neighbors = <int>[
        if (x > 0) cur - 1,
        if (x < srcW - 1) cur + 1,
        if (y > 0) cur - srcW,
        if (y < srcH - 1) cur + srcW,
      ];
      for (final ni in neighbors) {
        if (expanded[ni] == 0 || labels[ni] >= 0) continue;
        labels[ni] = label;
        queue.add(ni);
      }
    }
    componentPixels[label] = pixels;
  }

  final minSize = (srcW * srcH * 0.005).round(); // >=0.5% image
  final List<Map<String, dynamic>> regions = [];
  componentPixels.forEach((label, pixels) {
    if (pixels.length < minSize) return;
    var minX = srcW;
    var minY = srcH;
    var maxX = 0;
    var maxY = 0;
    for (final idx in pixels) {
      final x = idx % srcW;
      final y = idx ~/ srcW;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final regionMask = Uint8List(srcW * srcH);
    for (final idx in pixels) {
      regionMask[idx] = 255;
    }
    regions.add(<String, dynamic>{
      'id': label,
      'left': minX.toDouble(),
      'top': minY.toDouble(),
      'right': maxX.toDouble(),
      'bottom': maxY.toDouble(),
      'mask': regionMask,
    });
  });

  return <String, dynamic>{'regions': regions};
}

Float32List _coerceToFloat32(Object? raw) {
  if (raw is Float32List) return raw;
  if (raw is List<double>) return Float32List.fromList(raw);
  if (raw is List<num>) {
    return Float32List.fromList(raw.map((e) => e.toDouble()).toList());
  }
  if (raw is Uint8List) {
    return Float32List.fromList(
      raw.map((e) => e / 255.0).toList(),
    );
  }
  throw Exception('Unsupported segmentation output type: ${raw.runtimeType}');
}

int _maskDilateRadiusPx(int width, int height) {
  final minDim = width < height ? width : height;
  // Expand around subject boundaries so erase covers full silhouette.
  final adaptive = (minDim * 0.01).round(); // ~1% of shortest side.
  if (adaptive < 4) return 4;
  if (adaptive > 18) return 18;
  return adaptive;
}

Uint8List _dilateBinaryMask({
  required Uint8List source,
  required int width,
  required int height,
  required int radius,
}) {
  if (radius <= 0) return source;
  final out = Uint8List(width * height);
  final r2 = radius * radius;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var on = false;
      final y0 = (y - radius).clamp(0, height - 1);
      final y1 = (y + radius).clamp(0, height - 1);
      final x0 = (x - radius).clamp(0, width - 1);
      final x1 = (x + radius).clamp(0, width - 1);
      for (var ny = y0; ny <= y1 && !on; ny++) {
        final dy = ny - y;
        for (var nx = x0; nx <= x1; nx++) {
          final dx = nx - x;
          if (dx * dx + dy * dy > r2) continue;
          if (source[ny * width + nx] != 0) {
            on = true;
            break;
          }
        }
      }
      out[y * width + x] = on ? 1 : 0;
    }
  }
  return out;
}
