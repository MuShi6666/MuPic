package com.mupic.app

import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MuPic host activity.
 *
 * Bridges the Flutter UI to the Android native image pipeline:
 *  - [MethodChannel] "mupic/editor" for control (open image / set params / export)
 *  - [EventChannel]  "mupic/events"  for decode & export progress / errors
 *  - Flutter [io.flutter.view.TextureRegistry] for zero-copy GPU preview frames
 *
 * M0 skeleton: channels are registered and the native library is loaded; the
 * full JNI-backed pipeline is implemented in later milestones (see the plan).
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "mupic/editor"
        private const val EVENT_CHANNEL = "mupic/events"

        init {
            // Loaded lazily so the app still runs on non-arm64 dev emulators
            // before the native core is fully wired up.
            try {
                System.loadLibrary("mupic_core")
            } catch (_: UnsatisfiedLinkError) {
                // Native core not available yet (M0 placeholder).
            }
        }
    }

    private val editor = MuPicEditor()

    @RequiresApi(Build.VERSION_CODES.ICE_CREAM_SANDWICH)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        editor.attach(flutterEngine.dartExecutor, flutterEngine.renderer, applicationContext)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            editor.onMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL
        ).setStreamHandler(editor)
    }

    override fun onDestroy() {
        editor.dispose()
        super.onDestroy()
    }
}
