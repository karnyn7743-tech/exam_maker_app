import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/activation_service.dart';
import 'home_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  String _deviceId = 'جاري القراءة...';
  final _keyController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  int _remainingDays = 0;
  bool _isTrialNow = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceAndStatus();
  }

  Future<void> _loadDeviceAndStatus() async {
    final id = await ActivationService.getDeviceId();
    final status = await ActivationService.getLicenseStatus();
    final remaining = await ActivationService.getRemainingTrialDays();

    setState(() {
      _deviceId = id;
      _isLoading = false;
      _isTrialNow = (status == LicenseStatus.trial);
      _remainingDays = remaining;
    });
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال مفتاح التنشيط أو التجربة');
      return;
    }

    final status = await ActivationService.applyKey(key);
    if (!mounted) return;

    if (status == LicenseStatus.full) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تنشيط النسخة الكاملة بنجاح مدى الحياة! أهلاً بك.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else if (status == LicenseStatus.trial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل النسخة التجريبية بنجاح (صالحة لمدة شهر كامل - 30 يوماً).'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _errorMessage = 'مفتاح غير صحيح أو غير مخصص لهذا الجهاز';
      });
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رمز الجهاز. أرسله للمطور لاستلام كود التجربة أو التفعيل.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.security, size: 58, color: Color(0xFF1E3A8A)),
                  const SizedBox(height: 12),
                  const Text(
                    'تنشيط صانع الاختبارات والأتمتة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'للحصول على كود تجربة مجاني لمدة شهر أو مفتاح الترخيص الدائم، أرسل رمز جهازك الظاهر بالأسفل إلى المطور.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  // شريط توضيحي بالأيام المتبقية في حال كان الترخيص التجريبي سارياً
                  if (_isTrialNow && _remainingDays > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer_outlined, size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Text(
                            'أنت حالياً في الفترة التجريبية: متبقي لديك $_remainingDays يوماً',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 26),

                  const Text(
                    'رمز الجهاز الخاص بك (Device ID):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _deviceId,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            fontFamily: 'monospace',
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20, color: Color(0xFF1E3A8A)),
                          tooltip: 'نسخ الرمز',
                          onPressed: _copyDeviceId,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  TextField(
                    controller: _keyController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'أدخل مفتاح التنشيط أو كود التجربة',
                      hintText: 'TR-XXXX-XXXX-XXXX أو FL-XXXX-...',
                      errorText: _errorMessage,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key, color: Color(0xFF1E3A8A)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.verified, color: Colors.white),
                    label: const Text(
                      'تأكيد الدخول والتفعيل',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isLoading ? null : _handleActivation,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
