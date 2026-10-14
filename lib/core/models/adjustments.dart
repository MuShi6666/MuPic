import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Number of HSL / Color Mixer ranges (Red, Orange, Yellow, Green, Aqua, Blue,
/// Purple, + a global "all").
const int kHslRanges = 8;

/// Maximum retouch (祛瑕) spots carried in the render struct; mirrors
/// `RawAdjustments::kMaxSpots` on the native side.
const int kMaxRetouchSpots = 16;

/// Maximum liquify deformation impulses carried in the render struct; mirrors
/// `RawAdjustments::kMaxWarp` on the native side.
const int kMaxWarp = 64;

/// Maximum face-mesh key points carried in the render struct; mirrors
/// `RawAdjustments::kMaxFacePts` on the native side.
const int kMaxFacePts = 64;

/// Liquify brush types, matching the native `warp[].type` encoding.
const int kWarpPush = 0;
const int kWarpBloat = 1;
const int kWarpPucker = 2;
const int kWarpTwirl = 3;

/// One retouch spot in normalized image space: x over width, y over height,
/// r over the shorter edge. Serialized into the native `spots[]` triplets.
class RetouchSpot {
  const RetouchSpot(this.x, this.y, this.r);
  final double x;
  final double y;
  final double r;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'x': x, 'y': y, 'r': r};

  factory RetouchSpot.fromJson(Map<String, dynamic> j) => RetouchSpot(
        (j['x'] as num?)?.toDouble() ?? 0,
        (j['y'] as num?)?.toDouble() ?? 0,
        (j['r'] as num?)?.toDouble() ?? 0,
      );
}

/// One liquify deformation impulse in normalized source space: center (x,y) in
/// [0,1], a normalized displacement vector (dx,dy), a brush [radius] over the
/// shorter edge, and a brush [type] (see kWarp* constants). Serialized into the
/// native `warp[]` 6-float tuples; radius <= 0 marks an unused slot.
class WarpImpulse {
  const WarpImpulse(this.x, this.y, this.dx, this.dy, this.r, this.type);
  final double x;
  final double y;
  final double dx;
  final double dy;
  final double r;
  final double type;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
        'dx': dx,
        'dy': dy,
        'r': r,
        'type': type,
      };

  factory WarpImpulse.fromJson(Map<String, dynamic> j) => WarpImpulse(
        (j['x'] as num?)?.toDouble() ?? 0,
        (j['y'] as num?)?.toDouble() ?? 0,
        (j['dx'] as num?)?.toDouble() ?? 0,
        (j['dy'] as num?)?.toDouble() ?? 0,
        (j['r'] as num?)?.toDouble() ?? 0,
        (j['type'] as num?)?.toDouble() ?? 0,
      );
}

