#include "core/color_pipeline.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include "gl/lut_builder.h"

namespace mupic {

namespace {

inline float clamp01(float v) { return v < 0.f ? 0.f : (v > 1.f ? 1.f : v); }

inline float smoothstep01(float a, float b, float x) {
    float t = clamp01((x - a) / (b - a));
    return t * t * (3.f - 2.f * t);
}

// Same GLSL-compatible smoothstep used by grading (arbitrary edges).
inline float glSmoothstep(float e0, float e1, float x) {
    if (e1 == e0) return x < e0 ? 0.f : 1.f;
    return smoothstep01(e0, e1, x);
}

constexpr float kLumaR = 0.2126f, kLumaG = 0.7152f, kLumaB = 0.0722f;

// Skin-likelihood in [0,1] from a pixel's RGB, via feathered Rec.601 YCbCr
// chroma windows plus a luma band and the R>G>B dominance rule. Used to gate
// the whitening lift so it brightens skin / faces instead of the whole frame.
inline float skinWeight(float r, float g, float b) {
    const float y = 0.299f * r + 0.587f * g + 0.114f * b;
    const float cb = 0.5f - 0.168736f * r - 0.33186f * g + 0.5f * b;
    const float cr = 0.5f + 0.5f * r - 0.418688f * g - 0.081312f * b;
    const float f = 0.03f;  // window feather
    const float inCb = glSmoothstep(0.33f - f, 0.33f + f, cb) *
                       (1.f - glSmoothstep(0.50f - f, 0.50f + f, cb));
    const float inCr = glSmoothstep(0.50f - f, 0.50f + f, cr) *
                       (1.f - glSmoothstep(0.58f - f, 0.58f + f, cr));
    const float luma = glSmoothstep(0.05f, 0.25f, y) *
                       (1.f - glSmoothstep(0.90f, 1.0f, y));
    const float rgbRule = (r > g && r > b) ? 1.f : 0.35f;
    return clamp01(inCb * inCr * luma * rgbRule);
}

// ---- Liquify (M9): backward-warp displacement field ----
// Accumulated source-pixel displacement at source-normalized (u,v) from `n`
// 6-float impulse tuples in `w` (x, y, dx, dy, radius, type). Distances are
// measured in pixel space so the brush is circular regardless of aspect; a
// (1-t)^2 window feathers each impulse edge. Returns the displacement in
// *normalized* units (du over width, dv over height) so the caller can add it
// straight onto the fractional pixel. Types: 0=push 1=bloat 2=pucker 3=twirl.
// bloat/pucker move the sample along the radius (inward = enlarge under a
// backward warp); twirl rotates about the center; push translates by the vector.
inline void evalWarp(float u, float v, const float* w, int n,
                     int W, int H, float minDim, float& du, float& dv) {
    du = 0.f;
    dv = 0.f;
    const float px = u * W;
    const float py = v * H;
    float ddx = 0.f, ddy = 0.f;
    for (int i = 0; i < n; ++i) {
        const float rr = w[i * 6 + 4];
        if (rr <= 0.f) continue;
        const float cx = w[i * 6 + 0] * W;
        const float cy = w[i * 6 + 1] * H;
        const float idx = w[i * 6 + 2];
        const float idy = w[i * 6 + 3];
        const int type = static_cast<int>(w[i * 6 + 5] + 0.5f);
        const float rad = std::max(1.f, rr * minDim);
        const float ox = px - cx, oy = py - cy;
        const float dist = std::sqrt(ox * ox + oy * oy);
        if (dist >= rad) continue;
        const float inv = 1.f - dist / rad;
        const float fall = inv * inv;
        const float mag = std::sqrt(idx * idx + idy * idy);
        switch (type) {
            case 1: {  // bloat: pull sample toward center -> region enlarges
                const float k = std::min(0.5f, mag * 2.f);
                ddx += -ox * k * fall;
                ddy += -oy * k * fall;
                break;
            }
            case 2: {  // pucker: push sample away from center -> region shrinks
                const float k = std::min(0.5f, mag * 2.f);
                ddx += ox * k * fall;
                ddy += oy * k * fall;
                break;
            }
            case 3: {  // twirl: rotate about the center
                const float ang = mag * fall * 3.14159265f * (idx >= 0.f ? 1.f : -1.f);
                const float ca = std::cos(ang), sa = std::sin(ang);
                const float rx = ox * ca - oy * sa;
                const float ry = ox * sa + oy * ca;
                ddx += (rx - ox);
                ddy += (ry - oy);
                break;
            }
            default: {  // 0 push
                ddx += idx * minDim * fall;
                ddy += idy * minDim * fall;
                break;
            }
        }
    }
    du = ddx / static_cast<float>(W);
    dv = ddy / static_cast<float>(H);
}

// ---- Face-directed liquify (M9b): keypoints -> auto impulses ----
// Fixed point order produced by MuPicEditor.detectFace (source-normalized).
// Keep in sync with the Kotlin emitter and the Dart guide painter.
namespace face {
constexpr int kOvalStart = 0;    // 0..35 face oval (36 pts, canonical order)
constexpr int kOvalCount = 36;
constexpr int kChinInOval = 18;  // oval index that is the chin bottom (152)
constexpr int kRightPupil = 36;
constexpr int kLeftPupil = 37;
constexpr int kNoseTip = 38;
constexpr int kNoseBridge = 39;
constexpr int kRightWing = 40;
constexpr int kLeftWing = 41;
constexpr int kRightMouth = 42;
constexpr int kLeftMouth = 43;
constexpr int kChin = 44;
constexpr int kTotal = 45;
}  // namespace face

// Build the temporary impulse list (same 6-float layout as adj.warp) from the
// face keypoints + the four 0..1 sliders. Not counted against the manual warp
// budget; evaluated by the same engine so preview == export.
inline void buildFaceImpulses(const RawAdjustments& adj, std::vector<float>& out) {
    out.clear();
    const int n = static_cast<int>(adj.face_count + 0.5f);
    if (n < face::kTotal) return;
    const float* fp = adj.face_pts;
    auto X = [&](int i) { return fp[i * 2]; };
    auto Y = [&](int i) { return fp[i * 2 + 1]; };
    auto add = [&](float x, float y, float dx, float dy, float r, float type) {
        out.insert(out.end(), {x, y, dx, dy, r, type});
    };
    // Oval centroid (rough face center).
    float cx = 0.f, cy = 0.f;
    for (int i = 0; i < face::kOvalCount; ++i) { cx += X(i); cy += Y(i); }
    cx /= face::kOvalCount;
    cy /= face::kOvalCount;

    // 瘦脸: pull the two cheek bands of the oval toward the face center.
    if (adj.face_slim > 0.f) {
        const int cheeks[] = {6, 7, 8, 9, 10, 26, 27, 28, 29, 30};
        for (int ci : cheeks) {
            add(X(ci), Y(ci), (cx - X(ci)) * adj.face_slim * 0.5f,
                (cy - Y(ci)) * adj.face_slim * 0.5f, 0.05f, 0.f);
        }
    }
    // 大眼: bloat around each pupil (magnitude drives the radial k).
    if (adj.face_eye > 0.f) {
        const float m = adj.face_eye * 0.3f;
        add(X(face::kRightPupil), Y(face::kRightPupil), m, 0.f, 0.03f, 1.f);
        add(X(face::kLeftPupil), Y(face::kLeftPupil), m, 0.f, 0.03f, 1.f);
    }
    // 塑鼻: draw the two alae toward the nose bridge.
    if (adj.face_nose > 0.f) {
        add(X(face::kRightWing), Y(face::kRightWing),
            (X(face::kNoseBridge) - X(face::kRightWing)) * adj.face_nose * 0.6f,
            0.f, 0.02f, 0.f);
        add(X(face::kLeftWing), Y(face::kLeftWing),
            (X(face::kNoseBridge) - X(face::kLeftWing)) * adj.face_nose * 0.6f,
            0.f, 0.02f, 0.f);
    }
    // 尖下巴: taper the lower-jaw oval points toward the chin tip / center.
    if (adj.face_chin > 0.f) {
        const int jaw[] = {15, 16, 17, 18, 19, 20, 21};
        for (int ji : jaw) {
            add(X(ji), Y(ji), (cx - X(ji)) * adj.face_chin * 0.4f,
                (Y(face::kChin) - Y(ji)) * adj.face_chin * 0.3f, 0.04f, 0.f);
        }
    }
}

// ---- HSL round trip (mirrors the GLSL helpers exactly) ----
inline float hue2rgb(float p, float q, float t) {
    if (t < 0.f) t += 1.f;
    if (t > 1.f) t -= 1.f;
    if (t < 1.f / 6.f) return p + (q - p) * 6.f * t;
    if (t < 1.f / 2.f) return q;
    if (t < 2.f / 3.f) return p + (q - p) * (2.f / 3.f - t) * 6.f;
    return p;
}

inline void hsl2rgb(float h, float s, float l, float& r, float& g, float& b) {
    if (s <= 1e-6f) {
        r = g = b = l;
        return;
    }
    const float q = l < 0.5f ? l * (1.f + s) : l + s - l * s;
    const float p = 2.f * l - q;
    r = hue2rgb(p, q, h + 1.f / 3.f);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1.f / 3.f);
}

inline void rgb2hsl(float r, float g, float b, float& h, float& s, float& l) {
    const float mx = std::max(r, std::max(g, b));
    const float mn = std::min(r, std::min(g, b));
    l = (mx + mn) * 0.5f;
    const float d = mx - mn;
    if (d <= 1e-6f) {
        h = 0.f;
        s = 0.f;
        return;
    }
    s = l > 0.5f ? d / (2.f - mx - mn) : d / (mx + mn);
    if (mx == r) {
        h = (g - b) / d + (g < b ? 6.f : 0.f);
    } else if (mx == g) {
        h = (b - r) / d + 2.f;
    } else {
        h = (r - g) / d + 4.f;
    }
    h /= 6.f;
}

inline float fractf(float v) { return v - std::floor(v); }

inline float hueDist(float a, float b) {
    float d = std::fabs(a - b);
    return std::fmin(d, 1.f - d);
}

// Named range hue centers (degrees/360): Red, Orange, Yellow, Green, Aqua, Blue, Purple.
constexpr float kHslWidth = 40.f / 360.f;
constexpr float kHueFactor = 60.f / 360.f;  // slider +-1 -> +-60 deg
constexpr float kLumFactor = 0.5f;

inline float hslCenter(int i) {
    static const float kC[7] = {0.f / 360.f, 30.f / 360.f, 60.f / 360.f, 120.f / 360.f,
                               180.f / 360.f, 240.f / 360.f, 300.f / 360.f};
    return kC[i];
}

// HSL / Color Mixer: per-range hue/sat/lum with triangular hue falloff, + a
// global "all" range (index 7). Mirrored in the GLSL shader `applyHsl`.
inline void applyHsl(float& r, float& g, float& b, const RawAdjustments& adj) {
    float h, s, l;
    rgb2hsl(r, g, b, h, s, l);

    float hue_sum = 0.f, sat_sum = 0.f, lum_sum = 0.f;
    for (int i = 0; i < 7; ++i) {
        const float w = std::max(0.f, 1.f - hueDist(h, hslCenter(i)) / kHslWidth);
        hue_sum += w * adj.hsl_hue[i];
        sat_sum += w * adj.hsl_sat[i];
        lum_sum += w * adj.hsl_lum[i];
    }
    // Global "All" range applied at full weight.
    hue_sum += adj.hsl_hue[7];
    sat_sum += adj.hsl_sat[7];
    lum_sum += adj.hsl_lum[7];

    h = fractf(h + hue_sum * kHueFactor);
    s = clamp01(s * (1.f + sat_sum));
    l = clamp01(l * (1.f + lum_sum * kLumFactor));
    hsl2rgb(h, s, l, r, g, b);
}

// Color Grading: luminance-weighted split toning for shadows/mids/highlights.
// Mirrored in the GLSL shader `applyGrade`.
inline void applyGrade(float& r, float& g, float& b, const RawAdjustments& adj) {
    const float lum = r * kLumaR + g * kLumaG + b * kLumaB;

    const float w = 0.2f + adj.grade_blending * 0.6f;
    const float bal = adj.grade_midtone_range - 0.5f;
    const float shC = 0.4f + bal * 0.4f;
    const float hiC = 0.6f + bal * 0.4f;
    const float ws = 1.f - glSmoothstep(shC - w, shC + w, lum);
    const float wh = glSmoothstep(hiC - w, hiC + w, lum);
    const float wm = clamp01(1.f - ws - wh);

    // Tint color per region: hue(-1..1)->wheel, sat(0..1) magnitude, 50% lightness.
    float tr, tg, tb;
    float sr[3], sg[3], sb[3];
    for (int i = 0; i < 3; ++i) {
        const float h01 = fractf(adj.grade_hue[i] * 0.5f + 0.5f);
        hsl2rgb(h01, clamp01(adj.grade_sat[i]), 0.5f, tr, tg, tb);
        sr[i] = tr;
        sg[i] = tg;
        sb[i] = tb;
    }

    const float cw = 0.5f;  // cast strength
    r += cw * (ws * (sr[0] - 0.5f) + wm * (sr[1] - 0.5f) + wh * (sr[2] - 0.5f));
    g += cw * (ws * (sg[0] - 0.5f) + wm * (sg[1] - 0.5f) + wh * (sg[2] - 0.5f));
    b += cw * (ws * (sb[0] - 0.5f) + wm * (sb[1] - 0.5f) + wh * (sb[2] - 0.5f));

    const float lumK = 1.f + ws * adj.grade_lum[0] + wm * adj.grade_lum[1] + wh * adj.grade_lum[2];
    r *= lumK;
    g *= lumK;
    b *= lumK;

    r = clamp01(r);
    g = clamp01(g);
    b = clamp01(b);
}

// CPU mirror of the GLSL `tone()` operator in gl/gl_pipeline.cpp. Both MUST stay
// numerically identical (plan: preview/export parity test).
inline void tone(float& r, float& g, float& b, const DecodeInfo& info,
                 const RawAdjustments& adj) {
    r *= info.wb_multiplier[0];
    g *= info.wb_multiplier[1];
    b *= info.wb_multiplier[2];

    r *= std::pow(2.f, adj.color_temp * 0.5f);
    b *= std::pow(2.f, -adj.color_temp * 0.5f);
    g *= std::pow(2.f, adj.tint * 0.3f);

    const float expGain = std::pow(2.f, adj.exposure);
    r *= expGain;
    g *= expGain;
    b *= expGain;

    float lum = r * kLumaR + g * kLumaG + b * kLumaB;
    float hl_w = smoothstep01(0.5f, 1.0f, lum);
    float sh_w = 1.f - smoothstep01(0.0f, 0.5f, lum);
    r += adj.highlights * 0.5f * hl_w;
    g += adj.highlights * 0.5f * hl_w;
    b += adj.highlights * 0.5f * hl_w;
    r += adj.shadows * 0.5f * sh_w;
    g += adj.shadows * 0.5f * sh_w;
    b += adj.shadows * 0.5f * sh_w;
    r += adj.whites * 0.2f * hl_w;
    g += adj.whites * 0.2f * hl_w;
    b += adj.whites * 0.2f * hl_w;
    r += adj.blacks * 0.2f * sh_w;
    g += adj.blacks * 0.2f * sh_w;
    b += adj.blacks * 0.2f * sh_w;

    const float cs = 1.f + adj.contrast;
    r = (r - 0.5f) * cs + 0.5f;
    g = (g - 0.5f) * cs + 0.5f;
    b = (b - 0.5f) * cs + 0.5f;

    float l2 = r * kLumaR + g * kLumaG + b * kLumaB;
    float mx = std::max(r, std::max(g, b));
    float mn = std::min(r, std::min(g, b));
    float sat = mx - mn;
    float vib = adj.saturation + adj.vibrance * (1.f - sat);
    float mixK = 1.f + vib;
    r = l2 + (r - l2) * mixK;
    g = l2 + (g - l2) * mixK;
    b = l2 + (b - l2) * mixK;

    r = clamp01(r);
    g = clamp01(g);
    b = clamp01(b);
}

// CPU mirror of the GLSL `applyDetail` (sharpening + NR). center in/out by ref.
inline void applyDetail(float& r, float& g, float& b, const float blur[3],
                        const RawAdjustments& adj) {
    const float lc = r * kLumaR + g * kLumaG + b * kLumaB;
    const float lb = blur[0] * kLumaR + blur[1] * kLumaG + blur[2] * kLumaB;
    const float edge = std::fabs(lc - lb);

    const float thr = adj.sharpen_masking * 0.15f;
    const float mask = glSmoothstep(thr, thr + 0.05f, edge);

    const float detail[3] = {r - blur[0], g - blur[1], b - blur[2]};
    const float dotd = detail[0] * kLumaR + detail[1] * kLumaG + detail[2] * kLumaB;
    const float center[3] = {r, g, b};
    float outc[3];
    for (int k = 0; k < 3; ++k) {
        const float lum_d = dotd;
        const float chroma_d = detail[k] - lum_d;
        const float sharpen = (lum_d + chroma_d * adj.sharpen_detail) * adj.sharpen_amount * mask;
        outc[k] = center[k] + sharpen;
    }

    const float flat = 1.f - glSmoothstep(0.f, adj.nr_lum_detail * 0.15f + 0.01f, edge);
    const float lumNR = adj.nr_luminance * flat;
    const float chromaNR = adj.nr_color;

    const float l2 = outc[0] * kLumaR + outc[1] * kLumaG + outc[2] * kLumaB;
    const float lTarget = l2 + (lb - l2) * lumNR;  // mix(l2, lb, lumNR)
    for (int k = 0; k < 3; ++k) outc[k] += (lTarget - l2);

    const float l3 = outc[0] * kLumaR + outc[1] * kLumaG + outc[2] * kLumaB;
    for (int k = 0; k < 3; ++k) {
        const float ch = outc[k] - l3;
        const float chB = blur[k] - lb;
        const float mch = ch + (chB - ch) * chromaNR;  // mix(ch, chB, chromaNR)
        outc[k] = l3 + mch;
    }

    r = clamp01(outc[0]);
    g = clamp01(outc[1]);
    b = clamp01(outc[2]);
}

}  // namespace

