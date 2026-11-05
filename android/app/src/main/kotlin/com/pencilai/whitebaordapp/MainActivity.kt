package com.pencilai.whitebaordapp

import android.content.ClipData
import android.content.ClipDescription
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.DragEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.DragAndDropPermissions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val PERFORMANCE_CHANNEL = "com.pencilai.whiteboard/performance"
    private val TOUCH_HINTS_CHANNEL = "com.pencilai.whiteboard/touch_hints"
    private val CONTENT_RESOLVER_CHANNEL = "com.pencilai.whiteboard/content_resolver"
    private val DROP_CHANNEL = "com.pencilai.whiteboard/drop"

    private var eventSink: EventChannel.EventSink? = null
    private var dropSink: EventChannel.EventSink? = null
    private val dropExecutor = Executors.newSingleThreadExecutor()
    private var hasDropped = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        makeFullScreen()
        setupNativeDropListener()
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

    override fun onDestroy() {
        dropExecutor.shutdown()
        super.onDestroy()
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

    private fun setupNativeDropListener() {
        window.decorView.setOnDragListener(View.OnDragListener { _, event ->
            val x = event.x.toDouble()
            val y = event.y.toDouble()
            when (event.action) {
                DragEvent.ACTION_DRAG_STARTED -> {
                    hasDropped = false
                    val desc: ClipDescription? = event.clipDescription
                    val accepts = desc != null && (
                        desc.hasMimeType("image/*") ||
                        desc.hasMimeType("text/uri-list") ||
                        desc.hasMimeType("text/html") ||
                        desc.hasMimeType("text/plain")
                    )
                    accepts
                }
                DragEvent.ACTION_DRAG_ENTERED -> {
                    runOnUiThread {
                        dropSink?.success(hashMapOf("type" to "enter", "x" to x, "y" to y))
                    }
                    true
                }
                DragEvent.ACTION_DRAG_LOCATION -> {
                    runOnUiThread {
                        dropSink?.success(hashMapOf("type" to "update", "x" to x, "y" to y))
                    }
                    true
                }
                DragEvent.ACTION_DRAG_EXITED -> {
                    runOnUiThread {
                        dropSink?.success(hashMapOf("type" to "exit"))
                    }
                    true
                }
                DragEvent.ACTION_DRAG_ENDED -> {
                    if (hasDropped == false) {
                        runOnUiThread {
                            dropSink?.success(hashMapOf("type" to "exit"))
                        }
                    }
                    true
                }
                DragEvent.ACTION_DROP -> {
                    hasDropped = true
                    handleNativeDrop(event)
                    true
                }
                else -> true
            }
        })
    }

    private fun handleNativeDrop(event: DragEvent) {
        if (dropSink == null) return

        var dropPermissions: DragAndDropPermissions? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                dropPermissions = requestDragAndDropPermissions(event)
            } catch (e: Exception) {
                Log.w("MainActivity", "Failed requesting drag permissions: ${e.message}")
            }
        }

        val x = event.x.toDouble()
        val y = event.y.toDouble()
        val clipData: ClipData? = event.clipData

        dropExecutor.execute {
            var successSent = false
            try {
                if (clipData != null && clipData.itemCount > 0) {
                    for (i in 0 until clipData.itemCount) {
                        val item = clipData.getItemAt(i)
                        val uri = item.uri

                        if (uri != null) {
                            try {
                                val mimeType = contentResolver.getType(uri) ?: "image/png"
                                if (mimeType.startsWith("image/") || mimeType == "application/octet-stream" || mimeType == "*/*") {
                                    val inputStream = contentResolver.openInputStream(uri)
                                    val bytes = inputStream?.readBytes()
                                    inputStream?.close()
                                    if (bytes != null && bytes.isNotEmpty() && bytes.size <= 25 * 1024 * 1024) {
                                        runOnUiThread {
                                            dropSink?.success(hashMapOf(
                                                "type" to "drop",
                                                "kind" to "image",
                                                "bytes" to bytes,
                                                "mime" to mimeType,
                                                "x" to x,
                                                "y" to y
                                            ))
                                        }
                                        successSent = true
                                        break
                                    }
                                }
                            } catch (e: Exception) {
                                Log.w("MainActivity", "Error reading content URI: ${e.message}")
                            }
                        }

                        val textStr = item.text?.toString() ?: item.htmlText?.toString()
                        if (textStr != null && textStr.isNotEmpty()) {
                            val htmlStr = item.htmlText?.toString()
                            runOnUiThread {
                                dropSink?.success(hashMapOf(
                                    "type" to "drop",
                                    "kind" to "text",
                                    "text" to textStr,
                                    "html" to htmlStr,
                                    "x" to x,
                                    "y" to y
                                ))
                            }
                            successSent = true
                            break
                        }
                    }
                }
                if (successSent == false) {
                    runOnUiThread {
                        dropSink?.error("DROP_READ_ERROR", "No readable image or URL found in dropped items", null)
                    }
                }
            } catch (e: Exception) {
                Log.w("MainActivity", "Error processing native drop: ${e.message}")
                if (successSent == false) {
                    runOnUiThread {
                        dropSink?.error("DROP_READ_ERROR", e.message ?: "Native drop error", null)
                    }
                }
            } finally {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        dropPermissions?.release()
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Error releasing permissions: ${e.message}")
                    }
                }
            }
        }
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTENT_RESOLVER_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "readContentUri") {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    try {
                        val uri = Uri.parse(uriString)
                        val inputStream = contentResolver.openInputStream(uri)
                        val bytes = inputStream?.readBytes()
                        inputStream?.close()
                        if (bytes != null) {
                            result.success(bytes)
                        } else {
                            result.error("NULL_BYTES", "Failed to read bytes from ContentResolver", null)
                        }
                    } catch (e: Exception) {
                        result.error("READ_ERROR", e.message ?: "Unknown error", null)
                    }
                } else {
                    result.error("INVALID_ARG", "URI is null", null)
                }
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

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DROP_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    dropSink = events
                }

                override fun onCancel(arguments: Any?) {
                    dropSink = null
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
