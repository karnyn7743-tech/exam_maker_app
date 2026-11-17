import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// إخفاء لوحة المفاتيح قبل فتح أي نافذة نظام للأذونات.
Future<void> _hideKeyboardBeforePermission(BuildContext context) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

/// طلب صلاحية التخزين المناسبة لإصدار Android.
/// Android 11+ يستخدم صفحة الوصول الخاص لإدارة جميع الملفات؛
/// Android 10 وما دونه يستخدم نافذة إذن التخزين المعتادة.
Future<void> requestStoragePermissionIfNeeded() async {
  if (!Platform.isAndroid) return;

  final androidInfo = await DeviceInfoPlugin().androidInfo;
  if (androidInfo.version.sdkInt >= 30) {
    final status = await Permission.manageExternalStorage.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.manageExternalStorage.request();
    }
  } else {
    final status = await Permission.storage.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.storage.request();
    }
  }
}

/// طلب إذن الكاميرا من Android مباشرة دون نافذة شرح مخصصة.
/// لا يعاد الطلب إذا كان ممنوحاً أو رُفض نهائياً.
Future<void> requestCameraPermissionIfNeeded(BuildContext context) async {
  if (!Platform.isAndroid || !context.mounted) return;

  final status = await Permission.camera.status;
  if (status.isGranted || status.isPermanentlyDenied || status.isRestricted) {
    return;
  }

  await _hideKeyboardBeforePermission(context);
  if (!context.mounted) return;
  await Permission.camera.request();
}

/// تنفيذ طلبات الأذونات بالتتابع ثم متابعة الانتقال إلى الشاشة الرئيسية.
Future<void> requestAppPermissions(
  BuildContext context,
  VoidCallback onFinished,
) async {
  if (!Platform.isAndroid) {
    if (context.mounted) onFinished();
    return;
  }

  await _hideKeyboardBeforePermission(context);
  if (!context.mounted) return;

  await requestStoragePermissionIfNeeded();
  if (!context.mounted) return;

  await requestCameraPermissionIfNeeded(context);
  if (context.mounted) onFinished();
}
