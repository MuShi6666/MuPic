#ifndef MUPIC_CORE_PREVIEW_CPU_H_
#define MUPIC_CORE_PREVIEW_CPU_H_

#include <cstdint>
#include <vector>

#include "core/adjustments.h"
#include "core/image_buffer.h"
#include "core/raw_decoder.h"

namespace mupic {

// CPU preview renderer: the reliable, device-independent preview path.
//
// It downscales `linear` so the longest edge fits `maxDim`, runs the same
// `ApplyAdjustmentsCpu` stack used by export, then clamps + encodes the result
// to 8-bit RGBA. Because it shares the CPU color pipeline, the preview matches
// the exported pixels. Returns false on failure.
bool RenderPreviewCpu(const ImageBuffer& linear, const DecodeInfo& info,
                      const RawAdjustments& adj, int maxDim,
                      std::vector<uint8_t>* outRGBA, int* outW, int* outH);

}  // namespace mupic

#endif  // MUPIC_CORE_PREVIEW_CPU_H_
