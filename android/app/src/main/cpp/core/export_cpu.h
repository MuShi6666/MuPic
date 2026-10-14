#ifndef MUPIC_CORE_EXPORT_CPU_H_
#define MUPIC_CORE_EXPORT_CPU_H_

#include <cstdint>
#include <string>
#include <vector>

#include "core/adjustments.h"
#include "core/image_buffer.h"
#include "core/raw_decoder.h"

namespace mupic {

// Runs the CPU reference pipeline at full resolution and returns the result as
// packed RGBA8 bytes (outRGBA = outW*outH*4, alpha last). This mirrors, stage
// for stage, the preview so exported pixels match what the user saw.
//
// Actual file encoding (JPEG / PNG) is delegated to the platform layer, which
// reuses Android's battle-tested Bitmap compressors instead of bundling a codec.
bool RenderExportCpu(const ImageBuffer& linear, const DecodeInfo& info,
                     const RawAdjustments& adj,
                     std::vector<uint8_t>* outRGBA, int* outW, int* outH);

}  // namespace mupic

#endif  // MUPIC_CORE_EXPORT_CPU_H_
