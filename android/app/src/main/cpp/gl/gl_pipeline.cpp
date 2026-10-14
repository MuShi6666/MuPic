#include "gl/gl_pipeline.h"

#include <android/log.h>
#include <EGL/egl.h>
#include <GLES3/gl31.h>

#include <cmath>
#include <cstring>
#include <vector>

#define TAG "MuPicGLPipeline"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

namespace mupic {

namespace {

const char* kVertexSrc = R"glsl(#version 300 es
layout(location = 0) in vec2 a_pos;
out vec2 v_uv;
void main() {
    v_uv = a_pos * 0.5 + 0.5;
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
)glsl";

// Camera Raw "Basic" tone operator + M2 curve/HSL/grading. Each block is
// mirrored 1:1 by ApplyAdjustmentsCpu() so preview and export agree.
const char* kFragmentSrc = R"glsl(#version 300 es
precision highp float;
in vec2 v_uv;
out vec4 fragColor;

uniform sampler2D u_src;
uniform vec3 u_wb;
uniform float u_temp, u_tint, u_exposure, u_contrast;
uniform float u_highlights, u_shadows, u_whites, u_blacks;
uniform float u_vibrance, u_saturation;

uniform vec4 u_curveRgb, u_curveRed, u_curveGreen, u_curveBlue;  // 4 region controls
uniform vec3 u_hsl[8];    // x=hue y=sat z=lum, index 7 = global
uniform vec3 u_grade[3];  // x=hue y=sat z=lum; 0=sh 1=mid 2=high
uniform float u_gradeBlend, u_gradeMid;

// M3 Detail: texel size (1/w, 1/h) for neighborhood taps + sharpen/NR params.
uniform vec2 u_texel;
uniform float u_sharpAmount, u_sharpRadius, u_sharpDetail, u_sharpMasking;
uniform float u_nrLum, u_nrLumDetail, u_nrColor;
uniform float u_detailActive;

// M3 Lens corrections: aspect (w/h) for isotropic radial warp + lens params.
uniform float u_aspect;
uniform float u_lensRca, u_lensDefringeR, u_lensDefringeB, u_lensDistortion;
uniform float u_lensActive;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float HSL_WIDTH = 40.0 / 360.0;
const float HUE_FACTOR = 60.0 / 360.0;
const float LUM_FACTOR = 0.5;

float smoothstep01(float a, float b, float x) {
    float t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

vec3 tone(vec3 c) {
    c *= u_wb;
    c.r *= pow(2.0, u_temp * 0.5);
    c.b *= pow(2.0, -u_temp * 0.5);
    c.g *= pow(2.0, u_tint * 0.3);

    c *= pow(2.0, u_exposure);

    float lum = dot(c, LUMA);
    float hl_w = smoothstep01(0.5, 1.0, lum);
    float sh_w = 1.0 - smoothstep01(0.0, 0.5, lum);
    c += u_highlights * 0.5 * hl_w;
    c += u_shadows * 0.5 * sh_w;
    c += u_whites * 0.2 * hl_w;
    c += u_blacks * 0.2 * sh_w;

    c = (c - 0.5) * (1.0 + u_contrast) + 0.5;

    float l2 = dot(c, LUMA);
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    float vib = u_saturation + u_vibrance * (1.0 - sat);
    c = mix(vec3(l2), c, 1.0 + vib);

    return clamp(c, 0.0, 1.0);
}

// Parametric tone curve (mirrors mupic::ToneCurveEvaluate). ctrl = 4 regions.
float toneCurve(vec4 ctrl, float x) {
    x = clamp(x, 0.0, 1.0);
    float y = x;
    y += ctrl.x * (1.0 - y) * 0.5;   // shadows
    y -= ctrl.w * y * 0.5;           // highlights
    float slope = 1.0 + (ctrl.z - ctrl.y);  // mid2 - mid1
    y = clamp((y - 0.5) * slope + 0.5, 0.0, 1.0);
    return clamp(y, 0.0, 1.0);
}

vec3 rgb2hsl(vec3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float l = (mx + mn) * 0.5;
    float d = mx - mn;
    if (d <= 1e-6) return vec3(0.0, 0.0, l);
    float s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
    float h;
    if (mx == c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
    else h = (c.r - c.g) / d + 4.0;
    return vec3(h / 6.0, s, l);
}

float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 hsl) {
    float h = hsl.x, s = hsl.y, l = hsl.z;
    if (s <= 1e-6) return vec3(l);
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return vec3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}

float fractf(float v) { return v - floor(v); }
float hueDist(float a, float b) { float d = abs(a - b); return min(d, 1.0 - d); }

float hslCenter(int i) {
    if (i == 0) return 0.0;
    if (i == 1) return 30.0 / 360.0;
    if (i == 2) return 60.0 / 360.0;
    if (i == 3) return 120.0 / 360.0;
    if (i == 4) return 180.0 / 360.0;
    if (i == 5) return 240.0 / 360.0;
    return 300.0 / 360.0;
}

vec3 applyHsl(vec3 c) {
    vec3 hsl = rgb2hsl(c);
    float hue_sum = 0.0, sat_sum = 0.0, lum_sum = 0.0;
    for (int i = 0; i < 7; ++i) {
        float w = max(0.0, 1.0 - hueDist(hsl.x, hslCenter(i)) / HSL_WIDTH);
        hue_sum += w * u_hsl[i].x;
        sat_sum += w * u_hsl[i].y;
        lum_sum += w * u_hsl[i].z;
    }
    hue_sum += u_hsl[7].x;
    sat_sum += u_hsl[7].y;
    lum_sum += u_hsl[7].z;
    hsl.x = fractf(hsl.x + hue_sum * HUE_FACTOR);
    hsl.y = clamp(hsl.y * (1.0 + sat_sum), 0.0, 1.0);
    hsl.z = clamp(hsl.z * (1.0 + lum_sum * LUM_FACTOR), 0.0, 1.0);
    return hsl2rgb(hsl);
}

vec3 gradeTint(int i) {
    float h01 = fractf(u_grade[i].x * 0.5 + 0.5);
    return hsl2rgb(vec3(h01, clamp(u_grade[i].y, 0.0, 1.0), 0.5));
}

vec3 applyGrade(vec3 c) {
    float lum = dot(c, LUMA);
    float w = 0.2 + u_gradeBlend * 0.6;
    float bal = u_gradeMid - 0.5;
    float shC = 0.4 + bal * 0.4;
    float hiC = 0.6 + bal * 0.4;
    float ws = 1.0 - smoothstep(shC - w, shC + w, lum);
    float wh = smoothstep(hiC - w, hiC + w, lum);
    float wm = clamp(1.0 - ws - wh, 0.0, 1.0);
    vec3 ts = gradeTint(0), tm = gradeTint(1), th = gradeTint(2);
    const float cw = 0.5;
    c += cw * (ws * (ts - 0.5) + wm * (tm - 0.5) + wh * (th - 0.5));
    float lumK = 1.0 + ws * u_grade[0].z + wm * u_grade[1].z + wh * u_grade[2].z;
    c *= lumK;
    return clamp(c, 0.0, 1.0);
}

// Full per-pixel color chain: basic tone -> curve -> HSL -> grading.
vec3 adjust(vec3 c) {
    c = tone(c);
    c.r = toneCurve(u_curveRed, toneCurve(u_curveRgb, c.r));
    c.g = toneCurve(u_curveGreen, toneCurve(u_curveRgb, c.g));
    c.b = toneCurve(u_curveBlue, toneCurve(u_curveRgb, c.b));
    c = applyHsl(c);
    c = applyGrade(c);
    return c;
}

// Sample the raw source with lens correction applied (radial distortion +
// lateral chromatic aberration). R/B are sampled at slightly different radial
// scales than G. Mirrored 1:1 by the CPU `sampleSource` in color_pipeline.cpp.
// Constants (0.35 / 0.03 / 0.5) MUST match the CPU.
vec3 sampleSource(vec2 uv) {
    if (u_lensActive < 0.5) return texture(u_src, uv).rgb;
    vec2 q = uv - 0.5;
    q.x *= u_aspect;
    float r2 = dot(q, q);
    float kd = u_lensDistortion * 0.35;
    float kr = (u_lensRca * 0.5 + u_lensDefringeR) * 0.03;
    float kb = (-u_lensRca * 0.5 + u_lensDefringeB) * 0.03;
    float sR = 1.0 + (kd + kr) * r2;
    float sG = 1.0 + kd * r2;
    float sB = 1.0 + (kd + kb) * r2;
    vec2 dr = vec2(q.x * sR / u_aspect, q.y * sR) + 0.5;
    vec2 dg = vec2(q.x * sG / u_aspect, q.y * sG) + 0.5;
    vec2 db = vec2(q.x * sB / u_aspect, q.y * sB) + 0.5;
    return vec3(texture(u_src, dr).r, texture(u_src, dg).g, texture(u_src, db).b);
}

vec3 adjustAt(vec2 uv) { return adjust(sampleSource(uv)); }

// 3x3 Gaussian (weights 1,2,1/2,4,2/1,2,1) of the *adjusted* neighborhood,
// sampled at `radiusPx` texel spacing. Mirrored by the CPU gaussian in
// color_pipeline.cpp.
vec3 gaussianAdjust(vec2 uv, float radiusPx) {
    vec2 o = u_texel * radiusPx;
    vec3 sum =
        adjustAt(uv + vec2(-o.x, -o.y)) * 1.0 + adjustAt(uv + vec2(0.0, -o.y)) * 2.0 +
        adjustAt(uv + vec2(o.x, -o.y)) * 1.0 + adjustAt(uv + vec2(-o.x, 0.0)) * 2.0 +
        adjustAt(uv) * 4.0 + adjustAt(uv + vec2(o.x, 0.0)) * 2.0 +
        adjustAt(uv + vec2(-o.x, o.y)) * 1.0 + adjustAt(uv + vec2(0.0, o.y)) * 2.0 +
        adjustAt(uv + vec2(o.x, o.y)) * 1.0;
    return sum / 16.0;
}

// Sharpening (unsharp mask, edge-gated) + luminance/chroma noise reduction.
// Mirrored 1:1 by the CPU `applyDetail` in color_pipeline.cpp.
vec3 applyDetail(vec3 center, vec3 blur) {
    float lc = dot(center, LUMA);
    float lb = dot(blur, LUMA);
    float edge = abs(lc - lb);

    float thr = u_sharpMasking * 0.15;
    float mask = smoothstep(thr, thr + 0.05, edge);

    vec3 detail = center - blur;
    vec3 lumDetail = vec3(dot(detail, LUMA));
    vec3 chromaDetail = detail - lumDetail;
    vec3 sharpen = (lumDetail + chromaDetail * u_sharpDetail) * u_sharpAmount * mask;

    float flat = 1.0 - smoothstep(0.0, u_nrLumDetail * 0.15 + 0.01, edge);
    float lumNR = u_nrLum * flat;
    float chromaNR = u_nrColor;

    vec3 outc = center + sharpen;
    float l2 = dot(outc, LUMA);
    outc += vec3(mix(l2, lb, lumNR) - l2);

    vec3 ch = outc - vec3(dot(outc, LUMA));
    vec3 chB = blur - vec3(lb);
    ch = mix(ch, chB, chromaNR);
    outc = vec3(dot(outc, LUMA)) + ch;
    return clamp(outc, 0.0, 1.0);
}

void main() {
    vec4 s = texture(u_src, v_uv);
    vec3 c = adjust(sampleSource(v_uv));
    if (u_detailActive > 0.5) {
        vec3 blur = gaussianAdjust(v_uv, max(u_sharpRadius, 1.0));
        c = applyDetail(c, blur);
    }
    fragColor = vec4(c, s.a);
}
)glsl";

GLuint CompileShader(GLenum type, const char* src) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buf[1024];
        glGetShaderInfoLog(shader, sizeof(buf), nullptr, buf);
        LOGE("shader compile failed: %s", buf);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

GLuint LinkProgram(const char* vs, const char* fs) {
    GLuint v = CompileShader(GL_VERTEX_SHADER, vs);
    GLuint f = CompileShader(GL_FRAGMENT_SHADER, fs);
    if (!v || !f) return 0;
    GLuint program = glCreateProgram();
    glAttachShader(program, v);
    glAttachShader(program, f);
    glLinkProgram(program);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char buf[1024];
        glGetProgramInfoLog(program, sizeof(buf), nullptr, buf);
        LOGE("program link failed: %s", buf);
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

}  // namespace

GLPipeline::~GLPipeline() {
    // GL object deletion requires a current context; only do it if one is bound.
    if (surface_ != EGL_NO_SURFACE && context_.MakeCurrent(surface_)) {
        ReleaseGl();
        context_.ReleaseCurrent();
        context_.ReleaseWindow(surface_);
    }
    surface_ = EGL_NO_SURFACE;
    window_ = nullptr;
}

void GLPipeline::SetSource(const ImageBuffer& linear, const DecodeInfo& info) {
    source_ = linear;
    info_ = info;
    source_dirty_ = true;
}

bool GLPipeline::InitGl() {
    program_ = LinkProgram(kVertexSrc, kFragmentSrc);
    if (program_ == 0) return false;

    u_.src = glGetUniformLocation(program_, "u_src");
    u_.wb = glGetUniformLocation(program_, "u_wb");
    u_.temp = glGetUniformLocation(program_, "u_temp");
    u_.tint = glGetUniformLocation(program_, "u_tint");
    u_.exposure = glGetUniformLocation(program_, "u_exposure");
    u_.contrast = glGetUniformLocation(program_, "u_contrast");
    u_.highlights = glGetUniformLocation(program_, "u_highlights");
    u_.shadows = glGetUniformLocation(program_, "u_shadows");
    u_.whites = glGetUniformLocation(program_, "u_whites");
    u_.blacks = glGetUniformLocation(program_, "u_blacks");
    u_.vibrance = glGetUniformLocation(program_, "u_vibrance");
    u_.saturation = glGetUniformLocation(program_, "u_saturation");

    u_.curveRgb = glGetUniformLocation(program_, "u_curveRgb");
    u_.curveRed = glGetUniformLocation(program_, "u_curveRed");
    u_.curveGreen = glGetUniformLocation(program_, "u_curveGreen");
    u_.curveBlue = glGetUniformLocation(program_, "u_curveBlue");
    u_.hsl = glGetUniformLocation(program_, "u_hsl[0]");
    u_.grade = glGetUniformLocation(program_, "u_grade[0]");
    u_.gradeBlend = glGetUniformLocation(program_, "u_gradeBlend");
    u_.gradeMid = glGetUniformLocation(program_, "u_gradeMid");

    u_.texel = glGetUniformLocation(program_, "u_texel");
    u_.sharpAmount = glGetUniformLocation(program_, "u_sharpAmount");
    u_.sharpRadius = glGetUniformLocation(program_, "u_sharpRadius");
    u_.sharpDetail = glGetUniformLocation(program_, "u_sharpDetail");
    u_.sharpMasking = glGetUniformLocation(program_, "u_sharpMasking");
    u_.nrLum = glGetUniformLocation(program_, "u_nrLum");
    u_.nrLumDetail = glGetUniformLocation(program_, "u_nrLumDetail");
    u_.nrColor = glGetUniformLocation(program_, "u_nrColor");
    u_.detailActive = glGetUniformLocation(program_, "u_detailActive");

    u_.aspect = glGetUniformLocation(program_, "u_aspect");
    u_.lensRca = glGetUniformLocation(program_, "u_lensRca");
    u_.lensDefringeR = glGetUniformLocation(program_, "u_lensDefringeR");
    u_.lensDefringeB = glGetUniformLocation(program_, "u_lensDefringeB");
    u_.lensDistortion = glGetUniformLocation(program_, "u_lensDistortion");
    u_.lensActive = glGetUniformLocation(program_, "u_lensActive");

    glGenVertexArrays(1, &vao_);
    glBindVertexArray(vao_);
    const GLfloat quad[] = {-1, -1, 3, -1, -1, 3};  // fullscreen triangle
    glGenBuffers(1, &quad_vbo_);
    glBindBuffer(GL_ARRAY_BUFFER, quad_vbo_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), nullptr);
    glBindVertexArray(0);

