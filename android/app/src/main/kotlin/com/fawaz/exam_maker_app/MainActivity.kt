package com.fawaz.exam_maker_app

import android.graphics.Bitmap
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
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
    private val excelPickerRequestCode = 7412
    private var pendingExcelPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickExcelDocument" -> {
                        if (pendingExcelPickerResult != null) {
                            result.error("PICKER_BUSY", "هناك عملية اختيار ملف جارية.", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                "application/vnd.ms-excel.sheet.macroEnabled.12",
                                "application/vnd.ms-excel",
                                "application/octet-stream",
                                "application/zip"
                            ))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        pendingExcelPickerResult = result
                        try {
                            startActivityForResult(intent, excelPickerRequestCode)
                        } catch (e: Exception) {
                            pendingExcelPickerResult = null
                            result.error("PICKER_FAILED", e.message ?: "تعذر فتح منتقي الملفات.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "openExcelDocument" -> {
                        val uriText = call.argument<String>("uri")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        if (uriText.isNullOrBlank()) {
                            result.error("INVALID_URI", "مرجع ملف Excel غير صالح.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(uriText), mimeType)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(viewIntent, "فتح ملف Excel"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEL_OPEN_FAILED", e.message ?: "تعذر فتح الملف في تطبيق آخر.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "readExcelDocument" -> {
                        val uriText = call.argument<String>("uri")
                        if (uriText.isNullOrBlank()) {
                            result.error("INVALID_URI", "مرجع ملف Excel غير صالح.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bytes = contentResolver.openInputStream(Uri.parse(uriText))?.use { it.readBytes() }
                                ?: throw IllegalStateException("تعذر فتح الملف للقراءة.")
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("EXCEL_READ_FAILED", e.message ?: "تعذرت قراءة ملف Excel الأصلي.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "writeExcelDocument" -> {
                        val uriText = call.argument<String>("uri")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (uriText.isNullOrBlank() || bytes == null) {
                            result.error("INVALID_ARGUMENT", "بيانات حفظ ملف Excel غير مكتملة.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            contentResolver.openOutputStream(Uri.parse(uriText), "wt")?.use { stream ->
                                stream.write(bytes)
                                stream.flush()
                            } ?: throw IllegalStateException("مزود الملفات لا يسمح بالكتابة إلى الملف الأصلي.")
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEL_WRITE_FAILED", e.message ?: "تعذر تحديث ملف Excel الأصلي.", null)
                        }
                        return@setMethodCallHandler
                    }
                    "createStudentPdf" -> Unit
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
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
                val studentDataOnLastPage = arguments["studentDataOnLastPage"] as? Boolean ?: false
                val cropTopFraction = (arguments["cropTopFraction"] as? Number)?.toFloat() ?: 0f
                val cropBottomFraction = (arguments["cropBottomFraction"] as? Number)?.toFloat() ?: 0f

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
                            subjectCode = subjectCode,
                            studentDataOnLastPage = studentDataOnLastPage,
                            cropTopFraction = cropTopFraction,
                            cropBottomFraction = cropBottomFraction
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


    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != excelPickerRequestCode) return

        val callback = pendingExcelPickerResult
        pendingExcelPickerResult = null
        if (callback == null) return
        if (resultCode != RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }

        val uri = data.data!!
        if ((data.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == 0) {
            callback.error(
                "EXCEL_READ_ONLY",
                "الملف المحدد لا يمنح التطبيق صلاحية الكتابة إلى الملف الأصلي. اختر ملفًا يسمح بالتعديل.",
                null
            )
            return
        }
        try {
            val grantedFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, grantedFlags)
        } catch (_: Exception) {
            // Some document providers only grant access for the current session.
        }

        var displayName = "workbook.xlsx"
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) displayName = cursor.getString(index) ?: displayName
            }
        } catch (_: Exception) {
        } finally {
            cursor?.close()
        }

        callback.success(mapOf("uri" to uri.toString(), "name" to displayName))
    }

    private fun createStudentPdf(
        sourcePath: String,
        outputPath: String,
        students: List<Map<String, String>>,
        subjectCode: Int,
        studentDataOnLastPage: Boolean,
        cropTopFraction: Float,
        cropBottomFraction: Float
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
                        val studentDataPageIndex = if (studentDataOnLastPage) source.numberOfPages - 1 else 0
                        val hasStudentData = !student["seatNo"].isNullOrBlank() && pageIndex == studentDataPageIndex

                        // مساحة الصفحة الأولى: 1 سم لبيانات الطالب و3 سم للكود وQR ومستطيل الدرجة.
                        val topReserve = if (hasStudentData) 28.35f else 0f
                        val bottomReserve = if (hasStudentData) 85.04f else 0f
                        val sideMargin = 20f
                        val contentWidth = pageWidth - (sideMargin * 2f)
                        val contentHeight = pageHeight - topReserve - bottomReserve

                        val box = form.bBox ?: sourcePage.mediaBox
                        val sourceWidth = box.width.coerceAtLeast(1f)
                        val sourceHeight = box.height.coerceAtLeast(1f)

                        // نسب القص قادمة من موضعي الخطين في معاينة الصفحة.
                        // نحتفظ بالجزء الواقع بين الحدين دون فرض هامش ثابت.
                        // القص يطبق على الصفحة الأولى فقط؛ بقية الصفحات تبقى كاملة.
                        val safeTopFraction = (if (pageIndex == 0) cropTopFraction else 0f)
                            .coerceIn(0f, 0.99f)
                        val safeBottomFraction = (if (pageIndex == 0) cropBottomFraction else 0f)
                            .coerceIn(0f, 0.99f)
                        val effectiveBottomFraction =
                            minOf(safeBottomFraction, 0.99f - safeTopFraction)
                        val topCrop = sourceHeight * safeTopFraction
                        val bottomCrop = sourceHeight * effectiveBottomFraction
                        val visibleHeight = (sourceHeight - topCrop - bottomCrop).coerceAtLeast(1f)

                        // Stretch the retained first-page content to fill the entire
                        // available rectangle between the 1 cm student header and
                        // the 3 cm QR/grade footer. Later source pages use the full page.
                        val scaleX = contentWidth / sourceWidth
                        val scaleY = contentHeight / visibleHeight
                        val offsetX = sideMargin
                        val offsetY = bottomReserve
                        val boxLeft = box.lowerLeftX
                        val boxBottom = box.lowerLeftY

                        PDPageContentStream(output, page).use { stream ->
                            stream.saveGraphicsState()
                            stream.transform(
                                Matrix(
                                    scaleX, 0f, 0f, scaleY,
                                    offsetX - (boxLeft * scaleX),
                                    offsetY - ((boxBottom + bottomCrop) * scaleY)
                                )
                            )
                            stream.addRect(
                                boxLeft,
                                boxBottom + bottomCrop,
                                sourceWidth,
                                visibleHeight
                            )
                            stream.clip()
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
                                // Keep the printed subject/period code in a high-contrast square
                                // matching the QR dimensions, immediately to its right.
                                val gradeBoxX = 20f
                                val qrX = gradeBoxX + 55f + 10f
                                val codeBoxSize = 38f
                                val codeBoxX = qrX + codeBoxSize + 8f
                                val codeBoxY = 12f

                                if (secret.isNotBlank()) {
                                    val qrBitmap = createQrBitmap(secret)
                                    val qrImage = LosslessFactory.createFromImage(output, qrBitmap)
                                    stream.drawImage(qrImage, qrX, codeBoxY, codeBoxSize, codeBoxSize)
                                    qrBitmap.recycle()
                                }

                                // White paper remains the box interior; use a strong black outline.
                                stream.setStrokingColor(0, 0, 0)
                                stream.setLineWidth(2.2f)
                                stream.addRect(codeBoxX, codeBoxY, codeBoxSize, codeBoxSize)
                                stream.stroke()

                                // Center the dark code in the square and lower it slightly
                                // from its previous baseline to align visually with the box.
                                val maxTextWidth = codeBoxSize - 7f
                                val naturalTextWidth = font.getStringWidth(subjectText) / 1000f * 22f
                                val codeFontSize = if (naturalTextWidth > maxTextWidth) {
                                    22f * maxTextWidth / naturalTextWidth
                                } else {
                                    22f
                                }
                                val textWidth = font.getStringWidth(subjectText) / 1000f * codeFontSize
                                val textX = codeBoxX + (codeBoxSize - textWidth) / 2f
                                val textY = codeBoxY + (codeBoxSize - codeFontSize * 0.70f) / 2f
                                stream.setNonStrokingColor(0, 0, 0)
                                drawText(stream, font, subjectText, textX, textY, codeFontSize)

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
