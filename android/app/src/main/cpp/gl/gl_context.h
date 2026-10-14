#ifndef MUPIC_GL_GL_CONTEXT_H_
#define MUPIC_GL_GL_CONTEXT_H_

#include <EGL/egl.h>
#include <GLES3/gl31.h>

namespace mupic {

// Owns an EGL display/context usable for offscreen (PBuffer) or window
// (SurfaceTexture / ANativeWindow) rendering on a dedicated GL thread.
//
// M0 declares the lifecycle; the GL preview pipeline is implemented in M1.
class GLContext {
public:
    GLContext() = default;
    ~GLContext();

    GLContext(const GLContext&) = delete;
    GLContext& operator=(const GLContext&) = delete;

    bool InitDisplay();
    void Destroy();

    bool valid() const { return context_ != EGL_NO_CONTEXT; }
    EGLContext egl_context() const { return context_; }
    EGLDisplay egl_display() const { return display_; }
    EGLConfig egl_config() const { return config_; }

    // Bind this context to an ANativeWindow, producing a drawable surface.
    // Returns the created EGLSurface (caller releases with ReleaseWindow).
    EGLSurface AcquireWindow(void* native_window);
    bool MakeCurrent(EGLSurface surface);
    void ReleaseCurrent();
    void ReleaseWindow(EGLSurface surface);

  private:
    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLConfig config_ = nullptr;
    EGLContext context_ = EGL_NO_CONTEXT;
};

}  // namespace mupic

#endif  // MUPIC_GL_GL_CONTEXT_H_
