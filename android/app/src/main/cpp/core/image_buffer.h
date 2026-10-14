#ifndef MUPIC_CORE_IMAGE_BUFFER_H_
#define MUPIC_CORE_IMAGE_BUFFER_H_

#include <cstddef>
#include <cstdint>
#include <vector>

namespace mupic {

// Unified linear image container: float32 RGBA, tightly packed.
//
// Both the decoder output and the CPU pipeline operate on this type so the
// same pixel format flows from LibRaw -> color pipeline -> export, and can be
// uploaded directly to an RGBA32F texture for GPU preview.
struct ImageBuffer {
    int width = 0;
    int height = 0;
    // 4 channels (RGBA) in linear [0..1] float32.
    std::vector<float> pixels;

    ImageBuffer() = default;
    ImageBuffer(int w, int h) : width(w), height(h), pixels(static_cast<size_t>(w) * h * 4, 0.f) {}

    bool empty() const { return width == 0 || height == 0 || pixels.empty(); }
    size_t pixelCount() const { return static_cast<size_t>(width) * height; }

    float* at(int x, int y) { return &pixels[(static_cast<size_t>(y) * width + x) * 4]; }
    const float* at(int x, int y) const { return &pixels[(static_cast<size_t>(y) * width + x) * 4]; }

    void resize(int w, int h) {
        width = w;
        height = h;
        pixels.assign(static_cast<size_t>(w) * h * 4, 0.f);
    }

    // Fill every pixel with a solid RGBA color (used by the M0 placeholder).
    void fill(float r, float g, float b, float a = 1.f);
};

}  // namespace mupic

#endif  // MUPIC_CORE_IMAGE_BUFFER_H_
