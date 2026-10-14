#include <jni.h>

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>

#include "core/adjustments.h"
#include "core/export_cpu.h"
#include "core/image_buffer.h"
#include "core/preview_cpu.h"
#include "core/raw_decoder.h"
#include "gl/gl_pipeline.h"

#define TAG "MuPicJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

namespace {

// One open image: decoded linear buffer + current adjustment state + GL pipeline.
struct Session {
    mupic::ImageBuffer linear;
    mupic::DecodeInfo info;
    mupic::RawAdjustments adj;
    mupic::GLPipeline gl;
    bool source_ready = false;

    // Latest CPU preview frame (RGBA8) + its dimensions, cached so Kotlin can
    // pull them via the nativePreview* getters after a successful render.
    std::vector<uint8_t> preview_rgba;
    int preview_w = 0;
    int preview_h = 0;

    // Latest full-resolution export render (RGBA8) + dims, cached so Kotlin can
    // pull it and hand the bytes to Android's Bitmap encoder (JPEG / PNG).
    std::vector<uint8_t> export_rgba;
    int export_w = 0;
    int export_h = 0;

    void refreshSource() {
        if (source_ready) return;
        gl.SetSource(linear, info);
        source_ready = true;
    }
};

std::mutex g_mutex;
std::unordered_map<int, Session> g_sessions;
int g_next_id = 1;

std::string JStringToUtf8(JNIEnv* env, jstring s) {
    if (s == nullptr) return {};
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out = c ? c : "";
    if (c) env->ReleaseStringUTFChars(s, c);
    return out;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeOpenImage(JNIEnv* env, jobject /*thiz*/,
                                               jstring path) {
    const std::string p = JStringToUtf8(env, path);
    mupic::ImageBuffer buffer;
    mupic::DecodeInfo info;
    if (!mupic::DecodeImage(p, &buffer, &info)) {
        LOGE("failed to decode %s", p.c_str());
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    const int id = g_next_id++;
    Session& s = g_sessions[id];
    s.linear = std::move(buffer);
    s.info = info;
    s.source_ready = false;
    LOGI("opened image id=%d %dx%d raw=%d", id, info.width, info.height, info.is_raw ? 1 : 0);
    return id;
}

JNIEXPORT void JNICALL
Java_com_mupic_app_MuPicEditor_nativeSetParams(JNIEnv* env, jobject, jint imageId,
                                               jbyteArray params) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    if (it == g_sessions.end() || params == nullptr) return;

    // Binary transport contract: the payload is the little-endian float32 image
    // of RawAdjustments produced by the Dart EditState serializer. When the size
    // matches we copy it straight into the shared struct; otherwise the previous
    // state is kept so a version mismatch never corrupts the pipeline.
    const jsize len = env->GetArrayLength(params);
    if (static_cast<size_t>(len) >= sizeof(mupic::RawAdjustments)) {
        jbyte* data = env->GetByteArrayElements(params, nullptr);
        std::memcpy(&it->second.adj, data, sizeof(mupic::RawAdjustments));
        env->ReleaseByteArrayElements(params, data, JNI_ABORT);
    } else {
        LOGE("params size mismatch: got %d, want >= %zu", len,
             sizeof(mupic::RawAdjustments));
    }
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeOpenImageBuffer(JNIEnv* env, jobject /*thiz*/,
                                                     jint width, jint height,
                                                     jbyteArray rgba) {
    if (width <= 0 || height <= 0 || rgba == nullptr) return 0;
    const jsize len = env->GetArrayLength(rgba);
    if (static_cast<size_t>(len) < static_cast<size_t>(width) * height * 4) {
        LOGE("rgba buffer too small: %d", len);
        return 0;
    }
    mupic::ImageBuffer buffer;
    mupic::DecodeInfo info;
    jbyte* data = env->GetByteArrayElements(rgba, nullptr);
    const bool ok = mupic::DecodeRgba8(width, height, reinterpret_cast<uint8_t*>(data),
                                       &buffer, &info);
    env->ReleaseByteArrayElements(rgba, data, JNI_ABORT);
    if (!ok) return 0;

    std::lock_guard<std::mutex> lock(g_mutex);
    const int id = g_next_id++;
    Session& s = g_sessions[id];
    s.linear = std::move(buffer);
    s.info = info;
    s.source_ready = false;
    LOGI("opened raster id=%d %dx%d", id, width, height);
    return id;
}

JNIEXPORT void JNICALL
Java_com_mupic_app_MuPicEditor_nativeRenderPreview(JNIEnv* env, jobject, jint imageId,
                                                   jobject surface, jint quality) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    if (it == g_sessions.end() || surface == nullptr) return;

    Session& s = it->second;
    s.refreshSource();

    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    if (window == nullptr) return;
    const bool gpu = s.gl.Render(window, s.adj, quality);
    ANativeWindow_release(window);
    LOGI("preview render id=%d quality=%d gpu=%d", imageId, quality, gpu ? 1 : 0);
}

JNIEXPORT jboolean JNICALL
Java_com_mupic_app_MuPicEditor_nativeRenderPreviewCpu(JNIEnv* env, jobject, jint imageId,
                                                      jint maxDim) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    if (it == g_sessions.end()) return JNI_FALSE;

    Session& s = it->second;
    int w = 0, h = 0;
    std::vector<uint8_t> rgba;
    if (!mupic::RenderPreviewCpu(s.linear, s.info, s.adj, maxDim, &rgba, &w, &h)) {
        LOGE("cpu preview failed id=%d", imageId);
        return JNI_FALSE;
    }
    s.preview_rgba = std::move(rgba);
    s.preview_w = w;
    s.preview_h = h;
    LOGI("cpu preview render id=%d %dx%d", imageId, w, h);
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativePreviewWidth(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.preview_w;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativePreviewHeight(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.preview_h;
}

JNIEXPORT jbyteArray JNICALL
Java_com_mupic_app_MuPicEditor_nativePreviewBytes(JNIEnv* env, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    if (it == g_sessions.end() || it->second.preview_rgba.empty()) return nullptr;
    const std::vector<uint8_t>& rgba = it->second.preview_rgba;
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(rgba.size()));
    if (arr != nullptr) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(rgba.size()),
                                reinterpret_cast<const jbyte*>(rgba.data()));
    }
    return arr;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeImageWidth(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.info.width;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeImageHeight(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.info.height;
}

// ---- Export (M6): full-resolution CPU render, cached for Kotlin to encode ---

JNIEXPORT jboolean JNICALL
Java_com_mupic_app_MuPicEditor_nativeRenderExportCpu(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    if (it == g_sessions.end()) return JNI_FALSE;

    Session& s = it->second;
    int w = 0, h = 0;
    std::vector<uint8_t> rgba;
    if (!mupic::RenderExportCpu(s.linear, s.info, s.adj, &rgba, &w, &h)) {
        LOGE("cpu export failed id=%d", imageId);
        return JNI_FALSE;
    }
    s.export_rgba = std::move(rgba);
    s.export_w = w;
    s.export_h = h;
    LOGI("cpu export render id=%d %dx%d", imageId, w, h);
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeExportWidth(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.export_w;
}

JNIEXPORT jint JNICALL
Java_com_mupic_app_MuPicEditor_nativeExportHeight(JNIEnv*, jobject, jint imageId) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sessions.find(imageId);
    return it == g_sessions.end() ? 0 : it->second.export_h;
}

// Copy the cached full-res export RGBA8 into a fresh byte array (w*h*4, RGBA).
// Consumed once: the cache is cleared so a later export re-renders cleanly.
JNIEXPORT jbyteArray JNICALL
Java_com_mupic_app_MuPicEditor_nativeExportBytes(JNIEnv* env, jobject, jint imageId) {
    std::vector<uint8_t> rgba;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_sessions.find(imageId);
        if (it == g_sessions.end() || it->second.export_rgba.empty()) return nullptr;
        rgba = std::move(it->second.export_rgba);
        it->second.export_rgba.clear();
    }
    const jsize bytes = static_cast<jsize>(rgba.size());
    jbyteArray arr = env->NewByteArray(bytes);
    if (arr != nullptr && bytes > 0) {
        env->SetByteArrayRegion(arr, 0, bytes,
                                reinterpret_cast<jbyte*>(rgba.data()));
    }
    return arr;
}

JNIEXPORT void JNICALL
Java_com_mupic_app_MuPicEditor_nativeRelease(JNIEnv* env, jobject, jint imageId) {
    (void)env;
    std::lock_guard<std::mutex> lock(g_mutex);
    g_sessions.erase(imageId);
}

}  // extern "C"
