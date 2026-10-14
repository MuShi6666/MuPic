#ifndef MUPIC_GL_LUT_BUILDER_H_
#define MUPIC_GL_LUT_BUILDER_H_

#include <vector>

#include "core/adjustments.h"

namespace mupic {

// Bakes adjustment stages into lookup tables shared by the CPU and GPU paths so
// their results are numerically identical:
//   - tone curve  -> 1D LUT (one per RGB channel)
//   - HSL + color grading -> applied analytically (see color_pipeline / shaders)
//
// ToneCurveEvaluate() is the single parametric-curve definition; it is ported
// verbatim into the GLSL preview shader so CPU export and GPU preview match.
struct CurveLut {
    int size = 256;
    std::vector<float> r;  // size floats in [0..1]
    std::vector<float> g;
    std::vector<float> b;
};

// Parametric tone-curve evaluation shared by CPU + GPU.
//
// ctrl holds four region controls (normalized -1..1):
//   ctrl[0] shadows   (lifts/darkens the toe)
//   ctrl[1] midtones1 (lower-mid pivot)
//   ctrl[2] midtones2 (upper-mid pivot)
//   ctrl[3] highlights(pulls/pushs the shoulder)
// ctrl[4] is reserved. Identity when all controls are 0.
float ToneCurveEvaluate(const float ctrl[5], float x);

CurveLut BuildToneCurveLut(const RawAdjustments& adj, int size = 256);

}  // namespace mupic

#endif  // MUPIC_GL_LUT_BUILDER_H_
