import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActivationService {
  // مفتاح سري خاص بك أنت فقط - لا تشاركه مع أحد
  static const String _secretSalt = 'EXAM_MAKER_SECURE_SALT_2026_@ALBAETHEE';
  static const String _prefKeyIsActivated = 'app_is_activated';
  static const String _prefKeyActivationCode = 'app_activation_code';

  /// استخراج المعرف الفريد للجهاز (Hardware / Android ID)
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId = 'UNKNOWN_DEVICE';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // id أو fingerprint أو hardware
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

    // تنظيف وتحويل المعرف إلى كود بسيط وسهل القراءة للمعلم (مثل: AB12-CD34-EF56)
    final hash = sha256.convert(utf8.encode(rawId)).toString().toUpperCase();
    return '${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}';
  }

  /// الخوارزمية التي تولد مفتاح التنشيط بناءً على رمز الجهاز
  /// (هذه الدالة تستخدمها أنت لمنح التراخيص)
  static String generateActivationKey(String deviceId) {
    final cleanDevice = deviceId.replaceAll('-', '').trim().toUpperCase();
    final combined = '$cleanDevice:$_secretSalt';
    final hash = sha256.convert(utf8.encode(combined)).toString().toUpperCase();

    // نخرج مفتاحاً مكوناً من 16 خانة مقسمة إلى 4 مجموعات (سهلة الكتابة)
    return '${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}-${hash.substring(12, 16)}';
  }

  /// التحقق هل التطبيق مفعل مسبقاً على هذا الجهاز
  static Future<bool> isActivated() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefKeyActivationCode);
    if (savedKey == null || savedKey.isEmpty) return false;

    final currentDeviceId = await getDeviceId();
    final expectedKey = generateActivationKey(currentDeviceId);

    // التحقق من صحة المفتاح المخزن مع الجهاز الحالي
    return savedKey.trim() == expectedKey.trim();
  }

  /// محاولة تفعيل التطبيق بالمفتاح المدخل
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
