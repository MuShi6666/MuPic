#include "gl/lut_builder.h"

#include <algorithm>
#include <cmath>

namespace mupic {

namespace {
inline float clamp01(float v) { return v < 0.f ? 0.f : (v > 1.f ? 1.f : v); }
}  // namespace

float ToneCurveEvaluate(const float ctrl[5], float x) {
    // NOTE: mirrored verbatim in the GLSL preview shader (`toneCurve`). Keep in sync.
    x = clamp01(x);
    const float shadow = ctrl[0];
    const float mid1 = ctrl[1];
    const float mid2 = ctrl[2];
    const float highlight = ctrl[3];
    float y = x;
    // Lift/gamma style blend of the four control regions.
    y += shadow * (1.f - y) * 0.5f;
    y -= highlight * y * 0.5f;
    // Midtone slope pivoted around 0.5 between the two mid controls.
    const float slope = 1.f + (mid2 - mid1);
    y = clamp01((y - 0.5f) * slope + 0.5f);
    return clamp01(y);
}

CurveLut BuildToneCurveLut(const RawAdjustments& adj, int size) {
    CurveLut lut;
    lut.size = size;
    lut.r.resize(size);
    lut.g.resize(size);
    lut.b.resize(size);
    for (int i = 0; i < size; ++i) {
        const float x = static_cast<float>(i) / (size - 1);
        lut.r[i] = ToneCurveEvaluate(adj.curve_red, ToneCurveEvaluate(adj.curve_rgb, x));
        lut.g[i] = ToneCurveEvaluate(adj.curve_green, ToneCurveEvaluate(adj.curve_rgb, x));
        lut.b[i] = ToneCurveEvaluate(adj.curve_blue, ToneCurveEvaluate(adj.curve_rgb, x));
    }
    return lut;
}

}  // namespace mupic
