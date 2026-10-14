import 'dart:ui' show Color;

import 'adjustments.dart';

/// A one-tap filter preset: a named [Adjustments] bundle + a gradient swatch
/// used to preview its look on the Filters page.
class FilterPreset {
  const FilterPreset({
    required this.name,
    required this.adjustments,
    required this.colors,
  });

  final String name;
  final Adjustments adjustments;
  final List<Color> colors;
}

/// Built-in presets. Values follow the -1..1 (or 0..1) slider convention used
/// across the panels; only scalar fields are set for predictable results.
const List<FilterPreset> kFilterPresets = [
  FilterPreset(
    name: '原片',
    adjustments: Adjustments(),
    colors: [Color(0xFFE9E4EF), Color(0xFFD7D2E4)],
  ),
  FilterPreset(
    name: '清新',
    adjustments: Adjustments(
      exposure: 0.12,
      contrast: 0.15,
      highlights: -0.1,
      shadows: 0.18,
      vibrance: 0.32,
      saturation: 0.08,
    ),
    colors: [Color(0xFFA8E6CF), Color(0xFFA9D6FF)],
  ),
  FilterPreset(
    name: '暖阳',
    adjustments: Adjustments(
      colorTemp: 0.32,
      contrast: 0.12,
      vibrance: 0.22,
      saturation: 0.1,
      highlights: 0.08,
    ),
    colors: [Color(0xFFFFC1A1), Color(0xFFFFE0A3)],
  ),
  FilterPreset(
    name: '冷调',
    adjustments: Adjustments(
      colorTemp: -0.34,
      contrast: 0.18,
      saturation: 0.04,
      shadows: 0.1,
    ),
    colors: [Color(0xFFA9D6FF), Color(0xFFC6B6FF)],
  ),
  FilterPreset(
    name: '胶片',
    adjustments: Adjustments(
      contrast: 0.3,
      saturation: -0.12,
      highlights: -0.2,
      shadows: 0.24,
      grainAmount: 0.4,
      grainSize: 0.5,
    ),
    colors: [Color(0xFFB7A48F), Color(0xFF8E7C6A)],
  ),
  FilterPreset(
    name: '黑白',
    adjustments: Adjustments(
      saturation: -1,
      contrast: 0.28,
      clarity: 0.2,
    ),
    colors: [Color(0xFFCFCFCF), Color(0xFF6E6E6E)],
  ),
  FilterPreset(
    name: '青橙',
    adjustments: Adjustments(
      contrast: 0.26,
      vibrance: 0.4,
      saturation: 0.1,
      colorTemp: 0.16,
      clarity: 0.12,
    ),
    colors: [Color(0xFFFF9E7A), Color(0xFF3FB7C4)],
  ),
  FilterPreset(
    name: '柔和',
    adjustments: Adjustments(
      contrast: -0.14,
      highlights: 0.1,
      shadows: 0.14,
      vibrance: 0.16,
      texture: -0.1,
    ),
    colors: [Color(0xFFFFC1D9), Color(0xFFD9CCFF)],
  ),
];