/// Adjustment parameters mirroring, field for field and in the same order, the
/// native `mupic::RawAdjustments` struct (android/app/src/main/cpp/core/
/// adjustments.h).
///
/// Every native member is a contiguous `float`, so the struct's memory layout is
/// simply this class's fields serialized in declaration order as little-endian
/// float32. [toRenderBytes] produces exactly that byte image, which the JNI
/// layer memcpy's into the native struct (see jni_bridge.cpp `nativeSetParams`).
///
/// Neutral values mean "no change" (sliders normalized to -1..1 unless noted).
class Adjustments {
  const Adjustments({
    this.colorTemp = 0,
    this.tint = 0,
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.texture = 0,
    this.clarity = 0,
    this.dehaze = 0,
    this.vibrance = 0,
    this.saturation = 0,
    this.curveRgb = _kZero5,
    this.curveRed = _kZero5,
    this.curveGreen = _kZero5,
    this.curveBlue = _kZero5,
    this.hslHue = _kZero8,
    this.hslSat = _kZero8,
    this.hslLum = _kZero8,
    this.gradeHue = _kZero3,
    this.gradeSat = _kZero3,
    this.gradeLum = _kZero3,
    this.gradeBlending = 0.5,
    this.gradeMidtoneRange = 0.5,
    this.sharpenAmount = 0,
    this.sharpenRadius = 1,
    this.sharpenDetail = 0,
    this.sharpenMasking = 0,
    this.nrLuminance = 0,
    this.nrLumDetail = 0.5,
    this.nrLumContrast = 0,
    this.nrColor = 0,
    this.nrColorDetail = 0.5,
    this.vignetteAmount = 0,
    this.vignetteMidpoint = 0.5,
    this.vignetteRoundness = 0,
    this.vignetteFeather = 0.5,
    this.grainAmount = 0,
    this.grainSize = 0.5,
    this.grainRoughness = 0.5,
    this.shadowTint = 0,
    this.calibRedHue = 0,
    this.calibRedSat = 0,
    this.calibGreenHue = 0,
    this.calibGreenSat = 0,
    this.calibBlueHue = 0,
    this.calibBlueSat = 0,
    this.rotationDeg = 0,
    this.verticalSkew = 0,
    this.horizontalSkew = 0,
    this.lensRca = 0,
    this.lensDefringeRed = 0,
    this.lensDefringeBlue = 0,
    this.lensDistortion = 0,
    this.wbKelvin = 6500,
    this.wbMultiplierR = 1,
    this.wbMultiplierG = 1,
    this.wbMultiplierB = 1,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
    this.cropTurns = 0,
    this.beautySmooth = 0,
    this.beautyRadius = 0.5,
    this.beautyWhitening = 0,
    this.beautyWhiteSkin = 1,
    this.spots = const <RetouchSpot>[],
    this.warp = const <WarpImpulse>[],
    this.faceSlim = 0,
    this.faceEye = 0,
    this.faceNose = 0,
    this.faceChin = 0,
  });

  static const List<double> _kZero3 = [0, 0, 0];
  static const List<double> _kZero5 = [0, 0, 0, 0, 0];
  static const List<double> _kZero8 = [0, 0, 0, 0, 0, 0, 0, 0];

  static const Adjustments identity = Adjustments();

  // Basic panel
  final double colorTemp;
  final double tint;
  final double exposure;
  final double contrast;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double texture;
  final double clarity;
  final double dehaze;
  final double vibrance;
  final double saturation;

  // Tone curve
  final List<double> curveRgb;
  final List<double> curveRed;
  final List<double> curveGreen;
  final List<double> curveBlue;

  // HSL / Color Mixer
  final List<double> hslHue;
  final List<double> hslSat;
  final List<double> hslLum;

  // Color grading
  final List<double> gradeHue;
  final List<double> gradeSat;
  final List<double> gradeLum;
  final double gradeBlending;
  final double gradeMidtoneRange;

  // Detail
  final double sharpenAmount;
  final double sharpenRadius;
  final double sharpenDetail;
  final double sharpenMasking;
  final double nrLuminance;
  final double nrLumDetail;
  final double nrLumContrast;
  final double nrColor;
  final double nrColorDetail;

  // Effects
  final double vignetteAmount;
  final double vignetteMidpoint;
  final double vignetteRoundness;
  final double vignetteFeather;
  final double grainAmount;
  final double grainSize;
  final double grainRoughness;

  // Calibration
  final double shadowTint;
  final double calibRedHue;
  final double calibRedSat;
  final double calibGreenHue;
  final double calibGreenSat;
  final double calibBlueHue;
  final double calibBlueSat;

  // Transform
  final double rotationDeg;
  final double verticalSkew;
  final double horizontalSkew;

  // Lens corrections
  final double lensRca;          // Remove Chromatic Aberration toggle (0/1)
  final double lensDefringeRed;  // -1..1 red/cyan lateral CA
  final double lensDefringeBlue; // -1..1 blue/yellow lateral CA
  final double lensDistortion;   // -1..1 radial barrel/pincushion

  // White balance
  final double wbKelvin;
  final double wbMultiplierR;
  final double wbMultiplierG;
  final double wbMultiplierB;

  // Crop / geometry (M7). Normalized rect in source space + 90° clockwise
  // quarter turns applied to the cropped region.
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double cropTurns;

  // Beauty (M7): edge-preserving skin smoothing + whitening lift + spots.
  final double beautySmooth;
  final double beautyRadius;
  final double beautyWhitening;

