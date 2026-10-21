package com.pencilai.whitebaordapp

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.View
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class NativeDrawingView(context: Context, id: Int, private val channel: MethodChannel) : PlatformView, View(context) {
    private val paint = Paint().apply {
        color = Color.BLACK
        strokeWidth = 6f
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        isAntiAlias = true
    }
    
    private val path = Path()
    private val points = mutableListOf<Map<String, Double>>()

    override fun getView(): View = this

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawPath(path, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                path.moveTo(x, y)
                points.clear()
                points.add(mapOf("dx" to x.toDouble(), "dy" to y.toDouble()))
            }
            MotionEvent.ACTION_MOVE -> {
                // Handle historical points for ultra-smoothness
                for (i in 0 until event.historySize) {
                    val hX = event.getHistoricalX(i)
                    val hY = event.getHistoricalY(i)
                    path.lineTo(hX, hY)
                    points.add(mapOf("dx" to hX.toDouble(), "dy" to hY.toDouble()))
                }
                path.lineTo(x, y)
                points.add(mapOf("dx" to x.toDouble(), "dy" to y.toDouble()))
                invalidate()
            }
            MotionEvent.ACTION_UP -> {
                // Send all points back to Flutter
                channel.invokeMethod("onStrokeComplete", mapOf(
                    "points" to points.toList()
                ))
                path.reset()
                invalidate()
            }
        }
        return true
    }

    override fun dispose() {}
    
    fun setStrokeConfig(color: Int, width: Float) {
        paint.color = color
        paint.strokeWidth = width
        invalidate()
    }
}
