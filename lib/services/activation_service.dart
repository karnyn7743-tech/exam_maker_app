import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActivationService {
  static const String _secretSalt = 'EXAM_MAKER_SECURE_SALT_2026_@ALBAETHEE';
  static const String _prefKeyIsActivated = 'app_is_activated';
  static const String _prefKeyActivationCode = 'app_activation_code';
  static const String _prefKeyCreatedExamsCount = 'trial_created_exams_count';

  /// استخراج المعرف الفريد للجهاز
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId = 'UNKNOWN_DEVICE';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id.isNotEmpty
            ? androidInfo.id
            : '${androidInfo.brand}_${androidInfo.model}_${androidInfo.fingerprint}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        rawId = windowsInfo.deviceId;
      }
    } catch (_) {
      rawId = 'FALLBACK_EXAM_DEVICE';
    }

    final hash = sha256.convert(utf8.encode(rawId)).toString().toUpperCase();
    return '${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}';
  }

  /// توليد مفتاح التنشيط
  static String generateActivationKey(String deviceId) {
    final cleanDevice = deviceId.replaceAll('-', '').trim().toUpperCase();
    final combined = '$cleanDevice:$_secretSalt';
    final hash = sha256.convert(utf8.encode(combined)).toString().toUpperCase();
    return '${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}-${hash.substring(12, 16)}';
  }

  /// التحقق هل التطبيق منشط برخصة كاملة
  static Future<bool> isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefKeyActivationCode);
    if (savedKey == null || savedKey.isEmpty) return false;

    final currentDeviceId = await getDeviceId();
    final expectedKey = generateActivationKey(currentDeviceId);
    return savedKey.trim() == expectedKey.trim();
  }

  /// جلب عدد الاختبارات المنشأة أثناء الفترة التجريبية
  static Future<int> getTrialCreatedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKeyCreatedExamsCount) ?? 0;
  }

  /// تسجيل استهلاك اختبار تجريبي جديد
  static Future<void> incrementTrialCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefKeyCreatedExamsCount) ?? 0;
    await prefs.setInt(_prefKeyCreatedExamsCount, current + 1);
  }

  /// فحص هل يُسمح له بفتح التطبيق
  /// (مسموح إذا كان مفعلاً، أو لم يستهلك بعد الاختبار التجريبي الوحيد)
  static Future<bool> canAccessApp() async {
    if (await isActivated()) return true;
    final count = await getTrialCreatedCount();
    return count < 1;
  }

  /// تفعيل التطبيق بالمفتاح المدخل
  static Future<bool> activate(String enteredKey) async {
    final currentDeviceId = await getDeviceId();
    final expectedKey = generateActivationKey(currentDeviceId);

    final cleanEntered = enteredKey.trim().toUpperCase();
    if (cleanEntered == expectedKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyIsActivated, true);
      await prefs.setString(_prefKeyActivationCode, cleanEntered);
      return true;
    }
    return false;
  }
}
