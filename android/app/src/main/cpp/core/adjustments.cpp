#include "core/adjustments.h"

#include <cmath>

namespace mupic {

bool RawAdjustments::isNeutral() const {
    // Cheap "no edits" check used to skip the whole adjustment stage.
    auto nearZero = [](float v) { return std::fabs(v) < 1e-6f; };
    if (!nearZero(color_temp) || !nearZero(tint) || !nearZero(exposure) ||
        !nearZero(contrast) || !nearZero(highlights) || !nearZero(shadows) ||
        !nearZero(whites) || !nearZero(blacks) || !nearZero(texture) ||
        !nearZero(clarity) || !nearZero(dehaze) || !nearZero(vibrance) ||
        !nearZero(saturation)) {
        return false;
    }
    for (int i = 0; i < 5; ++i) {
        if (!nearZero(curve_rgb[i]) || !nearZero(curve_red[i]) ||
            !nearZero(curve_green[i]) || !nearZero(curve_blue[i])) {
            return false;
        }
    }
    for (int i = 0; i < kHslRanges; ++i) {
        if (!nearZero(hsl_hue[i]) || !nearZero(hsl_sat[i]) || !nearZero(hsl_lum[i])) {
            return false;
        }
    }
    return nearZero(rotation_deg) && nearZero(vertical_skew) &&
           nearZero(horizontal_skew) && nearZero(lens_rca) &&
           nearZero(lens_defringe_red) && nearZero(lens_defringe_blue) &&
           nearZero(lens_distortion) &&
           // Crop: neutral is the full frame, no turns.
           nearZero(crop_left) && nearZero(crop_top) &&
           std::fabs(crop_right - 1.f) < 1e-6f &&
           std::fabs(crop_bottom - 1.f) < 1e-6f && nearZero(crop_turns) &&
           // Beauty: no smoothing / whitening / spots.
           nearZero(beauty_smooth) && nearZero(beauty_whitening) &&
           [this] {
               for (int i = 0; i < kMaxSpots; ++i) {
                   if (spots[i * 3 + 2] > 0.f) return false;
               }
               return true;
           }() &&
           // Liquify: no active deformation impulses (radius > 0).
           [this] {
               for (int i = 0; i < kMaxWarp; ++i) {
                   if (warp[i * 6 + 4] > 0.f) return false;
               }
               return true;
           }() &&
           // Face liquify: the four auto sliders at rest. face_pts / face_count
           // are recomputable detection metadata and deliberately ignored here.
           nearZero(face_slim) && nearZero(face_eye) &&
           nearZero(face_nose) && nearZero(face_chin);
}

const RawAdjustments& RawAdjustments::identity() {
    static const RawAdjustments kIdentity{};
    return kIdentity;
}

}  // namespace mupic
