#ifndef MUPIC_CORE_ADJUSTMENTS_H_
#define MUPIC_CORE_ADJUSTMENTS_H_

#include <cstdint>

namespace mupic {

// Number of color ranges used by the HSL / Color Mixer panel
// (Red, Orange, Yellow, Green, Aqua, Blue, Purple + a global "all").
constexpr int kHslRanges = 8;

// Single source of truth for every Camera-Raw-style adjustment.
//
// This POD struct is shared verbatim by the CPU export pipeline and the GPU
// preview pipeline (uploaded as a uniform block / memcpy'd to a uniform
// buffer), which keeps preview and export numerically identical. Keep it
// trivially copyable and free of pointers.
//
// Neutral values below mean "no change"; ranges follow the Camera Raw
// convention (exposure in stops, most -100..100 sliders normalized to -1..1).
struct RawAdjustments {
    // ---- Basic panel ----
    float color_temp = 0.0f;      // white balance shift, normalized -1..1
    float tint = 0.0f;            // green/magenta shift, normalized -1..1
    float exposure = 0.0f;        // stops
    float contrast = 0.0f;        // -1..1
    float highlights = 0.0f;      // -1..1
    float shadows = 0.0f;         // -1..1
    float whites = 0.0f;          // -1..1
    float blacks = 0.0f;          // -1..1
    float texture = 0.0f;         // -1..1
    float clarity = 0.0f;         // -1..1
    float dehaze = 0.0f;          // -1..1
    float vibrance = 0.0f;        // -1..1
    float saturation = 0.0f;      // -1..1

    // ---- Tone curve (parametric) ----
    // Four region shadows/midtones1/midtones2/highlights, plus per-channel flags.
    float curve_rgb[5] = {0, 0, 0, 0, 0};
    float curve_red[5] = {0, 0, 0, 0, 0};
    float curve_green[5] = {0, 0, 0, 0, 0};
    float curve_blue[5] = {0, 0, 0, 0, 0};

    // ---- HSL / Color Mixer (per-range hue / sat / luminance) ----
    float hsl_hue[kHslRanges] = {0};
    float hsl_sat[kHslRanges] = {0};
    float hsl_lum[kHslRanges] = {0};

    // ---- Color Grading ----
    // Per-region arrays are indexed [0]=Shadows, [1]=Midtones, [2]=Highlights.
    // hue/sat/lum are normalized; grade_sat is a 0..1 cast magnitude, hue/lum -1..1.
    float grade_hue[3] = {0, 0, 0};
    float grade_sat[3] = {0, 0, 0};
    float grade_lum[3] = {0, 0, 0};
    float grade_blending = 0.5f;     // 0..1 transition softness
    float grade_midtone_range = 0.5f; // 0..1 balance pivot

    // ---- Detail ----
    float sharpen_amount = 0.0f;     // 0..1
    float sharpen_radius = 1.0f;     // px
    float sharpen_detail = 0.0f;     // 0..1
    float sharpen_masking = 0.0f;    // 0..1
    float nr_luminance = 0.0f;       // 0..1
    float nr_lum_detail = 0.5f;
    float nr_lum_contrast = 0.0f;
    float nr_color = 0.0f;           // 0..1
    float nr_color_detail = 0.5f;

    // ---- Effects ----
    float vignette_amount = 0.0f;    // -1..1
    float vignette_midpoint = 0.5f;
    float vignette_roundness = 0.0f; // -1..1
    float vignette_feather = 0.5f;
    float grain_amount = 0.0f;       // 0..1
    float grain_size = 0.5f;
    float grain_roughness = 0.5f;

    // ---- Calibration ----
    float shadow_tint = 0.0f;        // -1..1
    float calib_red_hue = 0.0f;
    float calib_red_sat = 0.0f;
    float calib_green_hue = 0.0f;
    float calib_green_sat = 0.0f;
    float calib_blue_hue = 0.0f;
    float calib_blue_sat = 0.0f;

    // ---- Transform / geometry ----
    float rotation_deg = 0.0f;
    float vertical_skew = 0.0f;
    float horizontal_skew = 0.0f;

