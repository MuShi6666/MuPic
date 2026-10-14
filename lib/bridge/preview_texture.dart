import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Displays the CPU preview frame decoded from native RGBA bytes.
///
/// The native pipeline downscales + color-grades the image and returns raw
/// pixels; [EditorController] turns them into a [ui.Image] shown here via
/// [RawImage]. When [image] is null (no image yet / render in flight) a neutral
/// placeholder is shown so the editor canvas still lays out correctly.
class PreviewImage extends StatelessWidget {
  const PreviewImage({
    super.key,
    required this.image,
    required this.aspectRatio,
    this.placeholderLabel = 'No image',
  });

  final ui.Image? image;
  final double aspectRatio; // width / height of the source
  final String placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final img = image;
    final ratio = aspectRatio <= 0 ? 1.0 : aspectRatio;
    if (img == null) {
      return AspectRatio(
        aspectRatio: ratio,
        child: Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined,
              color: Colors.white54, size: 48),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: ratio,
      child: RawImage(image: img, fit: BoxFit.contain),
    );
  }
}
