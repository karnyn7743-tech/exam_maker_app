package com.fawaz.exam_maker_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.os.Handler
import android.os.Looper
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.multipdf.LayerUtility
import com.tom_roush.pdfbox.util.Matrix
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.fawaz.exam_maker_app/document_pdf"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "createStudentPdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                val sourcePath = arguments["sourcePath"] as? String
                val outputPath = arguments["outputPath"] as? String
                val rawStudents = arguments["students"] as? List<*> ?: emptyList<Any?>()
                val students: List<Map<String, String>> = rawStudents.mapNotNull { item ->
                    val map = item as? Map<*, *> ?: return@mapNotNull null
                    map.entries.associate { entry ->
                        entry.key.toString() to (entry.value?.toString() ?: "")
                    }
                }
                val subjectCode = (arguments["subjectCode"] as? Number)?.toInt() ?: 1

                if (sourcePath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "مسار ملف PDF غير صالح.", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        createStudentPdf(
                            sourcePath = sourcePath,
                            outputPath = outputPath,
                            students = students,
                            subjectCode = subjectCode
                        )
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("PDF_PROCESSING_FAILED", e.message ?: "تعذرت معالجة ملف PDF.", null)
                        }
                    }
                }.start()
            }
    }

    private fun createStudentPdf(
        sourcePath: String,
        outputPath: String,
        students: List<Map<String, String>>,
        subjectCode: Int
    ) {
        PDFBoxResourceLoader.init(applicationContext)

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) throw IllegalArgumentException("ملف PDF الأصلي غير موجود.")

        PDDocument.load(sourceFile).use { source ->
            if (source.numberOfPages == 0) throw IllegalArgumentException("ملف PDF لا يحتوي على صفحات.")

            PDDocument().use { output ->
                val layerUtility = LayerUtility(output)
                val font = PDType0Font.load(
                    output,
                    assets.open("flutter_assets/assets/fonts/Amiri-Regular.ttf")
                )
                // Import each original PDF page once, then reuse its vector form for every student.
                val sourceForms = (0 until source.numberOfPages).map { pageIndex ->
                    layerUtility.importPageAsForm(source, source.getPage(pageIndex))
                }

                val copies: List<Map<String, String>> =
                    if (students.isEmpty()) listOf(emptyMap()) else students

                for (student in copies) {
                    for (pageIndex in 0 until source.numberOfPages) {
                        val sourcePage = source.getPage(pageIndex)
                        val form = sourceForms[pageIndex]
                        val page = PDPage(PDRectangle.A4)
                        output.addPage(page)

                        val pageWidth = PDRectangle.A4.width
                        val pageHeight = PDRectangle.A4.height
                        val hasStudentData = !student["seatNo"].isNullOrBlank() && pageIndex == 0

                        val topReserve = if (hasStudentData) 34f else 0f
                        val bottomReserve = if (hasStudentData) 62f else 0f
                        val sideMargin = 20f
                        val contentWidth = pageWidth - (sideMargin * 2f)
                        val contentHeight = pageHeight - topReserve - bottomReserve

                        val box = form.bBox ?: sourcePage.mediaBox
                        val sourceWidth = box.width.coerceAtLeast(1f)
                        val sourceHeight = box.height.coerceAtLeast(1f)
                        val scale = minOf(contentWidth / sourceWidth, contentHeight / sourceHeight)
                        val drawnWidth = sourceWidth * scale
                        val drawnHeight = sourceHeight * scale
                        val offsetX = sideMargin + (contentWidth - drawnWidth) / 2f
                        val offsetY = bottomReserve + (contentHeight - drawnHeight) / 2f

                        PDPageContentStream(output, page).use { stream ->
                            stream.saveGraphicsState()
                            stream.transform(Matrix(scale, 0f, 0f, scale, offsetX, offsetY))
                            stream.drawForm(form)
                            stream.restoreGraphicsState()

                            if (hasStudentData) {
                                val name = student["name"]?.toString().orEmpty()
                                val seat = student["seatNo"]?.toString().orEmpty()
                                val secret = student["secretCode"]?.toString().orEmpty()

                                drawArabicText(
                                    output, stream, "اسم الطالب: $name",
                                    pageWidth - 284f, pageHeight - 29f, 260f, 10.5f,
                                    Layout.Alignment.ALIGN_NORMAL
                                )
                                drawArabicText(
                                    output, stream, "رقم الجلوس: [ $seat ]",
                                    24f, pageHeight - 29f, 210f, 10.5f,
                                    Layout.Alignment.ALIGN_OPPOSITE
                                )

                                val subjectText = subjectCode.toString()
                                // Keep the grade box, QR, and code together at the far left.
                                // Reading order remains Arabic: code to the right of the QR.
                                val gradeBoxX = 20f
                                val qrX = gradeBoxX + 55f + 10f
                                val subjectRightX = qrX + 38f + 8f +
                                    (font.getStringWidth(subjectText) / 1000f * 22f)

                                drawRightText(
                                    stream, font, subjectText,
                                    subjectRightX, 27f, 22f
                                )

                                if (secret.isNotBlank()) {
                                    val qrBitmap = createQrBitmap(secret)
                                    val qrImage = LosslessFactory.createFromImage(output, qrBitmap)
                                    stream.drawImage(qrImage, qrX, 12f, 38f, 38f)
                                    qrBitmap.recycle()
                                }

                                stream.addRect(gradeBoxX, 10f, 55f, 45f)
                                stream.stroke()
                            }
                        }
                    }
                }

                File(outputPath).parentFile?.mkdirs()
                output.save(File(outputPath))
            }
        }
    }

    private fun createQrBitmap(value: String): Bitmap {
        val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, 240, 240)
        val bitmap = Bitmap.createBitmap(240, 240, Bitmap.Config.ARGB_8888)
        for (x in 0 until 240) {
            for (y in 0 until 240) {
                bitmap.setPixel(
                    x,
                    y,
                    if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
                )
            }
        }
        return bitmap
    }

    private fun drawArabicText(
        document: PDDocument,
        stream: PDPageContentStream,
        text: String,
        x: Float,
        y: Float,
        width: Float,
        fontSize: Float,
        alignment: Layout.Alignment
    ) {
        if (text.isBlank()) return

        val renderScale = 3
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.BLACK
            textSize = fontSize * renderScale
            typeface = Typeface.createFromAsset(
                assets,
                "flutter_assets/assets/fonts/Amiri-Regular.ttf"
            )
        }

        val layout = StaticLayout(
            text,
            paint,
            (width * renderScale).toInt().coerceAtLeast(1),
            alignment,
            1.0f,
            0.0f,
            false
        )
        val bitmap = Bitmap.createBitmap(
            (width * renderScale).toInt().coerceAtLeast(1),
            layout.height.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        layout.draw(canvas)

        val image = LosslessFactory.createFromImage(document, bitmap)
        stream.drawImage(
            image,
            x,
            y,
            width,
            layout.height.toFloat() / renderScale
        )
        bitmap.recycle()
    }

    private fun drawRightText(
        stream: PDPageContentStream,
        font: PDType0Font,
        text: String,
        rightX: Float,
        y: Float,
        size: Float
    ) {
        val width = font.getStringWidth(text) / 1000f * size
        drawText(stream, font, text, rightX - width, y, size)
    }

    private fun drawText(
        stream: PDPageContentStream,
        font: PDType0Font,
        text: String,
        x: Float,
        y: Float,
        size: Float
    ) {
        stream.beginText()
        stream.setFont(font, size)
        stream.newLineAtOffset(x, y)
        stream.showText(text)
        stream.endText()
    }
}
