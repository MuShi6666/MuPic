package com.mupic.app

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.common.PointF3D
import com.google.mlkit.vision.facemesh.FaceMesh
import com.google.mlkit.vision.facemesh.FaceMeshDetection
import com.google.mlkit.vision.facemesh.FaceMeshDetectorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.OutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val TAG = "MuPicEditor"

/**
 * Native editor host for the MuPic pipeline.
 *
 * Owns the Flutter method/event channels and the [TextureRegistry] surface used
 * to push GPU preview frames into the Dart [Texture] widget. In M0 the JNI calls
 * are declared but the heavy lifting (LibRaw decode + GL pipeline) is stubbed so
 * the whole Flutter <-> Kotlin <-> JNI path is wired and testable end to end.
 */
class MuPicEditor : EventChannel.StreamHandler {

    private var events: EventChannel.EventSink? = null
    private var textures: TextureRegistry? = null

    // Application context lets export write the rendered image into the gallery
    // (MediaStore) without holding an Activity reference.
    private var appContext: Context? = null

    // CPU preview renders off the platform thread; results are posted back to
    // the main looper because MethodChannel.Result must be signalled on it.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val rawExtensions = setOf(
        "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "dng", "pef", "srw", "raw"
    )

    fun attach(messenger: BinaryMessenger, textures: TextureRegistry, context: Context) {
        this.textures = textures
        this.appContext = context.applicationContext
    }

    // ---- JNI surface (implemented in cpp/jni_bridge.cpp) ----
    private external fun nativeOpenImage(path: String): Int
    private external fun nativeOpenImageBuffer(width: Int, height: Int, rgba: ByteArray): Int
    private external fun nativeSetParams(imageId: Int, params: ByteArray)
    private external fun nativeRenderPreviewCpu(imageId: Int, maxDim: Int): Boolean
    private external fun nativePreviewWidth(imageId: Int): Int
    private external fun nativePreviewHeight(imageId: Int): Int
    private external fun nativePreviewBytes(imageId: Int): ByteArray?
    private external fun nativeRenderExportCpu(imageId: Int): Boolean
    private external fun nativeExportWidth(imageId: Int): Int
    private external fun nativeExportHeight(imageId: Int): Int
    private external fun nativeExportBytes(imageId: Int): ByteArray?
    private external fun nativeRelease(imageId: Int)
    private external fun nativeImageWidth(imageId: Int): Int
    private external fun nativeImageHeight(imageId: Int): Int

    @RequiresApi(Build.VERSION_CODES.ICE_CREAM_SANDWICH)
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openImage" -> {
                    val path = call.argument<String>("path")
                        ?: return result.error("bad_args", "path required", null)
                    val ext = path.substringAfterLast('.', "").lowercase()
                    val id: Int
                    val w: Int
                    val h: Int
                    if (ext in rawExtensions) {
                        // RAW: routed to LibRaw (native) / placeholder until it lands.
                        id = nativeOpenImage(path)
                        w = nativeImageWidth(id)
                        h = nativeImageHeight(id)
                    } else {
                        // JPEG / PNG: decode via Android's BitmapFactory, hand RGBA8 to native.
                        val decoded = decodeRaster(path)
                        if (decoded == null) {
                            return result.error("decode_failed", "could not decode $path", null)
                        }
                        w = decoded.first
                        h = decoded.second
                        id = nativeOpenImageBuffer(w, h, decoded.third)
                    }
                    result.success(
                        mapOf(
                            "imageId" to id,
                            "width" to w,
                            "height" to h,
                        )
                    )
                }
                "setParams" -> {
                    val imageId = call.argument<Int>("imageId") ?: 0
                    val params = call.argument<ByteArray>("params") ?: ByteArray(0)
                    nativeSetParams(imageId, params)
                    result.success(null)
                }
                "render" -> {
                    val imageId = call.argument<Int>("imageId") ?: 0
                    val maxDim = call.argument<Int>("maxDim") ?: 1024
                    executor.execute {
                        val payload: Map<String, Any>? = try {
                            if (nativeRenderPreviewCpu(imageId, maxDim)) {
                                mapOf(
                                    "width" to nativePreviewWidth(imageId),
                                    "height" to nativePreviewHeight(imageId),
                                    "bytes" to (nativePreviewBytes(imageId) ?: ByteArray(0)),
                                )
                            } else {
                                null
                            }
                        } catch (t: Throwable) {
                            Log.e(TAG, "cpu render failed", t)
                            null
                        }
                        mainHandler.post { result.success(payload) }
                    }
                    return
                }
                "export" -> {
                    val imageId = call.argument<Int>("imageId") ?: 0
                    val format = call.argument<String>("format") ?: "jpeg"
                    val quality = call.argument<Int>("quality") ?: 92
                    // Full-res render + encode is heavy; run it off the platform
                    // thread and post the saved URI back on the main looper.
                    executor.execute {
                        try {
                            if (!nativeRenderExportCpu(imageId)) {
                                mainHandler.post {
                                    result.error("render_failed", "全分辨率渲染失败", null)
                                }
                                return@execute
                            }
                            val w = nativeExportWidth(imageId)
                            val h = nativeExportHeight(imageId)
                            val rgba = nativeExportBytes(imageId)
                            val saved =
                                if (rgba != null && rgba.isNotEmpty() && w > 0 && h > 0)
                                    encodeAndSave(rgba, w, h, format, quality)
                                else null
                            mainHandler.post {
                                if (saved != null) result.success(saved)
                                else result.error("export_failed", "导出写入失败", null)
                            }
                        } catch (t: Throwable) {
                            Log.e(TAG, "export failed", t)
                            mainHandler.post { result.error("export_failed", t.message, null) }
                        }
                    }
                    return
                }
                "release" -> {
                    val imageId = call.argument<Int>("imageId") ?: 0
                    nativeRelease(imageId)
                    result.success(null)
                }
                "detectFace" -> {
                    val path = call.argument<String>("path")
                        ?: return result.error("bad_args", "path required", null)
                    // FaceMesh decode + inference is heavy; run it off the
                    // platform thread and post the flat point list back on main.
                    executor.execute {
                        val payload: List<Double> = try {
                            detectFacePoints(path)
                        } catch (t: Throwable) {
                            Log.e(TAG, "face detect failed", t)
                            emptyList()
                        }
                        mainHandler.post { result.success(payload) }
                    }
                    return
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "method ${call.method} failed", t)
            result.error("native_error", t.message, null)
        }
    }

    /// Decodes a raster image to (width, height, RGBA8 bytes) using BitmapFactory.
    private fun decodeRaster(path: String): Triple<Int, Int, ByteArray>? {
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bmp = BitmapFactory.decodeFile(path, opts) ?: return null
        val w = bmp.width
        val h = bmp.height
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        bmp.recycle()
        val rgba = ByteArray(w * h * 4)
        for (i in 0 until w * h) {
            val argb = pixels[i]
            rgba[i * 4] = ((argb shr 16) and 0xFF).toByte()      // R
            rgba[i * 4 + 1] = ((argb shr 8) and 0xFF).toByte()   // G
            rgba[i * 4 + 2] = (argb and 0xFF).toByte()           // B
            rgba[i * 4 + 3] = ((argb ushr 24) and 0xFF).toByte() // A
        }
        return Triple(w, h, rgba)
    }

    // ---- FaceMesh (人脸液化) ----

    // Canonical MediaPipe face-oval vertex indices (36 pts), emitted in this
    // exact order so the native `buildFaceImpulses` cheek / jaw index ranges
    // line up. Keep in sync with cpp/core/color_pipeline.cpp `namespace face`.
    private val faceOvalIndices = intArrayOf(
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378,
        400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21,
        54, 103, 67, 109,
    )

    /// Runs ML Kit FaceMesh on [path] and returns the largest face's key points
    /// as a flat, source-normalized list `[x0, y0, x1, y1, ...]` in the FIXED
    /// 45-point order the native engine expects:
    ///   [0..35]  face oval (canonical order)
    ///   [36]     right eye center  (RIGHT_EYE contour average)
    ///   [37]     left  eye center  (LEFT_EYE  contour average)
    ///   [38]     nose tip (1)      [39] nose bridge (6)
    ///   [40]     right wing (129)  [41] left wing (358)
    ///   [42]     right mouth (61)  [43] left mouth (291)  [44] chin (152)
    /// Empty list when no face is found. Coords are normalized against the
    /// downsampled bitmap, which preserves the source aspect + BitmapFactory
    /// orientation used by [decodeRaster], so they align with the native
    /// source space.
    private fun detectFacePoints(path: String): List<Double> {
        val bmp = decodeDownsampled(path, 720) ?: return emptyList()
        try {
            val image = InputImage.fromBitmap(bmp, 0)
            val options = FaceMeshDetectorOptions.Builder()
                .setUseCase(FaceMeshDetectorOptions.FACE_MESH)
                .build()
            val client = FaceMeshDetection.getClient(options)
            val faces: List<FaceMesh> = try {
                Tasks.await(client.process(image))
            } finally {
                client.close()
            }
            val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                ?: return emptyList()

            val pts = arrayOfNulls<PointF3D>(468)
            for (p in face.allPoints) {
                val idx = p.index
                if (idx in 0 until 468) pts[idx] = p.position
            }

            val w = bmp.width.toFloat()
            val h = bmp.height.toFloat()
            val out = ArrayList<Double>(45 * 2)
            fun emit(x: Float, y: Float) {
                out.add((x / w).toDouble())
                out.add((y / h).toDouble())
            }
            fun emitIdx(i: Int): Boolean {
                val p = pts[i] ?: return false
                emit(p.x, p.y)
                return true
            }
            fun emitEyeCenter(contourType: Int): Boolean {
                var sx = 0f
                var sy = 0f
                var n = 0
                for (p in face.getPoints(contourType)) {
                    sx += p.position.x
                    sy += p.position.y
                    n++
                }
                if (n == 0) return false
                emit(sx / n, sy / n)
                return true
            }

            for (mi in faceOvalIndices) if (!emitIdx(mi)) return emptyList() // 0..35
            if (!emitEyeCenter(FaceMesh.RIGHT_EYE)) return emptyList()       // 36
            if (!emitEyeCenter(FaceMesh.LEFT_EYE)) return emptyList()        // 37
            for (mi in intArrayOf(1, 6, 129, 358, 61, 291, 152)) {           // 38..44
                if (!emitIdx(mi)) return emptyList()
            }
            return out
        } finally {
            bmp.recycle()
        }
    }

    /// Decodes [path] with BitmapFactory, downscaled so the longest edge is at
    /// most [maxDim]. Mirrors [decodeRaster]'s orientation handling so the
    /// normalized face coords stay aligned with the native source space.
    private fun decodeDownsampled(path: String, maxDim: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / sample > maxDim) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sample
        }
        return BitmapFactory.decodeFile(path, opts)
    }

    /// Encodes full-res RGBA8 to JPEG/PNG and saves into the gallery. Returns the
    /// content URI on API 29+, or a file path on older devices (app-specific dir).
    private fun encodeAndSave(
        rgba: ByteArray, w: Int, h: Int, format: String, quality: Int,
    ): String? {
        val ctx = appContext ?: return null
        val argb = IntArray(w * h)
        for (i in 0 until w * h) {
            val r = rgba[i * 4].toInt() and 0xFF
            val g = rgba[i * 4 + 1].toInt() and 0xFF
            val b = rgba[i * 4 + 2].toInt() and 0xFF
            val a = rgba[i * 4 + 3].toInt() and 0xFF
            argb[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(argb, 0, w, 0, 0, w, h)

        val isPng = format.equals("png", ignoreCase = true)
        val compressFormat =
            if (isPng) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
        val mime = if (isPng) "image/png" else "image/jpeg"
        val name = "MuPic_${System.currentTimeMillis()}.${if (isPng) "png" else "jpg"}"

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveToMediaStore(ctx, bmp, compressFormat, quality, mime, name)
            } else {
                saveToAppDir(ctx, bmp, compressFormat, quality, name)
            }
        } finally {
            bmp.recycle()
        }
    }

    private fun saveToMediaStore(
        ctx: Context, bmp: Bitmap, format: Bitmap.CompressFormat,
        quality: Int, mime: String, name: String,
    ): String? {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/MuPic")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        val out = resolver.openOutputStream(uri) ?: return null
        out.use { os: OutputStream ->
            if (!bmp.compress(format, quality, os)) {
                resolver.delete(uri, null, null)
                return null
            }
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    private fun saveToAppDir(
        ctx: Context, bmp: Bitmap, format: Bitmap.CompressFormat,
        quality: Int, name: String,
    ): String? {
        val dir = ctx.getExternalFilesDir(android.os.Environment.DIRECTORY_PICTURES)
            ?: ctx.filesDir
        val file = java.io.File(dir, name)
        file.outputStream().use { os ->
            if (!bmp.compress(format, quality, os)) return null
        }
        return file.absolutePath
    }

    // ---- EventChannel.StreamHandler ----
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    fun dispose() {
        executor.shutdownNow()
    }
}
