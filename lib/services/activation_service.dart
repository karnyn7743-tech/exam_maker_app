import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full }

class ActivationService {
  static const String _secretSalt = 'EXAM_MAKER_SECURE_SALT_2026_@ALBAETHEE';
  static const String _prefLicenseStatus = 'license_status'; // 'trial' أو 'full'
  static const String _prefKeyActivationCode = 'app_activation_code';
  static const String _prefTrialExamsCount = 'trial_exams_created_count';

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

  /// خوارزمية التحقق من المفتاح وتحديد نوعه (تجريبي أو دائم)
  static LicenseStatus verifyKey(String enteredKey, String deviceId) {
    final cleanDevice = deviceId.replaceAll('-', '').trim().toUpperCase();
    final cleanKey = enteredKey.trim().toUpperCase();

    // 1. فحص هل هو مفتاح كامل دائم
    final fullCombined = '$cleanDevice:FULL:$_secretSalt';
    final fullHash = sha256.convert(utf8.encode(fullCombined)).toString().toUpperCase();
    final expectedFullKey = 'FL-${fullHash.substring(0, 4)}-${fullHash.substring(4, 8)}-${fullHash.substring(8, 12)}';

    if (cleanKey == expectedFullKey) {
      return LicenseStatus.full;
    }

    // 2. فحص هل هو مفتاح تجريبي مصرح به (لاختبار واحد)
    final trialCombined = '$cleanDevice:TRIAL:$_secretSalt';
    final trialHash = sha256.convert(utf8.encode(trialCombined)).toString().toUpperCase();
    final expectedTrialKey = 'TR-${trialHash.substring(0, 4)}-${trialHash.substring(4, 8)}-${trialHash.substring(8, 12)}';

    if (cleanKey == expectedTrialKey) {
      return LicenseStatus.trial;
    }

    return LicenseStatus.locked;
  }

  /// التحقق من حالة الترخيص الحالية للجهاز
  static Future<LicenseStatus> getLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefKeyActivationCode);
    if (savedKey == null || savedKey.isEmpty) return LicenseStatus.locked;

    final currentDeviceId = await getDeviceId();
    final status = verifyKey(savedKey, currentDeviceId);

    // إذا كان مفتاحاً تجريبياً، نتأكد هل استهلك اختباره الوحيد
    if (status == LicenseStatus.trial) {
      final count = prefs.getInt(_prefTrialExamsCount) ?? 0;
      if (count >= 1) {
        return LicenseStatus.locked; // انتهت التجربة
      }
    }

    return status;
  }

  /// تسجيل استهلاك الاختبار التجريبي
  static Future<void> incrementTrialCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefTrialExamsCount) ?? 0;
    await prefs.setInt(_prefTrialExamsCount, current + 1);
  }

  /// تفعيل المفتاح المدخل
  static Future<LicenseStatus> applyKey(String enteredKey) async {
    final currentDeviceId = await getDeviceId();
    final status = verifyKey(enteredKey, currentDeviceId);

    if (status != LicenseStatus.locked) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyActivationCode, enteredKey.trim().toUpperCase());
      await prefs.setString(_prefLicenseStatus, status == LicenseStatus.full ? 'full' : 'trial');
    }

    return status;
  }
}
