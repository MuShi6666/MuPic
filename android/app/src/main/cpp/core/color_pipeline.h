#ifndef MUPIC_CORE_COLOR_PIPELINE_H_
#define MUPIC_CORE_COLOR_PIPELINE_H_

#include "core/adjustments.h"
#include "core/image_buffer.h"
#include "core/raw_decoder.h"

namespace mupic {

// CPU reference implementation of the full adjustment stack (white balance ->
// base color -> basic tone -> curve/HSL/grading via LUTs -> detail -> effects).
//
// It mirrors, stage for stage, the GPU preview pipeline so exported pixels match
// the preview. M1+ fills in each stage; M0 applies the basic tone adjustments so
// the path is real and measurable.
void ApplyAdjustmentsCpu(const ImageBuffer& linear, const DecodeInfo& info,
                         const RawAdjustments& adj, ImageBuffer* out);

}  // namespace mupic

#endif  // MUPIC_CORE_COLOR_PIPELINE_H_