  /// Whitening skin-limit: 0 = global lift (legacy), 1 = skin-only, between =
  /// feathered blend. Mirrors `RawAdjustments::beauty_white_skin` (last slot).
  final double beautyWhiteSkin;
  final List<RetouchSpot> spots;
  final List<WarpImpulse> warp;

  // Face-directed liquify auto sliders (M9b), 0..1. Mirror `RawAdjustments::
  // face_slim / face_eye / face_nose / face_chin`. The dense mesh points
  // themselves are NOT modelled here: they are recomputable detection metadata
  // passed as optional [toRenderBytes] args so they reach the native struct for
  // export without polluting equality / JSON (opening the liquify tab and auto
  // -detecting a face must not, on its own, mark the edit non-neutral).
  final double faceSlim; // 瘦脸
  final double faceEye; // 大眼
  final double faceNose; // 塑鼻
  final double faceChin; // 尖下巴

  /// Total float slots matching the native struct (keep in sync with
  /// adjustments.h). 676 floats as of M9b (543 + kMaxFacePts*2 face points +
  /// face_count + four face sliders).
  static const int kFloatCount = 676;

  /// Serializes to the exact little-endian float32 byte image of the native
  /// `RawAdjustments`. Field order here MUST match the struct declaration.
  Uint8List toRenderBytes({
    List<Offset> facePts = const <Offset>[],
    int faceCount = 0,
  }) {
    final data = Float32List(kFloatCount);
    var i = 0;
    void put(double v) => data[i++] = v;
    void putAll(List<double> l) {
      for (final v in l) {
        put(v);
      }
    }

    // Basic
    put(colorTemp);
    put(tint);
    put(exposure);
    put(contrast);
    put(highlights);
    put(shadows);
    put(whites);
    put(blacks);
    put(texture);
    put(clarity);
    put(dehaze);
    put(vibrance);
    put(saturation);
    // Tone curve
    putAll(curveRgb);
    putAll(curveRed);
    putAll(curveGreen);
    putAll(curveBlue);
    // HSL
    putAll(hslHue);
    putAll(hslSat);
    putAll(hslLum);
    // Color grading
    putAll(gradeHue);
    putAll(gradeSat);
    putAll(gradeLum);
    put(gradeBlending);
    put(gradeMidtoneRange);
    // Detail
    put(sharpenAmount);
    put(sharpenRadius);
    put(sharpenDetail);
    put(sharpenMasking);
    put(nrLuminance);
    put(nrLumDetail);
    put(nrLumContrast);
    put(nrColor);
    put(nrColorDetail);
    // Effects
    put(vignetteAmount);
    put(vignetteMidpoint);
    put(vignetteRoundness);
    put(vignetteFeather);
    put(grainAmount);
    put(grainSize);
    put(grainRoughness);
    // Calibration
    put(shadowTint);
    put(calibRedHue);
    put(calibRedSat);
    put(calibGreenHue);
    put(calibGreenSat);
    put(calibBlueHue);
    put(calibBlueSat);
    // Transform
    put(rotationDeg);
    put(verticalSkew);
    put(horizontalSkew);
    // Lens corrections
    put(lensRca);
    put(lensDefringeRed);
    put(lensDefringeBlue);
    put(lensDistortion);
    // White balance
    put(wbKelvin);
    put(wbMultiplierR);
    put(wbMultiplierG);
    put(wbMultiplierB);
    // Crop / geometry
    put(cropLeft);
    put(cropTop);
    put(cropRight);
    put(cropBottom);
    put(cropTurns);
    // Beauty
    put(beautySmooth);
    put(beautyRadius);
    put(beautyWhitening);
    // Spot triplets, zero-padded to the fixed native capacity.
    for (var s = 0; s < kMaxRetouchSpots; s++) {
      if (s < spots.length) {
        put(spots[s].x);
        put(spots[s].y);
        put(spots[s].r);
      } else {
        put(0);
        put(0);
        put(0);
      }
    }
    // Whitening skin-limit: appended last, matching the native struct order.
    put(beautyWhiteSkin);
    // Liquify impulses, zero-padded to the fixed native capacity.
    for (var w = 0; w < kMaxWarp; w++) {
      if (w < warp.length) {
        put(warp[w].x);
        put(warp[w].y);
        put(warp[w].dx);
        put(warp[w].dy);
        put(warp[w].r);
        put(warp[w].type);
      } else {
        for (var k = 0; k < 6; k++) {
          put(0);
        }
      }
    }
    // Face-mesh (x, y) source-normalized pairs, zero-padded to the fixed native
    // capacity, then face_count and the four auto sliders. `facePts` / `faceCount`
    // are supplied by the caller (editor_channel.setParams) purely to feed the
    // native warp engine; they are not part of equality / JSON.
    final int nFace = facePts.length < faceCount ? facePts.length : faceCount;
    for (var f = 0; f < kMaxFacePts; f++) {
      if (f < nFace) {
        put(facePts[f].dx);
        put(facePts[f].dy);
      } else {
        put(0);
        put(0);
      }
    }
    put(nFace.toDouble());
    put(faceSlim);
    put(faceEye);
    put(faceNose);
    put(faceChin);

    assert(i == kFloatCount, 'Adjustments layout drift from native struct');
    return data.buffer.asUint8List();
  }

