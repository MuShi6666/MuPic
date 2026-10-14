#include "core/raw_decoder.h"

#include <sys/stat.h>

#include <cctype>
#include <string>

#ifdef MUPIC_HAVE_LIBRAW
#include <libraw/libraw.h>
#endif

namespace mupic {

namespace {

bool endsWithIgnoreCase(const std::string& s, const std::string& suffix) {
    if (s.size() < suffix.size()) return false;
    auto lower = [](char c) { return static_cast<char>(std::tolower(c)); };
    auto it1 = s.end() - static_cast<long>(suffix.size());
    auto it2 = suffix.begin();
    for (; it2 != suffix.end(); ++it1, ++it2) {
        if (lower(*it1) != lower(*it2)) return false;
    }
    return true;
}

bool isRawExtension(const std::string& path) {
    static const char* kRawExts[] = {".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf",
                                     ".rw2", ".dng", ".pef", ".srw", ".raw"};
    for (const char* ext : kRawExts) {
        if (endsWithIgnoreCase(path, ext)) return true;
    }
    return false;
}

bool fileExists(const std::string& path) {
    struct stat st {};
    return stat(path.c_str(), &st) == 0;
}

#ifdef MUPIC_HAVE_LIBRAW
bool decodeWithLibRaw(const std::string& path, ImageBuffer* out, DecodeInfo* info) {
    LibRaw raw;
    if (raw.open_file(path.c_str()) != LIBRAW_SUCCESS) return false;
    if (raw.unpack() != LIBRAW_SUCCESS) return false;

    const auto& ip = raw.imgdata;
    info->width = ip.sizes.width;
    info->height = ip.sizes.height;
    info->is_raw = true;
    info->wb_multiplier[0] = ip.colour.cam_mul[0];
    info->wb_multiplier[1] = ip.colour.cam_mul[1];
    info->wb_multiplier[2] = ip.colour.cam_mul[2];
    info->make = ip.ipdt.make ? ip.ipdt.make : "";
    info->model = ip.ipdt.model ? ip.ipdt.model : "";

    raw.dcraw_init();
    raw.dcraw_interpolate();
    out->resize(info->width, info->height);
    // Detailed 16-bit -> float conversion implemented in M1+.
    return !out->empty();
}
#endif

// Placeholder used until LibRaw is dropped into third_party: validates the file
// exists and emits a small solid buffer so the render path still runs.
bool decodePlaceholder(const std::string& path, ImageBuffer* out, DecodeInfo* info) {
    if (!fileExists(path)) return false;
    info->is_raw = isRawExtension(path);
    info->width = 64;
    info->height = 64;
    out->resize(64, 64);
    out->fill(1.f, 0.f, 1.f, 1.f);  // magenta = "placeholder decoded"
    return true;
}

}  // namespace

bool DecodeImage(const std::string& path, ImageBuffer* out, DecodeInfo* info) {
    if (out == nullptr || info == nullptr) return false;
    out->width = out->height = 0;
    out->pixels.clear();
    *info = DecodeInfo{};

#ifdef MUPIC_HAVE_LIBRAW
    if (isRawExtension(path) && decodeWithLibRaw(path, out, info)) {
        return true;
    }
#endif
    return decodePlaceholder(path, out, info);
}

bool DecodeRgba8(int width, int height, const uint8_t* rgba, ImageBuffer* out,
                 DecodeInfo* info) {
    if (out == nullptr || info == nullptr || rgba == nullptr) return false;
    if (width <= 0 || height <= 0) return false;

    out->resize(width, height);
    *info = DecodeInfo{};
    info->width = width;
    info->height = height;
    info->is_raw = false;

    // Android Bitmap ARGB_8888 is stored in memory as R,G,B,A per pixel.
    const size_t n = static_cast<size_t>(width) * height;
    for (size_t i = 0; i < n; ++i) {
        out->pixels[i * 4 + 0] = rgba[i * 4 + 0] / 255.f;
        out->pixels[i * 4 + 1] = rgba[i * 4 + 1] / 255.f;
        out->pixels[i * 4 + 2] = rgba[i * 4 + 2] / 255.f;
        out->pixels[i * 4 + 3] = rgba[i * 4 + 3] / 255.f;
    }
    return true;
}

}  // namespace mupic
