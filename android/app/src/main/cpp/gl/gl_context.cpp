#include "gl/gl_context.h"

#include <android/log.h>

#define TAG "MuPicGL"

namespace mupic {

GLContext::~GLContext() { Destroy(); }

bool GLContext::InitDisplay() {
    display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display_ == EGL_NO_DISPLAY) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "no EGL display");
        return false;
    }

    EGLint major = 0, minor = 0;
    if (eglInitialize(display_, &major, &minor) != EGL_TRUE) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "eglInitialize failed");
        return false;
    }

    const EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
        EGL_NONE
    };
    EGLint num_configs = 0;
    if (eglChooseConfig(display_, attribs, &config_, 1, &num_configs) != EGL_TRUE ||
        num_configs < 1) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "eglChooseConfig failed");
        return false;
    }

    const EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, ctx_attribs);
    if (context_ == EGL_NO_CONTEXT) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "eglCreateContext failed");
        return false;
    }
    return true;
}

void GLContext::Destroy() {
    if (display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (context_ != EGL_NO_CONTEXT) eglDestroyContext(display_, context_);
        eglTerminate(display_);
    }
    display_ = EGL_NO_DISPLAY;
    config_ = nullptr;
    context_ = EGL_NO_CONTEXT;
}

EGLSurface GLContext::AcquireWindow(void* native_window) {
    if (display_ == EGL_NO_DISPLAY || native_window == nullptr) return EGL_NO_SURFACE;
    const EGLint attribs[] = {EGL_NONE};
    EGLSurface surface =
        eglCreateWindowSurface(display_, config_,
                               reinterpret_cast<EGLNativeWindowType>(native_window), attribs);
    if (surface == EGL_NO_SURFACE) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "eglCreateWindowSurface failed: 0x%x", eglGetError());
    }
    return surface;
}

bool GLContext::MakeCurrent(EGLSurface surface) {
    if (display_ == EGL_NO_DISPLAY || surface == EGL_NO_SURFACE) return false;
    if (eglMakeCurrent(display_, surface, surface, context_) != EGL_TRUE) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "eglMakeCurrent failed: 0x%x", eglGetError());
        return false;
    }
    return true;
}

void GLContext::ReleaseCurrent() {
    if (display_ == EGL_NO_DISPLAY) return;
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
}

void GLContext::ReleaseWindow(EGLSurface surface) {
    if (display_ == EGL_NO_DISPLAY || surface == EGL_NO_SURFACE) return;
    eglDestroySurface(display_, surface);
}

}  // namespace mupic
