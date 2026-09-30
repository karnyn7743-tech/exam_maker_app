import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../services/exam_storage_service.dart';

Future<bool> showSaveChoiceDialog({
  required BuildContext context,
  required ExamModel currentExam,
  required bool isNewExam,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
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
      title: const Text('خيارات الحفظ', style: TextStyle(fontWeight: FontWeight.bold)),
      content: const Text(
        'هل ترغب بالحفظ في نفس الملف الحالي أم إنشاء ملف جديد وحفظه باسم مختلف؟',
        style: TextStyle(fontSize: 15),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('حفظ لنفس الملف'),
          onPressed: () => Navigator.pop(ctx, 'SAME_FILE'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.save_as),
          label: const Text('حفظ باسم آخر'),
          onPressed: () => Navigator.pop(ctx, 'SAVE_AS'),
        ),
      ],
    ),
  );

  if (choice == 'SAME_FILE') {
    currentExam.updatedAt = DateTime.now();
    await ExamStorageService.saveOrUpdateExam(currentExam);
    onPerformSave(currentExam);
    return true;
  } else if (choice == 'SAVE_AS') {
    if (!context.mounted) return false;
    return await showSaveAsDialog(
      context: context,
      examToSave: currentExam,
      onPerformSave: onPerformSave,
    );
  }

  return false;
}

Future<bool> showSaveAsDialog({
  required BuildContext context,
  required ExamModel examToSave,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
  final nameController = TextEditingController(
    text: '${examToSave.fileName}_نسخة',
  );

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حفظ باسم جديد'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(
          labelText: 'اسم ملف الاختبار',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
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

  if (shouldSave == true) {
    final duplicatedExam = examToSave.copyWith(
      newId: const Uuid().v4(),
      newFileName: nameController.text.trim(),
    );

    await ExamStorageService.saveOrUpdateExam(duplicatedExam);
    onPerformSave(duplicatedExam);
    return true;
  }

  return false;
}