void ApplyAdjustmentsCpu(const ImageBuffer& linear, const DecodeInfo& info,
                         const RawAdjustments& adj, ImageBuffer* out) {
    // ---- Geometry: normalized crop rect (source space) + 90° turns ----
    const float cl = std::clamp(adj.crop_left, 0.f, 1.f);
    const float ct = std::clamp(adj.crop_top, 0.f, 1.f);
    const float cr = std::max(std::clamp(adj.crop_right, 0.f, 1.f), cl + 1e-4f);
    const float cb = std::max(std::clamp(adj.crop_bottom, 0.f, 1.f), ct + 1e-4f);
    const int turns = ((static_cast<int>(std::lround(adj.crop_turns)) % 4) + 4) % 4;

    const int sx0 = static_cast<int>(std::lround(cl * linear.width));
    const int sy0 = static_cast<int>(std::lround(ct * linear.height));
    const int sx1 = std::min(linear.width, static_cast<int>(std::lround(cr * linear.width)));
    const int sy1 = std::min(linear.height, static_cast<int>(std::lround(cb * linear.height)));
    const int cropW = std::max(1, sx1 - sx0);
    const int cropH = std::max(1, sy1 - sy0);
    const bool swap = (turns == 1 || turns == 3);
    const int outW = swap ? cropH : cropW;
    const int outH = swap ? cropW : cropH;
    out->resize(outW, outH);

    // Liquify: precompute the shared min-dimension and the active impulse lists
    // (manual warp[] + face-derived), then fold the accumulated displacement
    // into the output->source map (a backward warp, so no holes). Inactive =>
    // zero cost fast path. Face impulses are built once, outside the pixel loop.
    const float minDim = static_cast<float>(std::min(linear.width, linear.height));
    bool manualWarp = false;
    for (int i = 0; i < RawAdjustments::kMaxWarp; ++i) {
        if (adj.warp[i * 6 + 4] > 0.f) { manualWarp = true; break; }
    }
    std::vector<float> faceWarp;
    buildFaceImpulses(adj, faceWarp);
    const int faceWarpN = static_cast<int>(faceWarp.size()) / 6;
    const bool warpActive = manualWarp || faceWarpN > 0;

    // Output pixel center -> fractional source pixel. Identity for the neutral
    // full-frame crop; quarter turns keep integer coordinates (no resampling
    // blur from the mapping itself).
    auto outToSrc = [&](int x, int y, float& px, float& py) {
        const float p = (x + 0.5f) / outW;
        const float q = (y + 0.5f) / outH;
        float a, b;  // crop-space normalized coords
        switch (turns) {
            case 1: a = q;       b = 1.f - p; break;
            case 2: a = 1.f - p; b = 1.f - q; break;
            case 3: a = 1.f - q; b = p;       break;
            default: a = p;      b = q;
        }
        px = sx0 + a * cropW - 0.5f;
        py = sy0 + b * cropH - 0.5f;
        if (warpActive) {
            const float u = (px + 0.5f) / static_cast<float>(linear.width);
            const float v = (py + 0.5f) / static_cast<float>(linear.height);
            float du = 0.f, dv = 0.f, tu = 0.f, tv = 0.f;
            if (manualWarp) {
                evalWarp(u, v, adj.warp, RawAdjustments::kMaxWarp,
                         linear.width, linear.height, minDim, tu, tv);
                du += tu;
                dv += tv;
            }
            if (faceWarpN > 0) {
                evalWarp(u, v, faceWarp.data(), faceWarpN,
                         linear.width, linear.height, minDim, tu, tv);
                du += tu;
                dv += tv;
            }
            px += du * static_cast<float>(linear.width);
            py += dv * static_cast<float>(linear.height);
        }
    };

    // Full per-pixel color chain (mirrors the GLSL `adjust`).
    auto adjust = [&](float& r, float& g, float& b) {
        tone(r, g, b, info, adj);
        r = ToneCurveEvaluate(adj.curve_red, ToneCurveEvaluate(adj.curve_rgb, r));
        g = ToneCurveEvaluate(adj.curve_green, ToneCurveEvaluate(adj.curve_rgb, g));
        b = ToneCurveEvaluate(adj.curve_blue, ToneCurveEvaluate(adj.curve_rgb, b));
        applyHsl(r, g, b, adj);
        applyGrade(r, g, b, adj);
    };

    const bool detailActive = adj.sharpen_amount > 1e-6f || adj.nr_luminance > 1e-6f ||
                              adj.nr_color > 1e-6f;

    // M3 Lens corrections: radial distortion + lateral chromatic aberration,
    // applied by resampling the source before the color chain. Constants and
    // formula mirror the GLSL `sampleSource` in gl_pipeline.cpp.
    const float aspect = static_cast<float>(linear.width) / static_cast<float>(linear.height);
    const bool lensActive = adj.lens_distortion > 1e-6f || adj.lens_distortion < -1e-6f ||
                            adj.lens_rca > 1e-6f || adj.lens_defringe_red > 1e-6f ||
                            adj.lens_defringe_red < -1e-6f || adj.lens_defringe_blue > 1e-6f ||
                            adj.lens_defringe_blue < -1e-6f;
    const float kd = adj.lens_distortion * 0.35f;
    const float kr = (adj.lens_rca * 0.5f + adj.lens_defringe_red) * 0.03f;
    const float kb = (-adj.lens_rca * 0.5f + adj.lens_defringe_blue) * 0.03f;

    // Bilinear sample of a single raw channel at fractional pixel (px,py),
    // clamped to the image (mirrors GL_CLAMP_TO_EDGE + GL_LINEAR on the GPU).
    auto sampleChan = [&](float px, float py, int ch) -> float {
        px = std::clamp(px, 0.f, static_cast<float>(linear.width - 1));
        py = std::clamp(py, 0.f, static_cast<float>(linear.height - 1));
        const int x0 = static_cast<int>(std::floor(px));
        const int y0 = static_cast<int>(std::floor(py));
        const float fx = px - x0, fy = py - y0;
        const int x1 = std::min(x0 + 1, linear.width - 1);
        const int y1 = std::min(y0 + 1, linear.height - 1);
        auto at = [&](int xx, int yy) {
            return linear.pixels[(static_cast<size_t>(yy) * linear.width + xx) * 4 + ch];
        };
        const float top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * fx;
        const float bot = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * fx;
        return top + (bot - top) * fy;
    };

    // Sample the (lens-corrected) raw RGB at output pixel (px,py). When lens is
    // inactive this is a plain bilinear tap, matching the GPU fast path.
    auto sampleSource = [&](float px, float py, float o3[3]) {
        if (!lensActive) {
            o3[0] = sampleChan(px, py, 0);
            o3[1] = sampleChan(px, py, 1);
            o3[2] = sampleChan(px, py, 2);
            return;
        }
        const float u = (px + 0.5f) / static_cast<float>(linear.width);
        const float v = (py + 0.5f) / static_cast<float>(linear.height);
        const float qx = (u - 0.5f) * aspect;
        const float qy = (v - 0.5f);
        const float r2 = qx * qx + qy * qy;
        const float sR = 1.f + (kd + kr) * r2;
        const float sG = 1.f + kd * r2;
        const float sB = 1.f + (kd + kb) * r2;
        auto warpPx = [&](float s, float& ox, float& oy) {
            const float uu = (qx * s) / aspect + 0.5f;
            const float vv = qy * s + 0.5f;
            ox = uu * static_cast<float>(linear.width) - 0.5f;
            oy = vv * static_cast<float>(linear.height) - 0.5f;
        };
        float wx, wy;
        warpPx(sR, wx, wy); o3[0] = sampleChan(wx, wy, 0);
        warpPx(sG, wx, wy); o3[1] = sampleChan(wx, wy, 1);
        warpPx(sB, wx, wy); o3[2] = sampleChan(wx, wy, 2);
    };

    // ---- 祛瑕: per-spot ring-median replacement in raw space (pre-color) ----
    bool spotActive = false;
    for (int i = 0; i < RawAdjustments::kMaxSpots; ++i) {
        if (adj.spots[i * 3 + 2] > 0.f) { spotActive = true; break; }
    }

    auto spotReplaceRaw = [&](float px, float py, float o3[3]) -> bool {
        if (!spotActive) return false;
        for (int i = 0; i < RawAdjustments::kMaxSpots; ++i) {
            const float sr = adj.spots[i * 3 + 2];
            if (sr <= 0.f) continue;
            const float ccx = adj.spots[i * 3 + 0] * linear.width;
            const float ccy = adj.spots[i * 3 + 1] * linear.height;
            const float rr = std::max(1.f, sr * minDim);
            const float dx = px - ccx, dy = py - ccy;
            if (dx * dx + dy * dy > rr * rr) continue;
            // Per-channel median of a 12-tap ring just outside the spot edge:
            // robust against the blemish itself leaking into the fill.
            constexpr int kTaps = 12;
            float vals[kTaps][3];
            for (int k = 0; k < kTaps; ++k) {
                const float ang = static_cast<float>(k) * (6.28318530718f / kTaps);
                sampleSource(ccx + std::cos(ang) * rr * 1.15f,
                             ccy + std::sin(ang) * rr * 1.15f, vals[k]);
            }
            for (int c = 0; c < 3; ++c) {
                float col[kTaps];
                for (int k = 0; k < kTaps; ++k) col[k] = vals[k][c];
                std::sort(col, col + kTaps);
                o3[c] = 0.5f * (col[kTaps / 2 - 1] + col[kTaps / 2]);
            }
            return true;
        }
        return false;
    };

    // ---- Pass A: geometry map + raw sample + retouch + color chain ----
    ImageBuffer temp(outW, outH);
    for (int y = 0; y < outH; ++y) {
        for (int x = 0; x < outW; ++x) {
            float px, py;
            outToSrc(x, y, px, py);
            float s[3];
            if (!spotReplaceRaw(px, py, s)) sampleSource(px, py, s);
            float r = s[0], g = s[1], b = s[2];
            adjust(r, g, b);
            float* o = temp.at(x, y);
            o[0] = r;
            o[1] = g;
            o[2] = b;
            o[3] = sampleChan(px, py, 3);
        }
    }

    // ---- Pass B: beauty (edge-preserving smoothing + whitening lift) ----
    if (adj.beauty_smooth > 1e-6f) {
        // Two round-trips of a separable box blur (H,V,H,V) approximate a
        // Gaussian; O(n) per pass keeps full-res export tractable.
        const int R = std::max(
            2, static_cast<int>(std::lround(2.f + adj.beauty_radius * 10.f)));
        ImageBuffer a1(temp.width, temp.height), a2(temp.width, temp.height);
        auto boxH = [&](const ImageBuffer& src, ImageBuffer* dst) {
            const float inv = 1.f / (2.f * R + 1.f);
            for (int y = 0; y < src.height; ++y) {
                for (int c = 0; c < 3; ++c) {
                    float sum = 0.f;
                    for (int k = -R; k <= R; ++k)
                        sum += src.at(std::clamp(k, 0, src.width - 1), y)[c];
                    for (int x = 0; x < src.width; ++x) {
                        dst->at(x, y)[c] = sum * inv;
                        sum += src.at(std::min(x + R + 1, src.width - 1), y)[c] -
                               src.at(std::max(x - R, 0), y)[c];
                    }
                }
            }
        };
        auto boxV = [&](const ImageBuffer& src, ImageBuffer* dst) {
            const float inv = 1.f / (2.f * R + 1.f);
            for (int x = 0; x < src.width; ++x) {
                for (int c = 0; c < 3; ++c) {
                    float sum = 0.f;
                    for (int k = -R; k <= R; ++k)
                        sum += src.at(x, std::clamp(k, 0, src.height - 1))[c];
                    for (int y = 0; y < src.height; ++y) {
                        dst->at(x, y)[c] = sum * inv;
                        sum += src.at(x, std::min(y + R + 1, src.height - 1))[c] -
                               src.at(x, std::max(y - R, 0))[c];
                    }
                }
            }
        };
        boxH(temp, &a1); boxV(a1, &a2);
        boxH(a2, &a1);   boxV(a1, &a2);
        // Flat (low edge energy) pixels get pulled toward the blur so skin
        // smooths while eyes / lips / hairlines stay sharp. The wider the
        // kernel (beauty_radius) the lower the edge threshold.
        const float thr = 0.03f + 0.05f * (1.f - adj.beauty_radius);
        for (int y = 0; y < temp.height; ++y) {
            for (int x = 0; x < temp.width; ++x) {
                float* p = temp.at(x, y);
                const float* bp = a2.at(x, y);
                const float lc = p[0] * kLumaR + p[1] * kLumaG + p[2] * kLumaB;
                const float lb = bp[0] * kLumaR + bp[1] * kLumaG + bp[2] * kLumaB;
                const float flat = 1.f - glSmoothstep(0.f, thr, std::fabs(lc - lb));
                const float amt = adj.beauty_smooth * flat;
                for (int c = 0; c < 3; ++c) p[c] += (bp[c] - p[c]) * amt;
            }
        }
    }
    if (adj.beauty_whitening > 1e-6f) {
        // Midtone gamma lift via a 1025-entry LUT (pow per channel per pixel
        // would dominate full-res time). When beauty_white_skin > 0 the lift is
        // attenuated per pixel by a skin-likelihood weight, so skin brightens
        // while backgrounds / hair stay put. skin = 0 keeps the legacy global
        // lift (m == 1 everywhere).
        const float gamma = 1.f / (1.f + 0.45f * adj.beauty_whitening);
        float lut[1025];
        for (int i = 0; i <= 1024; ++i) lut[i] = std::pow(i / 1024.f, gamma);
        const size_t n = temp.pixelCount();
        const float skin = clamp01(adj.beauty_white_skin);
        for (size_t i = 0; i < n; ++i) {
            float* p = &temp.pixels[i * 4];
            float m = 1.f;
            if (skin > 0.f) {
                const float w = skinWeight(clamp01(p[0]), clamp01(p[1]), clamp01(p[2]));
                m = 1.f + (w - 1.f) * skin;  // lerp(1, w, skin)
            }
            for (int c = 0; c < 3; ++c) {
                const float v = std::clamp(p[c], 0.f, 1.f);
                const float lifted = lut[std::min(1024, static_cast<int>(v * 1024.f + 0.5f))];
                p[c] = v + (lifted - v) * m;
            }
        }
    }

    // No detail stage: the graded temp *is* the result.
    if (!detailActive) {
        out->pixels = std::move(temp.pixels);
        return;
    }

    // ---- Pass C: detail (sharpen / NR) from the temp buffer ----
    // Bilinear tap of the already-graded image in *output* space (isotropic
    // under quarter turns). Note this is bilinear(adjust(src)) rather than the
    // previous adjust(bilinear(src)); preview and export share this one code
    // path so they stay numerically identical.
    auto sampleTemp = [&](float px, float py, float o3[3]) {
        px = std::clamp(px, 0.f, static_cast<float>(temp.width - 1));
        py = std::clamp(py, 0.f, static_cast<float>(temp.height - 1));
        const int x0 = static_cast<int>(std::floor(px));
        const int y0 = static_cast<int>(std::floor(py));
        const float fx = px - x0, fy = py - y0;
        const int x1 = std::min(x0 + 1, temp.width - 1);
        const int y1 = std::min(y0 + 1, temp.height - 1);
        for (int c = 0; c < 3; ++c) {
            const float top = temp.at(x0, y0)[c] + (temp.at(x1, y0)[c] - temp.at(x0, y0)[c]) * fx;
            const float bot = temp.at(x0, y1)[c] + (temp.at(x1, y1)[c] - temp.at(x0, y1)[c]) * fx;
            o3[c] = top + (bot - top) * fy;
        }
    };

    // 3x3 Gaussian (1,2,1 / 2,4,2 / 1,2,1) at `radius` pixel spacing.
    auto gaussian = [&](float cx, float cy, float o3[3]) {
        const float off = std::max(adj.sharpen_radius, 1.f);
        const float w[3] = {1.f, 2.f, 1.f};
        const float d[3] = {-off, 0.f, off};
        float acc[3] = {0.f, 0.f, 0.f};
        for (int jy = 0; jy < 3; ++jy) {
            for (int jx = 0; jx < 3; ++jx) {
                float s[3];
                sampleTemp(cx + d[jx], cy + d[jy], s);
                const float ww = w[jx] * w[jy];
                acc[0] += s[0] * ww;
                acc[1] += s[1] * ww;
                acc[2] += s[2] * ww;
            }
        }
        o3[0] = acc[0] / 16.f;
        o3[1] = acc[1] / 16.f;
        o3[2] = acc[2] / 16.f;
    };

    for (int y = 0; y < outH; ++y) {
        for (int x = 0; x < outW; ++x) {
            float* p = temp.at(x, y);
            float r = p[0], g = p[1], b = p[2];
            float blur[3];
            gaussian(static_cast<float>(x), static_cast<float>(y), blur);
            applyDetail(r, g, b, blur, adj);
            float* o = out->at(x, y);
            o[0] = r;
            o[1] = g;
            o[2] = b;
            o[3] = p[3];
        }
    }
}

}  // namespace mupic
