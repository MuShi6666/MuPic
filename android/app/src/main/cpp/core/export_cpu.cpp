#include "core/export_cpu.h"

#include <algorithm>
#include <cmath>

#include "core/color_pipeline.h"

namespace mupic {
namespace {

inline uint8_t ToU8(float v) {
    const float c = std::clamp(v, 0.f, 1.f) * 255.f;
    return static_cast<uint8_t>(std::lround(c));
}

}  // namespace

bool RenderExportCpu(const ImageBuffer& linear, const DecodeInfo& info,
                     const RawAdjustments& adj,
                     std::vector<uint8_t>* outRGBA, int* outW, int* outH) {
    if (linear.empty() || outRGBA == nullptr || outW == nullptr || outH == nullptr)
        return false;

    // Full-resolution CPU render; the same ApplyAdjustmentsCpu used by the
    // preview guarantees export == preview.
    ImageBuffer result;
    ApplyAdjustmentsCpu(linear, info, adj, &result);
    if (result.empty()) return false;

    const size_t n = result.pixelCount();
    outRGBA->resize(n * 4);
    for (size_t i = 0; i < n; ++i) {
        const float* p = &result.pixels[i * 4];
        uint8_t* o = &(*outRGBA)[i * 4];
        o[0] = ToU8(p[0]);
        o[1] = ToU8(p[1]);
        o[2] = ToU8(p[2]);
        o[3] = ToU8(p[3]);
    }
    *outW = result.width;
    *outH = result.height;
    return true;
}

}  // namespace mupic