    // ---- Lens corrections ----
    // Geometric ops applied by resampling the source *before* the color chain.
    // Lateral chromatic aberration is a per-channel radial magnification, so R/B
    // are sampled at slightly different scales than G. All normalized -1..1
    // except the rca toggle (0/1). Mirrored by gl_pipeline `sampleSource` and the
    // CPU `sampleSource` in color_pipeline.cpp.
    float lens_rca = 0.0f;           // Remove Chromatic Aberration toggle (0/1)
    float lens_defringe_red = 0.0f;  // red/cyan lateral CA
    float lens_defringe_blue = 0.0f; // blue/yellow lateral CA
    float lens_distortion = 0.0f;    // radial barrel/pincushion

    // ---- White balance (Kelvin, decoded from image + temp slider) ----
    float wb_kelvin = 6500.0f;
    float wb_multiplier_r = 1.0f;
    float wb_multiplier_g = 1.0f;
    float wb_multiplier_b = 1.0f;

    // ---- Crop / geometry (M7) ----
    // Normalized crop rect in *source* (unrotated) image space; the 90°
    // clockwise `crop_turns` is applied to the cropped region afterwards,
    // mirroring "rotate then crop" (the UI keeps the rect in rotated space by
    // transforming it on every rotate press). Geometry-only: the CPU pipeline
    // maps output pixels back through it before the color chain.
    float crop_left = 0.0f;
    float crop_top = 0.0f;
    float crop_right = 1.0f;
    float crop_bottom = 1.0f;
    float crop_turns = 0.0f;       // quarter turns clockwise, 0..3

    // ---- Beauty ----
    // Edge-preserving skin smoothing (flat regions blurred, edges kept) plus a
    // global midtone whitening lift. CPU-only (preview + export share it).
    float beauty_smooth = 0.0f;    // 磨皮 amount, 0..1
    float beauty_radius = 0.5f;    // smoothing kernel scale, 0..1
    float beauty_whitening = 0.0f; // 美白 amount, 0..1

    // 祛瑕 spots: (x, y, radius) normalized; x/y in [0,1] of W/H, radius of
    // min(W,H). radius <= 0 marks an unused slot (max 16 spots).
    static const int kMaxSpots = 16;
    float spots[kMaxSpots * 3] = {0};

    // Whitening skin-limit: 0 = global whitening (legacy), 1 = lift only
    // skin-colored pixels, in between = feathered blend. Appended LAST so the
    // byte offsets of every earlier field stay stable across the Dart<->native
    // memcpy contract (see jni_bridge.cpp nativeSetParams).
    float beauty_white_skin = 1.0f;

    // ---- Liquify (M9) ----
    // Manual deformation impulses: each is a 6-float tuple
    // (x, y, dx, dy, radius, type). x/y in [0,1] of the *source* image;
    // dx/dy are normalized displacement vectors; radius is relative to
    // min(W,H); type: 0=push 1=bloat 2=pucker 3=twirl. radius <= 0 marks an
    // unused slot. Appended after beauty_white_skin so the byte offsets of
    // every earlier field stay stable across the memcpy contract.
    static const int kMaxWarp = 64;
    float warp[kMaxWarp * 6] = {0};

    // ---- Face-directed liquify (M9b) ----
    // Dense face mesh subset (source-normalized x,y pairs) in the FIXED order
    // documented in MuPicEditor.detectFace / buildFaceImpulses. face_count is
    // the number of valid points (0 = no face). The four 0..1 sliders are turned
    // into extra deformation impulses natively (same warp engine as manual
    // liquify). Appended after warp[] so earlier byte offsets stay stable.
    static const int kMaxFacePts = 64;
    float face_pts[kMaxFacePts * 2] = {0};
    float face_count = 0.0f;
    float face_slim = 0.0f;  // 瘦脸
    float face_eye = 0.0f;   // 大眼
    float face_nose = 0.0f;  // 塑鼻
    float face_chin = 0.0f;  // 尖下巴

    bool isNeutral() const;

    static const RawAdjustments& identity();
};

}  // namespace mupic

#endif  // MUPIC_CORE_ADJUSTMENTS_H_