    glGenTextures(1, &texture_);
    gl_ready_ = true;
    return true;
}

void GLPipeline::ReleaseGl() {
    if (texture_) glDeleteTextures(1, &texture_);
    if (quad_vbo_) glDeleteBuffers(1, &quad_vbo_);
    if (vao_) glDeleteVertexArrays(1, &vao_);
    if (program_) glDeleteProgram(program_);
    texture_ = quad_vbo_ = vao_ = program_ = 0;
    gl_ready_ = false;
}

bool GLPipeline::UploadSourceIfNeeded() {
    if (source_.empty()) return false;
    const int w = source_.width;
    const int h = source_.height;
    std::vector<uint8_t> rgba(static_cast<size_t>(w) * h * 4);
    for (size_t i = 0, n = static_cast<size_t>(w) * h; i < n; ++i) {
        auto to8 = [&](float v) {
            return static_cast<uint8_t>(std::lrint(std::clamp(v, 0.f, 1.f) * 255.f));
        };
        rgba[i * 4 + 0] = to8(source_.pixels[i * 4 + 0]);
        rgba[i * 4 + 1] = to8(source_.pixels[i * 4 + 1]);
        rgba[i * 4 + 2] = to8(source_.pixels[i * 4 + 2]);
        rgba[i * 4 + 3] = to8(source_.pixels[i * 4 + 3]);
    }

    glBindTexture(GL_TEXTURE_2D, texture_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    tex_w_ = w;
    tex_h_ = h;
    source_dirty_ = false;
    return true;
}

void GLPipeline::ApplyUniforms(const RawAdjustments& adj) const {
    glUseProgram(program_);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture_);
    glUniform1i(u_.src, 0);
    glUniform3f(u_.wb, info_.wb_multiplier[0], info_.wb_multiplier[1], info_.wb_multiplier[2]);
    glUniform1f(u_.temp, adj.color_temp);
    glUniform1f(u_.tint, adj.tint);
    glUniform1f(u_.exposure, adj.exposure);
    glUniform1f(u_.contrast, adj.contrast);
    glUniform1f(u_.highlights, adj.highlights);
    glUniform1f(u_.shadows, adj.shadows);
    glUniform1f(u_.whites, adj.whites);
    glUniform1f(u_.blacks, adj.blacks);
    glUniform1f(u_.vibrance, adj.vibrance);
    glUniform1f(u_.saturation, adj.saturation);

    // Tone curve: four region controls per channel (index 4 reserved).
    if (u_.curveRgb >= 0)
        glUniform4f(u_.curveRgb, adj.curve_rgb[0], adj.curve_rgb[1], adj.curve_rgb[2], adj.curve_rgb[3]);
    if (u_.curveRed >= 0)
        glUniform4f(u_.curveRed, adj.curve_red[0], adj.curve_red[1], adj.curve_red[2], adj.curve_red[3]);
    if (u_.curveGreen >= 0)
        glUniform4f(u_.curveGreen, adj.curve_green[0], adj.curve_green[1], adj.curve_green[2], adj.curve_green[3]);
    if (u_.curveBlue >= 0)
        glUniform4f(u_.curveBlue, adj.curve_blue[0], adj.curve_blue[1], adj.curve_blue[2], adj.curve_blue[3]);

    // HSL: build vec3[8] (hue, sat, lum) from the flat parameter arrays.
    if (u_.hsl >= 0) {
        GLfloat hsl[kHslRanges * 3];
        for (int i = 0; i < kHslRanges; ++i) {
            hsl[i * 3 + 0] = adj.hsl_hue[i];
            hsl[i * 3 + 1] = adj.hsl_sat[i];
            hsl[i * 3 + 2] = adj.hsl_lum[i];
        }
        glUniform3fv(u_.hsl, kHslRanges, hsl);
    }

    // Color grading: vec3[3] (hue, sat, lum) + blending + midtone range.
    if (u_.grade >= 0) {
        GLfloat grade[3 * 3];
        for (int i = 0; i < 3; ++i) {
            grade[i * 3 + 0] = adj.grade_hue[i];
            grade[i * 3 + 1] = adj.grade_sat[i];
            grade[i * 3 + 2] = adj.grade_lum[i];
        }
        glUniform3fv(u_.grade, 3, grade);
    }
    if (u_.gradeBlend >= 0) glUniform1f(u_.gradeBlend, adj.grade_blending);
    if (u_.gradeMid >= 0) glUniform1f(u_.gradeMid, adj.grade_midtone_range);

    // M3 Detail. Only pays for the gaussian taps when an op is active.
    const bool detailActive = adj.sharpen_amount > 1e-6f || adj.nr_luminance > 1e-6f ||
                              adj.nr_color > 1e-6f;
    if (u_.texel >= 0 && tex_w_ > 0 && tex_h_ > 0)
        glUniform2f(u_.texel, 1.f / static_cast<float>(tex_w_), 1.f / static_cast<float>(tex_h_));
    if (u_.sharpAmount >= 0) glUniform1f(u_.sharpAmount, adj.sharpen_amount);
    if (u_.sharpRadius >= 0) glUniform1f(u_.sharpRadius, adj.sharpen_radius);
    if (u_.sharpDetail >= 0) glUniform1f(u_.sharpDetail, adj.sharpen_detail);
    if (u_.sharpMasking >= 0) glUniform1f(u_.sharpMasking, adj.sharpen_masking);
    if (u_.nrLum >= 0) glUniform1f(u_.nrLum, adj.nr_luminance);
    if (u_.nrLumDetail >= 0) glUniform1f(u_.nrLumDetail, adj.nr_lum_detail);
    if (u_.nrColor >= 0) glUniform1f(u_.nrColor, adj.nr_color);
    if (u_.detailActive >= 0) glUniform1f(u_.detailActive, detailActive ? 1.f : 0.f);

    // M3 Lens corrections. aspect = w/h so the radial warp is isotropic.
    const bool lensActive = adj.lens_distortion > 1e-6f || adj.lens_distortion < -1e-6f ||
                            adj.lens_rca > 1e-6f || adj.lens_defringe_red > 1e-6f ||
                            adj.lens_defringe_red < -1e-6f || adj.lens_defringe_blue > 1e-6f ||
                            adj.lens_defringe_blue < -1e-6f;
    if (u_.aspect >= 0 && tex_w_ > 0 && tex_h_ > 0)
        glUniform1f(u_.aspect, static_cast<float>(tex_w_) / static_cast<float>(tex_h_));
    if (u_.lensRca >= 0) glUniform1f(u_.lensRca, adj.lens_rca);
    if (u_.lensDefringeR >= 0) glUniform1f(u_.lensDefringeR, adj.lens_defringe_red);
    if (u_.lensDefringeB >= 0) glUniform1f(u_.lensDefringeB, adj.lens_defringe_blue);
    if (u_.lensDistortion >= 0) glUniform1f(u_.lensDistortion, adj.lens_distortion);
    if (u_.lensActive >= 0) glUniform1f(u_.lensActive, lensActive ? 1.f : 0.f);
}

bool GLPipeline::Render(ANativeWindow* window, const RawAdjustments& adj, int quality) {
    (void)quality;
    if (window == nullptr || source_.empty()) return false;

    if (!context_.valid() && !context_.InitDisplay()) {
        LOGE("GLContext init failed");
        return false;
    }

    if (window != window_ || surface_ == EGL_NO_SURFACE) {
        if (surface_ != EGL_NO_SURFACE) {
            context_.ReleaseCurrent();
            context_.ReleaseWindow(surface_);
            surface_ = EGL_NO_SURFACE;
        }
        surface_ = context_.AcquireWindow(window);
        window_ = window;
    }
    if (surface_ == EGL_NO_SURFACE) return false;

    if (!context_.MakeCurrent(surface_)) return false;

    if (!gl_ready_ && !InitGl()) {
        context_.ReleaseCurrent();
        return false;
    }
    if (source_dirty_ && !UploadSourceIfNeeded()) {
        context_.ReleaseCurrent();
        return false;
    }

    // After eglMakeCurrent the default viewport matches the surface size.
    GLint viewport[4] = {0, 0, 0, 0};
    glGetIntegerv(GL_VIEWPORT, viewport);

    glViewport(0, 0, viewport[2], viewport[3]);
    glClearColor(0.f, 0.f, 0.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);

    ApplyUniforms(adj);
    glBindVertexArray(vao_);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);

    if (eglSwapBuffers(context_.egl_display(), surface_) != EGL_TRUE) {
        LOGE("eglSwapBuffers failed: 0x%x, will recreate surface", eglGetError());
        context_.ReleaseCurrent();
        context_.ReleaseWindow(surface_);
        surface_ = EGL_NO_SURFACE;
        window_ = nullptr;
        return false;
    }

    context_.ReleaseCurrent();
    return true;
}

}  // namespace mupic