  // ---- Element-editing helpers (arrays are shared const defaults) ----
  static List<double> _with(List<double> src, int index, double value) {
    final out = List<double>.of(src);
    out[index] = value;
    return out;
  }

  /// Set one of the four region controls (0=shadows,1=mid1,2=mid2,3=highlights)
  /// for the selected curve channel: 'rgb' | 'red' | 'green' | 'blue'.
  Adjustments setCurve(String channel, int index, double value) {
    switch (channel) {
      case 'red':
        return copyWith(curveRed: _with(curveRed, index, value));
      case 'green':
        return copyWith(curveGreen: _with(curveGreen, index, value));
      case 'blue':
        return copyWith(curveBlue: _with(curveBlue, index, value));
      default:
        return copyWith(curveRgb: _with(curveRgb, index, value));
    }
  }

  /// Set one HSL / Color Mixer control. [kind]: 'hue' | 'sat' | 'lum'.
  Adjustments setHsl(int range, String kind, double value) {
    switch (kind) {
      case 'sat':
        return copyWith(hslSat: _with(hslSat, range, value));
      case 'lum':
        return copyWith(hslLum: _with(hslLum, range, value));
      default:
        return copyWith(hslHue: _with(hslHue, range, value));
    }
  }

  /// Set one color-grading region control. [region]: 0=shadows,1=midtones,
  /// 2=highlights. [kind]: 'hue' | 'sat' | 'lum'.
  Adjustments setGrade(int region, String kind, double value) {
    switch (kind) {
      case 'sat':
        return copyWith(gradeSat: _with(gradeSat, region, value));
      case 'lum':
        return copyWith(gradeLum: _with(gradeLum, region, value));
      default:
        return copyWith(gradeHue: _with(gradeHue, region, value));
    }
  }

