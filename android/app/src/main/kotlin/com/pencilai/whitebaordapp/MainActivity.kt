package com.pencilai.whitebaordapp

import android.os.Build
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pencilai.whiteboard/performance"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "enableHighRefreshRate") {
                enableHighRefreshRate()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val window = window
            val params = window.attributes
            val display = try { this.display } catch (e: Exception) { null }
            val modes = display?.supportedModes
            if (modes != null) {
                var maxRefreshRate = 0f
                var bestMode: Display.Mode? = null
                for (mode in modes) {
                    if (mode.refreshRate > maxRefreshRate) {
                        maxRefreshRate = mode.refreshRate
                        bestMode = mode
                    }
                }
                if (bestMode != null) {
                    params.preferredDisplayModeId = bestMode.modeId
                    window.attributes = params
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val window = window
            val params = window.attributes
            params.preferredRefreshRate = 120f
            window.attributes = params
        }
    }
}
