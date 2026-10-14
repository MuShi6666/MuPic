#ifndef MUPIC_CORE_RAW_DECODER_H_
#define MUPIC_CORE_RAW_DECODER_H_

#include <string>

#include "core/image_buffer.h"

namespace mupic {

// Metadata extracted while decoding a source image, needed by later pipeline
// stages (white balance, camera color matrix, orientation).
struct DecodeInfo {
    int width = 0;
    int height = 0;
    bool is_raw = false;
    float wb_multiplier[3] = {1.f, 1.f, 1.f};  // camera as-shot R/G/B gains
    float neutral_kelvin = 6500.f;
    float rotation_deg = 0.f;                   // EXIF orientation
    std::string make;
    std::string model;
};

// Decodes a RAW file at `path` into a linear float RGBA buffer.
//
// M0/M1 status:
//   - RAW : routed to LibRaw when MUPIC_HAVE_LIBRAW is defined (drop sources
//           under cpp/third_party/libraw). Otherwise returns a placeholder.
//   - JPEG/PNG: decoded on the Kotlin side (BitmapFactory) and handed to
//           DecodeRgba8 below, so the native core stays free of an API-31-only
//           NDK image decoder.
bool DecodeImage(const std::string& path, ImageBuffer* out, DecodeInfo* info);

// Builds a float RGBA buffer from a Kotlin-decoded RGBA8 (R,G,B,A) pixel array.
// Used for JPEG/PNG (and any format Android can already rasterize).
bool DecodeRgba8(int width, int height, const uint8_t* rgba,
                 ImageBuffer* out, DecodeInfo* info);

}  // namespace mupic

#endif  // MUPIC_CORE_RAW_DECODER_H_