  Adjustments copyWith({
    double? colorTemp,
    double? tint,
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? texture,
    double? clarity,
    double? dehaze,
    double? vibrance,
    double? saturation,
    List<double>? curveRgb,
    List<double>? curveRed,
    List<double>? curveGreen,
    List<double>? curveBlue,
    List<double>? hslHue,
    List<double>? hslSat,
    List<double>? hslLum,
    List<double>? gradeHue,
    List<double>? gradeSat,
    List<double>? gradeLum,
    double? gradeBlending,
    double? gradeMidtoneRange,
    double? sharpenAmount,
    double? sharpenRadius,
    double? sharpenDetail,
    double? sharpenMasking,
    double? nrLuminance,
    double? nrLumDetail,
    double? nrLumContrast,
    double? nrColor,
    double? nrColorDetail,
    double? vignetteAmount,
    double? vignetteMidpoint,
    double? vignetteRoundness,
    double? vignetteFeather,
    double? grainAmount,
    double? grainSize,
    double? grainRoughness,
    double? shadowTint,
    double? calibRedHue,
    double? calibRedSat,
    double? calibGreenHue,
    double? calibGreenSat,
    double? calibBlueHue,
    double? calibBlueSat,
    double? rotationDeg,
    double? verticalSkew,
    double? horizontalSkew,
    double? lensRca,
    double? lensDefringeRed,
    double? lensDefringeBlue,
    double? lensDistortion,
    double? wbKelvin,
    double? wbMultiplierR,
    double? wbMultiplierG,
    double? wbMultiplierB,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    double? cropTurns,
    double? beautySmooth,
    double? beautyRadius,
    double? beautyWhitening,
    double? beautyWhiteSkin,
    List<RetouchSpot>? spots,
    List<WarpImpulse>? warp,
    double? faceSlim,
    double? faceEye,
    double? faceNose,
    double? faceChin,
  }) {
    return Adjustments(
      colorTemp: colorTemp ?? this.colorTemp,
      tint: tint ?? this.tint,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      texture: texture ?? this.texture,
      clarity: clarity ?? this.clarity,
      dehaze: dehaze ?? this.dehaze,
      vibrance: vibrance ?? this.vibrance,
      saturation: saturation ?? this.saturation,
      curveRgb: curveRgb ?? this.curveRgb,
      curveRed: curveRed ?? this.curveRed,
      curveGreen: curveGreen ?? this.curveGreen,
      curveBlue: curveBlue ?? this.curveBlue,
      hslHue: hslHue ?? this.hslHue,
      hslSat: hslSat ?? this.hslSat,
      hslLum: hslLum ?? this.hslLum,
      gradeHue: gradeHue ?? this.gradeHue,
      gradeSat: gradeSat ?? this.gradeSat,
      gradeLum: gradeLum ?? this.gradeLum,
      gradeBlending: gradeBlending ?? this.gradeBlending,
      gradeMidtoneRange: gradeMidtoneRange ?? this.gradeMidtoneRange,
      sharpenAmount: sharpenAmount ?? this.sharpenAmount,
      sharpenRadius: sharpenRadius ?? this.sharpenRadius,
      sharpenDetail: sharpenDetail ?? this.sharpenDetail,
      sharpenMasking: sharpenMasking ?? this.sharpenMasking,
      nrLuminance: nrLuminance ?? this.nrLuminance,
      nrLumDetail: nrLumDetail ?? this.nrLumDetail,
      nrLumContrast: nrLumContrast ?? this.nrLumContrast,
      nrColor: nrColor ?? this.nrColor,
      nrColorDetail: nrColorDetail ?? this.nrColorDetail,
      vignetteAmount: vignetteAmount ?? this.vignetteAmount,
      vignetteMidpoint: vignetteMidpoint ?? this.vignetteMidpoint,
      vignetteRoundness: vignetteRoundness ?? this.vignetteRoundness,
      vignetteFeather: vignetteFeather ?? this.vignetteFeather,
      grainAmount: grainAmount ?? this.grainAmount,
      grainSize: grainSize ?? this.grainSize,
      grainRoughness: grainRoughness ?? this.grainRoughness,
      shadowTint: shadowTint ?? this.shadowTint,
      calibRedHue: calibRedHue ?? this.calibRedHue,
      calibRedSat: calibRedSat ?? this.calibRedSat,
      calibGreenHue: calibGreenHue ?? this.calibGreenHue,
      calibGreenSat: calibGreenSat ?? this.calibGreenSat,
      calibBlueHue: calibBlueHue ?? this.calibBlueHue,
      calibBlueSat: calibBlueSat ?? this.calibBlueSat,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      verticalSkew: verticalSkew ?? this.verticalSkew,
      horizontalSkew: horizontalSkew ?? this.horizontalSkew,
      lensRca: lensRca ?? this.lensRca,
      lensDefringeRed: lensDefringeRed ?? this.lensDefringeRed,
      lensDefringeBlue: lensDefringeBlue ?? this.lensDefringeBlue,
      lensDistortion: lensDistortion ?? this.lensDistortion,
      wbKelvin: wbKelvin ?? this.wbKelvin,
      wbMultiplierR: wbMultiplierR ?? this.wbMultiplierR,
      wbMultiplierG: wbMultiplierG ?? this.wbMultiplierG,
      wbMultiplierB: wbMultiplierB ?? this.wbMultiplierB,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      cropTurns: cropTurns ?? this.cropTurns,
      beautySmooth: beautySmooth ?? this.beautySmooth,
      beautyRadius: beautyRadius ?? this.beautyRadius,
      beautyWhitening: beautyWhitening ?? this.beautyWhitening,
      beautyWhiteSkin: beautyWhiteSkin ?? this.beautyWhiteSkin,
      spots: spots ?? this.spots,
      warp: warp ?? this.warp,
      faceSlim: faceSlim ?? this.faceSlim,
      faceEye: faceEye ?? this.faceEye,
      faceNose: faceNose ?? this.faceNose,
      faceChin: faceChin ?? this.faceChin,
    );
  }

