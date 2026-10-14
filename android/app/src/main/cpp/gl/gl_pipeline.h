#ifndef MUPIC_GL_GL_PIPELINE_H_
#define MUPIC_GL_GL_PIPELINE_H_

#include <android/native_window.h>
#include <EGL/egl.h>
#include <GLES3/gl31.h>

#include <string>

#include "core/adjustments.h"
#include "core/image_buffer.h"
#include "core/raw_decoder.h"
#include "gl/gl_context.h"

namespace mupic {

// GPU preview pipeline.
//
// Uploads the decoded image to an RGBA8 texture, runs the Camera Raw "Basic"
// adjustment as an OpenGL ES 3.1 fragment pass, and draws to the SurfaceTexture
// window Flutter consumes as a Texture. The GLSL `tone()` math is mirrored
// 1:1 by ApplyAdjustmentsCpu() so preview and export agree (plan: parity test).
class GLPipeline {
public:
    GLPipeline() = default;
    ~GLPipeline();

    GLPipeline(const GLPipeline&) = delete;
    GLPipeline& operator=(const GLPipeline&) = delete;

    // Set the decoded source; marks the texture for re-upload on next Render.
    void SetSource(const ImageBuffer& linear, const DecodeInfo& info);

    // Render one preview frame into `window` (SurfaceTexture-backed).
    // [quality]: 0 = coarse interactive, 1 = refine. Returns false on GL failure.
    bool Render(ANativeWindow* window, const RawAdjustments& adj, int quality);

private:
    bool InitGl();
    void ReleaseGl();
    bool UploadSourceIfNeeded();
    void ApplyUniforms(const RawAdjustments& adj) const;

    GLContext context_;
    ImageBuffer source_;
    DecodeInfo info_;

    bool gl_ready_ = false;
    bool source_dirty_ = false;

    // Cached window surface (recreated only when the window pointer changes).
    ANativeWindow* window_ = nullptr;
    EGLSurface surface_ = EGL_NO_SURFACE;

    GLuint program_ = 0;
    GLuint vao_ = 0;
    GLuint quad_vbo_ = 0;
    GLuint texture_ = 0;
    int tex_w_ = 0;
    int tex_h_ = 0;

    // Uniform locations (resolved in InitGl).
    struct Uniforms {
        GLint src = -1;
        GLint wb = -1;
        GLint temp = -1, tint = -1, exposure = -1, contrast = -1;
        GLint highlights = -1, shadows = -1, whites = -1, blacks = -1;
        GLint vibrance = -1, saturation = -1;
        // M2: tone curve (four region controls per channel) + HSL + grading.
        GLint curveRgb = -1, curveRed = -1, curveGreen = -1, curveBlue = -1;
        GLint hsl = -1;    // vec3[8]  (x=hue, y=sat, z=lum), index 7 = global
        GLint grade = -1;  // vec3[3]  (x=hue, y=sat, z=lum); 0=sh 1=mid 2=high
        GLint gradeBlend = -1, gradeMid = -1;
        // M3: Detail (sharpening + noise reduction) + texel size for taps.
        GLint texel = -1;
        GLint sharpAmount = -1, sharpRadius = -1, sharpDetail = -1, sharpMasking = -1;
        GLint nrLum = -1, nrLumDetail = -1, nrColor = -1;
        GLint detailActive = -1;  // 1.0 when any detail op is non-neutral
        // M3: Lens corrections (geometric resample) + aspect ratio for radial warp.
        GLint aspect = -1;
        GLint lensRca = -1, lensDefringeR = -1, lensDefringeB = -1, lensDistortion = -1;
        GLint lensActive = -1;  // 1.0 when any lens op is non-neutral
    } u_;
};

}  // namespace mupic

#endif  // MUPIC_GL_GL_PIPELINE_H_
