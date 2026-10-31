import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> requestPermissionsStepByStep(BuildContext context, VoidCallback onFinished) async {
  // 1. طلب إذن التخزين مع شرح توضيحي
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.folder_shared, color: Color(0xFF1E3A8A)),
          SizedBox(width: 8),
          Text('إذن التخزين وحفظ الملفات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
      content: const Text(
        'يحتاج التطبيق إلى صلاحية الوصول للتخزين ليتمكن من حفظ ملفات الاختبارات بصيغة PDF وتصدير أوراق الأسئلة وكشوفات الطلاب لجهازك.',
        style: TextStyle(fontSize: 13),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
          onPressed: () async {
            Navigator.pop(ctx);
            if (Platform.isAndroid) {
              if (await Permission.manageExternalStorage.status.isDenied) {
                await Permission.manageExternalStorage.request();
              }
              await Permission.storage.request();
            }
          },
          child: const Text('منح إذن التخزين', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  // 2. طلب إذن الكاميرا مع شرح توضيحي
  if (context.mounted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.camera_alt, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('إذن الكاميرا (تصحيح OMR)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
      content: const Text(
        'يحتاج التطبيق لصلاحية الكاميرا لمسح وتصحيح نماذج إجابة الطلاب المؤتمتة (ورقة التظليل) وقراءة النتائج آلياً.',
        style: TextStyle(fontSize: 13),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
          onPressed: () async {
            Navigator.pop(ctx);
            await Permission.camera.request();
          },
          child: const Text('منح إذن الكاميرا', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  }

  // انتهاء الإعداد والانتقال
  onFinished();
}
