#include "core/preview_cpu.h"

#include <algorithm>
#include <cmath>

#include "core/color_pipeline.h"

namespace mupic {
namespace {

// Bilinear downscale of a packed float RGBA image to (dstW, dstH).
ImageBuffer DownscaleBilinear(const ImageBuffer& src, int dstW, int dstH) {
    ImageBuffer dst(dstW, dstH);
    if (src.empty() || dstW <= 0 || dstH <= 0) return dst;
    const float sx = static_cast<float>(src.width) / static_cast<float>(dstW);
    const float sy = static_cast<float>(src.height) / static_cast<float>(dstH);
    for (int y = 0; y < dstH; ++y) {
        float fy = (y + 0.5f) * sy - 0.5f;
        int y0 = static_cast<int>(std::floor(fy));
        float wy = fy - static_cast<float>(y0);
        if (y0 < 0) { y0 = 0; wy = 0.f; }
        const int y1 = std::min(y0 + 1, src.height - 1);
        y0 = std::min(y0, src.height - 1);
        for (int x = 0; x < dstW; ++x) {
            float fx = (x + 0.5f) * sx - 0.5f;
            int x0 = static_cast<int>(std::floor(fx));
            float wx = fx - static_cast<float>(x0);
            if (x0 < 0) { x0 = 0; wx = 0.f; }
            const int x1 = std::min(x0 + 1, src.width - 1);
            x0 = std::min(x0, src.width - 1);
            const float* p00 = src.at(x0, y0);
            const float* p10 = src.at(x1, y0);
            const float* p01 = src.at(x0, y1);
            const float* p11 = src.at(x1, y1);
            float* o = dst.at(x, y);
            for (int c = 0; c < 4; ++c) {
                const float top = p00[c] + (p10[c] - p00[c]) * wx;
                const float bot = p01[c] + (p11[c] - p01[c]) * wx;
                o[c] = top + (bot - top) * wy;
            }
        }
    }
    return dst;
}

inline uint8_t ToU8(float v) {
    const float c = std::clamp(v, 0.f, 1.f) * 255.f;
    return static_cast<uint8_t>(std::lround(c));
}

}  // namespace

bool RenderPreviewCpu(const ImageBuffer& linear, const DecodeInfo& info,
                      const RawAdjustments& adj, int maxDim,
                      std::vector<uint8_t>* outRGBA, int* outW, int* outH) {
    if (linear.empty() || outRGBA == nullptr || outW == nullptr || outH == nullptr)
        return false;
    if (maxDim < 16) maxDim = 16;

    const int longest = std::max(linear.width, linear.height);
    const float scale = longest > maxDim
                            ? static_cast<float>(maxDim) / static_cast<float>(longest)
                            : 1.f;
    const int pw = std::max(1, static_cast<int>(std::lround(linear.width * scale)));
    const int ph = std::max(1, static_cast<int>(std::lround(linear.height * scale)));

    const ImageBuffer small = DownscaleBilinear(linear, pw, ph);
    DecodeInfo smallInfo = info;
    smallInfo.width = pw;
    smallInfo.height = ph;

    ImageBuffer result;
    ApplyAdjustmentsCpu(small, smallInfo, adj, &result);
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
