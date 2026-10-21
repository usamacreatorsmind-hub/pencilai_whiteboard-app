package com.pencilai.whitebaordapp

import android.content.Context
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeDrawingViewFactory(private val channel: MethodChannel) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = NativeDrawingView(context, viewId, channel)
        val params = args as? Map<String, Any>
        if (params != null) {
            val color = (params["color"] as? Number)?.toInt() ?: -16777216
            val width = (params["width"] as? Number)?.toFloat() ?: 6f
            view.setStrokeConfig(color, width)
        }
        return view
    }
}