  /// Full-frame, unrotated copy: what the native side receives *while* the
  /// crop overlay is being dragged, so the canvas shows the whole image.
  Adjustments withCropNeutralized() => copyWith(
        cropLeft: 0,
        cropTop: 0,
        cropRight: 1,
        cropBottom: 1,
        cropTurns: 0,
      );

  /// Replace the retouch spot list (capped at [kMaxRetouchSpots]).
  Adjustments withSpots(List<RetouchSpot> next) => copyWith(
        spots: next.length > kMaxRetouchSpots
            ? next.sublist(0, kMaxRetouchSpots)
            : next,
      );

  /// Replace the liquify impulse list (capped at [kMaxWarp]).
  Adjustments withWarp(List<WarpImpulse> next) => copyWith(
        warp: next.length > kMaxWarp ? next.sublist(0, kMaxWarp) : next,
      );

  /// Layer a filter [preset] on top of the current adjustments by adding its
  /// scalar deviations and clamping to each slider's range, rather than
  /// replacing the whole set. Curve / HSL / grading arrays, white balance,
  /// crop / geometry, beauty and spots are all preserved from `this`, so
  /// applying a preset no longer wipes manual edits.
  Adjustments mergeWithPreset(Adjustments preset) {
    double add(double base, double delta, {double lo = -1, double hi = 1}) =>
        (base + delta).clamp(lo, hi).toDouble();
    return copyWith(
      colorTemp: add(colorTemp, preset.colorTemp),
      tint: add(tint, preset.tint),
      exposure: add(exposure, preset.exposure),
      contrast: add(contrast, preset.contrast),
      highlights: add(highlights, preset.highlights),
      shadows: add(shadows, preset.shadows),
      vibrance: add(vibrance, preset.vibrance),
      saturation: add(saturation, preset.saturation),
      clarity: add(clarity, preset.clarity),
      texture: add(texture, preset.texture),
      grainAmount: add(grainAmount, preset.grainAmount, lo: 0, hi: 1),
      grainSize: add(grainSize, preset.grainSize, lo: 0, hi: 1),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'colorTemp': colorTemp,
        'tint': tint,
        'exposure': exposure,
        'contrast': contrast,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'texture': texture,
        'clarity': clarity,
        'dehaze': dehaze,
        'vibrance': vibrance,
        'saturation': saturation,
        'curveRgb': curveRgb,
        'curveRed': curveRed,
        'curveGreen': curveGreen,
        'curveBlue': curveBlue,
        'hslHue': hslHue,
        'hslSat': hslSat,
        'hslLum': hslLum,
        'gradeHue': gradeHue,
        'gradeSat': gradeSat,
        'gradeLum': gradeLum,
        'gradeBlending': gradeBlending,
        'gradeMidtoneRange': gradeMidtoneRange,
        'rotationDeg': rotationDeg,
        'wbKelvin': wbKelvin,
        'wbMultiplierR': wbMultiplierR,
        'wbMultiplierG': wbMultiplierG,
        'wbMultiplierB': wbMultiplierB,
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropRight': cropRight,
        'cropBottom': cropBottom,
        'cropTurns': cropTurns,
        'beautySmooth': beautySmooth,
        'beautyRadius': beautyRadius,
        'beautyWhitening': beautyWhitening,
        'beautyWhiteSkin': beautyWhiteSkin,
        'spots': spots.map((s) => s.toJson()).toList(),
        'warp': warp.map((w) => w.toJson()).toList(),
        'faceSlim': faceSlim,
        'faceEye': faceEye,
        'faceNose': faceNose,
        'faceChin': faceChin,
      };

  factory Adjustments.fromJson(Map<String, dynamic> j) => Adjustments(
        colorTemp: (j['colorTemp'] as num?)?.toDouble() ?? 0,
        tint: (j['tint'] as num?)?.toDouble() ?? 0,
        exposure: (j['exposure'] as num?)?.toDouble() ?? 0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 0,
        highlights: (j['highlights'] as num?)?.toDouble() ?? 0,
        shadows: (j['shadows'] as num?)?.toDouble() ?? 0,
        whites: (j['whites'] as num?)?.toDouble() ?? 0,
        blacks: (j['blacks'] as num?)?.toDouble() ?? 0,
        texture: (j['texture'] as num?)?.toDouble() ?? 0,
        clarity: (j['clarity'] as num?)?.toDouble() ?? 0,
        dehaze: (j['dehaze'] as num?)?.toDouble() ?? 0,
        vibrance: (j['vibrance'] as num?)?.toDouble() ?? 0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 0,
        curveRgb: _list(j['curveRgb'], 5),
        curveRed: _list(j['curveRed'], 5),
        curveGreen: _list(j['curveGreen'], 5),
        curveBlue: _list(j['curveBlue'], 5),
        hslHue: _list(j['hslHue'], 8),
        hslSat: _list(j['hslSat'], 8),
        hslLum: _list(j['hslLum'], 8),
        gradeHue: _list(j['gradeHue'], 3),
        gradeSat: _list(j['gradeSat'], 3),
        gradeLum: _list(j['gradeLum'], 3),
        gradeBlending: (j['gradeBlending'] as num?)?.toDouble() ?? 0.5,
        gradeMidtoneRange: (j['gradeMidtoneRange'] as num?)?.toDouble() ?? 0.5,
        rotationDeg: (j['rotationDeg'] as num?)?.toDouble() ?? 0,
        wbKelvin: (j['wbKelvin'] as num?)?.toDouble() ?? 6500,
        wbMultiplierR: (j['wbMultiplierR'] as num?)?.toDouble() ?? 1,
        wbMultiplierG: (j['wbMultiplierG'] as num?)?.toDouble() ?? 1,
        wbMultiplierB: (j['wbMultiplierB'] as num?)?.toDouble() ?? 1,
        cropLeft: (j['cropLeft'] as num?)?.toDouble() ?? 0,
        cropTop: (j['cropTop'] as num?)?.toDouble() ?? 0,
        cropRight: (j['cropRight'] as num?)?.toDouble() ?? 1,
        cropBottom: (j['cropBottom'] as num?)?.toDouble() ?? 1,
        cropTurns: (j['cropTurns'] as num?)?.toDouble() ?? 0,
        beautySmooth: (j['beautySmooth'] as num?)?.toDouble() ?? 0,
        beautyRadius: (j['beautyRadius'] as num?)?.toDouble() ?? 0.5,
        beautyWhitening: (j['beautyWhitening'] as num?)?.toDouble() ?? 0,
        beautyWhiteSkin: (j['beautyWhiteSkin'] as num?)?.toDouble() ?? 1,
        spots: (j['spots'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(RetouchSpot.fromJson)
                .toList() ??
            const <RetouchSpot>[],
        warp: (j['warp'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(WarpImpulse.fromJson)
                .toList() ??
            const <WarpImpulse>[],
        faceSlim: (j['faceSlim'] as num?)?.toDouble() ?? 0,
        faceEye: (j['faceEye'] as num?)?.toDouble() ?? 0,
        faceNose: (j['faceNose'] as num?)?.toDouble() ?? 0,
        faceChin: (j['faceChin'] as num?)?.toDouble() ?? 0,
      );

  static List<double> _list(dynamic v, int len) {
    if (v is List) {
      final out = List<double>.filled(len, 0);
      for (var i = 0; i < len && i < v.length; i++) {
        out[i] = (v[i] as num).toDouble();
      }
      return out;
    }
    return List<double>.filled(len, 0);
  }

  @override
  bool operator ==(Object other) =>
      other is Adjustments && listEquals(other.toRenderBytes(), toRenderBytes());

  @override
  int get hashCode => Object.hashAll(toRenderBytes());
}

bool listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
