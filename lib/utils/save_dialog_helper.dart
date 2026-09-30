/// دالة إدارة قرار الحفظ: (نفس الملف أم حفظ باسم)
Future<bool> showSaveChoiceDialog({
  required BuildContext context,
  required ExamModel currentExam,
  required bool isNewExam,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
  // إذا كان الاختبار جديداً كلياً، نطلب الاسم مباشرة
  if (isNewExam) {
    return await _showSaveAsDialog(
      context: context,
      examToSave: currentExam,
      onPerformSave: onPerformSave,
    );
  }

  // إذا كان الاختبار موجوداً مسبقاً، نسأل المعلم عن نوع الحفظ
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('خيارات الحفظ', style: TextStyle(fontWeight: FontWeight.bold)),
      content: const Text(
        'هل تريد حفظ التعديلات على نفس الملف السابق أم تريد الحفظ باسم آخر (نسخة جديدة)؟',
        style: TextStyle(fontSize: 15),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // الخيار الأول: الحفظ لنفس الملف
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('حفظ لنفس الملف'),
          onPressed: () => Navigator.pop(ctx, 'SAME_FILE'),
        ),
        const SizedBox(width: 8),
        // الخيار الثاني: حفظ باسم جديد
        OutlinedButton.icon(
          icon: const Icon(Icons.save_as),
          label: const Text('حفظ باسم آخر'),
          onPressed: () => Navigator.pop(ctx, 'SAVE_AS'),
        ),
      ],
    ),
  );

  if (choice == 'SAME_FILE') {
    // تحديث نفس الاختبار بنفس المعرف والاسم
    await ExamStorageService.saveOrUpdateExam(currentExam);
    onPerformSave(currentExam);
    return true;
  } else if (choice == 'SAVE_AS') {
    // فتح مربع إدخال الاسم الجديد دون المساس بالملف السابق
    return await _showSaveAsDialog(
      context: context,
      examToSave: currentExam,
      onPerformSave: onPerformSave,
    );
  }

  return false;
}

/// نافذة إدخال الاسم الجديد عند اختيار (حفظ باسم)
Future<bool> _showSaveAsDialog({
  required BuildContext context,
  required ExamModel examToSave,
  required Function(ExamModel updatedExam) onPerformSave,
}) async {
  final nameController = TextEditingController(
    text: '${examToSave.header.subject}_${examToSave.header.grade}'.trim().replaceAll(' ', '_'),
  );

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حفظ باسم جديد'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'اسم الملف الجديد',
          suffixText: '.docx',
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
    // استنساخ كائن جديد بمعرف واسم جديدين، وإبقاء الأصلي دون تعديل
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
