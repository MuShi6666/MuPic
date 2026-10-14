import 'package:flutter/services.dart';

import '../core/models/edit_state.dart';

/// Result of opening an image: the native handle + source dimensions.
class OpenedImage {
  const OpenedImage({
    required this.imageId,
    required this.width,
    required this.height,
  });
  final int imageId;
  final int width;
  final int height;

  double get aspectRatio => height > 0 ? width / height : 1;
}

/// A decoded CPU preview frame: raw RGBA8 pixels + dimensions. The Dart side
/// turns this into a `ui.Image` for display via `decodeImageFromPixels`.
class PreviewFrame {
  const PreviewFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width;
  final int height;

  double get aspectRatio => height > 0 ? width / height : 1;
}

enum PipelineStage { decode, render, export }

class PipelineProgress {
  const PipelineProgress(this.stage, this.value, this.message);
  final PipelineStage stage;
  final double value; // 0..1
  final String? message;

  factory PipelineProgress.fromMap(Map<Object?, Object?> m) => PipelineProgress(
        switch (m['stage'] as String?) {
          'render' => PipelineStage.render,
          'export' => PipelineStage.export,
          _ => PipelineStage.decode,
        },
        (m['value'] as num?)?.toDouble() ?? 0,
        m['message'] as String?,
      );
}

/// Dart wrapper around the native editor channels.
///
/// MethodChannel "mupic/editor"  -> control
/// EventChannel  "mupic/events"  -> decode / export progress + errors
class EditorChannel {
  EditorChannel._();
  static final EditorChannel instance = EditorChannel._();

  static const MethodChannel _method = MethodChannel('mupic/editor');
  static const EventChannel _events = EventChannel('mupic/events');

  Stream<PipelineProgress> get progress =>
      _events.receiveBroadcastStream().map((e) => PipelineProgress.fromMap(
          (e as Map).cast<Object?, Object?>()));

  Future<OpenedImage> openImage(String path) async {
    final res = await _method.invokeMapMethod<String, Object?>('openImage', {
      'path': path,
    });
    if (res == null) throw PlatformException(code: 'open_failed');
    return OpenedImage(
      imageId: (res['imageId'] as num).toInt(),
      width: (res['width'] as num?)?.toInt() ?? 0,
      height: (res['height'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> setParams(
    int imageId,
    EditState state, {
    List<Offset> facePts = const <Offset>[],
    int faceCount = 0,
  }) {
    final Uint8List bytes =
        state.adjustments.toRenderBytes(facePts: facePts, faceCount: faceCount);
    return _method.invokeMethod<void>('setParams', {
      'imageId': imageId,
      'params': bytes,
    });
  }

  /// Runs ML Kit FaceMesh on the image at [path] and returns the fixed-order
  /// normalized key points (see MuPicEditor.detectFace) for the largest face.
  /// Returns an empty list when no face is found or detection fails.
  Future<List<Offset>> detectFace(String path) async {
    final res = await _method.invokeListMethod<Object>('detectFace', {
      'path': path,
    });
    if (res == null) return const <Offset>[];
    final out = <Offset>[];
    // Flat [x0, y0, x1, y1, ...] doubles coming back from Kotlin.
    for (var i = 0; i + 1 < res.length; i += 2) {
      final x = (res[i] as num?)?.toDouble();
      final y = (res[i + 1] as num?)?.toDouble();
      if (x == null || y == null) break;
      out.add(Offset(x, y));
    }
    return out;
  }

  /// Requests a CPU preview frame capped at [maxDim] on the longest edge.
  /// Returns null when the native render failed or produced no frame.
  Future<PreviewFrame?> renderPreview(int imageId, {int maxDim = 1024}) async {
    final res = await _method.invokeMapMethod<String, Object?>('render', {
      'imageId': imageId,
      'maxDim': maxDim,
    });
    if (res == null) return null;
    final bytes = res['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    return PreviewFrame(
      bytes: bytes,
      width: (res['width'] as num).toInt(),
      height: (res['height'] as num).toInt(),
    );
  }

  /// Renders the current edits at full resolution, encodes to [format]
  /// ('jpeg' | 'png') and saves into the gallery. Returns the saved content
  /// URI / path on success, or null on failure.
  Future<String?> exportImage(
    int imageId, {
    String format = 'jpeg',
    int quality = 92,
  }) async {
    try {
      return await _method.invokeMethod<String>('export', {
        'imageId': imageId,
        'format': format,
        'quality': quality,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> release(int imageId) =>
      _method.invokeMethod<void>('release', {'imageId': imageId});
}
