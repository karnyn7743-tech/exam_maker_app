import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full }

class ActivationService {
  static const String _secretSalt = 'EXAM_MAKER_SECURE_SALT_2026_@ALBAETHEE';
  static const String _prefLicenseStatus = 'license_status';
  static const String _prefKeyActivationCode = 'app_activation_code';
  static const String _prefTrialExamsCount = 'trial_exams_created_count';
  static const String _prefTrialStartDate = 'trial_start_timestamp'; // تسجيل بداية التجربة
  static const int trialDaysDuration = 30; // مدة التجربة: 30 يوماً (شهر كامل)

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

  /// خوارزمية التحقق من المفتاح وتحديد نوعه
  static LicenseStatus verifyKey(String enteredKey, String deviceId) {
    final cleanDevice = deviceId.replaceAll('-', '').trim().toUpperCase();
    final cleanKey = enteredKey.trim().toUpperCase();

    // 1. فحص المفتاح الكامل الدائم
    final fullCombined = '$cleanDevice:FULL:$_secretSalt';
    final fullHash = sha256.convert(utf8.encode(fullCombined)).toString().toUpperCase();
    final expectedFullKey = 'FL-${fullHash.substring(0, 4)}-${fullHash.substring(4, 8)}-${fullHash.substring(8, 12)}';

    if (cleanKey == expectedFullKey) {
      return LicenseStatus.full;
    }

    // 2. فحص كود التجربة المصرح به
    final trialCombined = '$cleanDevice:TRIAL:$_secretSalt';
    final trialHash = sha256.convert(utf8.encode(trialCombined)).toString().toUpperCase();
    final expectedTrialKey = 'TR-${trialHash.substring(0, 4)}-${trialHash.substring(4, 8)}-${trialHash.substring(8, 12)}';

    if (cleanKey == expectedTrialKey) {
      return LicenseStatus.trial;
    }

    return LicenseStatus.locked;
  }

  /// فحص هل التطبيق مفعل تفعيلاً كاملاً
  static Future<bool> isActivated() async {
    final status = await getLicenseStatus();
    return status == LicenseStatus.full;
  }

  /// جلب عدد الاختبارات المنشأة أثناء الفترة التجريبية
  static Future<int> getTrialCreatedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefTrialExamsCount) ?? 0;
  }

  /// حساب عدد الأيام المتبقية في الفترة التجريبية (30 يوماً)
  static Future<int> getRemainingTrialDays() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefKeyActivationCode);
    if (savedKey == null || savedKey.isEmpty) return 0;

    final currentDeviceId = await getDeviceId();
    final status = verifyKey(savedKey, currentDeviceId);

    if (status == LicenseStatus.full) return 999; // ترخيص كامل دائم

    if (status == LicenseStatus.trial) {
      final startMillis = prefs.getInt(_prefTrialStartDate);
      if (startMillis == null) return trialDaysDuration;

      final startDate = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final daysPassed = DateTime.now().difference(startDate).inDays;
      final remaining = trialDaysDuration - daysPassed;
      return remaining > 0 ? remaining : 0;
    }

    return 0;
  }

  /// التحقق من حالة الترخيص الحالية (فحص انقضاء مدة الـ 30 يوماً للتجربة)
  static Future<LicenseStatus> getLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefKeyActivationCode);
    if (savedKey == null || savedKey.isEmpty) return LicenseStatus.locked;

    final currentDeviceId = await getDeviceId();
    final status = verifyKey(savedKey, currentDeviceId);

    // إذا كان الترخيص تجريبياً، يتم فحص هل انتهت مدة الشهر (30 يوماً)
    if (status == LicenseStatus.trial) {
      int? startMillis = prefs.getInt(_prefTrialStartDate);
      final now = DateTime.now();

      if (startMillis == null) {
        // تسجيل بداية التجربة عند أول فحص للترخيص التجريبي
        await prefs.setInt(_prefTrialStartDate, now.millisecondsSinceEpoch);
        return LicenseStatus.trial;
      }

      final startDate = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final daysPassed = now.difference(startDate).inDays;

      // إذا تجاوزت المدة 30 يوماً، يقفل التطبيق
      if (daysPassed >= trialDaysDuration) {
        return LicenseStatus.locked;
      }
    }

    return status;
  }

  /// تسجيل استهلاك الاختبار التجريبي (لأغراض الإحصاء ومتابعة المعلم دون قفل التطبيق)
  static Future<void> incrementTrialCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_prefTrialExamsCount) ?? 0;
    await prefs.setInt(_prefTrialExamsCount, current + 1);
  }

  /// تفعيل المفتاح المدخل وبدء عداد الـ 30 يوماً في حال كان المفتاح تجريبياً
  static Future<LicenseStatus> applyKey(String enteredKey) async {
    final currentDeviceId = await getDeviceId();
    final status = verifyKey(enteredKey, currentDeviceId);

    if (status != LicenseStatus.locked) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyActivationCode, enteredKey.trim().toUpperCase());
      await prefs.setString(_prefLicenseStatus, status == LicenseStatus.full ? 'full' : 'trial');

      // عند إدخال مفتاح تجريبي، نسجل لحظة البداية لبدء حساب الـ 30 يوماً
      if (status == LicenseStatus.trial) {
        await prefs.setInt(_prefTrialStartDate, DateTime.now().millisecondsSinceEpoch);
      }
    }

    return status;
  }
}
