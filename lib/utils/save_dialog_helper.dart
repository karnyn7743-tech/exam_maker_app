
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/exam_models.dart';
import '../services/exam_storage_service.dart';

// ============================================================
// نافذة خيارات الحفظ
// ============================================================

Future<bool> showSaveChoiceDialog({
  required BuildContext context,
  required ExamModel currentExam,
  required bool isNewExam,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
  // الاختبار الجديد: الانتقال مباشرة إلى حفظ باسم.
  if (isNewExam) {
    return await showSaveAsDialog(
      context: context,
      examToSave: currentExam,
      onPerformSave: onPerformSave,
    );
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        'خيارات الحفظ',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: const Text(
        'هل ترغب بالحفظ في نفس الملف الحالي أم إنشاء ملف جديد وحفظه باسم مختلف؟',
        style: TextStyle(
          fontSize: 15,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('حفظ لنفس الملف'),
          onPressed: () {
            Navigator.pop(ctx, 'SAME_FILE');
          },
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.save_as),
          label: const Text('حفظ باسم آخر'),
          onPressed: () {
            Navigator.pop(ctx, 'SAVE_AS');
          },
        ),
      ],
    ),
  );

  if (choice == 'SAME_FILE') {
    try {
      currentExam.updatedAt = DateTime.now();

      await ExamStorageService.saveOrUpdateExam(
        currentExam,
      );

      onPerformSave(currentExam);

      return true;
    } catch (e) {
      if (context.mounted) {
        _showSaveError(context, e);
      }

      return false;
    }
  }

  if (choice == 'SAVE_AS') {
    if (!context.mounted) {
      return false;
    }

    return await showSaveAsDialog(
      context: context,
      examToSave: currentExam,
      onPerformSave: onPerformSave,
    );
  }

  return false;
}

// ============================================================
// نافذة حفظ باسم جديد
// ============================================================

Future<bool> showSaveAsDialog({
  required BuildContext context,
  required ExamModel examToSave,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
  final nameController = TextEditingController(
    text: examToSave.fileName.trim().isNotEmpty
        ? '${examToSave.fileName}_نسخة'
        : 'اختبار_جديد',
  );

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        'حفظ باسم جديد',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: TextField(
        controller: nameController,
        autofocus: true,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          labelText: 'اسم ملف الاختبار',
          hintText: 'أدخل اسماً للملف',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx, false);
          },
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (nameController.text.trim().isNotEmpty) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('تأكيد الحفظ'),
        ),
      ],
    ),
  );

  if (shouldSave != true) {
    nameController.dispose();
    return false;
  }

  final requestedName = nameController.text.trim();

  nameController.dispose();

  if (!context.mounted) {
    return false;
  }

  try {
    // إنشاء نسخة مستقلة تماماً عن الاختبار الأصلي.
    //
    // newId:
    // معرّف جديد حتى لا تستبدل النسخة الأصلية في الأرشيف.
    //
    // newFileName:
    // اسم جديد للنسخة.
    //
    // clearFilePath:
    // إزالة مسار الملف الأصلي حتى لا تتم الكتابة فوقه.
    final duplicatedExam = examToSave.copyWith(
      newId: const Uuid().v4(),
      newFileName: requestedName,
      clearFilePath: true,
    );

    duplicatedExam.updatedAt = DateTime.now();

    // الحفظ الفعلي في ملف مستقل.
    await ExamStorageService.saveOrUpdateExam(
      duplicatedExam,
    );

    // تحديث المحرر بالنسخة الجديدة بعد نجاح الحفظ فقط.
    onPerformSave(duplicatedExam);

    return true;
  } catch (e) {
    if (context.mounted) {
      _showSaveError(context, e);
    }

    return false;
  }
}

// ============================================================
// عرض أخطاء الحفظ
// ============================================================

void _showSaveError(
  BuildContext context,
  Object error,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'تعذر حفظ الاختبار: $error',
        textDirection: TextDirection.rtl,
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ),
  );
}
