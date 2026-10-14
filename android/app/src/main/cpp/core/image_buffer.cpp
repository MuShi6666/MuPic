#include "core/image_buffer.h"

namespace mupic {

void ImageBuffer::fill(float r, float g, float b, float a) {
    for (size_t i = 0; i < pixels.size(); i += 4) {
        pixels[i + 0] = r;
        pixels[i + 1] = g;
        pixels[i + 2] = b;
        pixels[i + 3] = a;
    }
}

}  // namespace mupic
