package com.pencilai.whitebaordapp

import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PERFORMANCE_CHANNEL = "com.pencilai.whiteboard/performance"
    private val TOUCH_HINTS_CHANNEL = "com.pencilai.whiteboard/touch_hints"

    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        makeFullScreen()
    }

    override fun onResume() {
        super.onResume()
        makeFullScreen()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            makeFullScreen()
        }
    }

    private fun makeFullScreen() {
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERFORMANCE_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "enableHighRefreshRate") {
                enableHighRefreshRate()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TOUCH_HINTS_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        processMotionEvent(event)
        return super.dispatchTouchEvent(event)
    }

    private fun processMotionEvent(event: MotionEvent) {
        val sink = eventSink ?: return
        val action = event.actionMasked

        val isCanceled = if (Build.VERSION.SDK_INT >= 33) {
            (event.flags and MotionEvent.FLAG_CANCELED) != 0 || action == MotionEvent.ACTION_CANCEL
        } else {
            action == MotionEvent.ACTION_CANCEL
        }

        val list = ArrayList<Map<String, Any>>(event.pointerCount)
        for (i in 0 until event.pointerCount) {
            list.add(hashMapOf(
                "pointerId" to event.getPointerId(i),
                "toolType" to event.getToolType(i),
                "touchMajor" to event.getTouchMajor(i).toDouble(),
                "touchMinor" to event.getTouchMinor(i).toDouble(),
                "toolMajor" to event.getToolMajor(i).toDouble(),
                "size" to event.getSize(i).toDouble(),
                "action" to action,
                "isCanceled" to isCanceled
            ))
        }

        sink.success(hashMapOf(
            "pointers" to list,
            "pointerCount" to event.pointerCount,
            "action" to action,
            "isCanceled" to isCanceled
        ))
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val window = window
            val params = window.attributes
            val display = try {
                this.display
            } catch (e: Exception) {
                null
            }
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
