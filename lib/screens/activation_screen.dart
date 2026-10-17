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
  String _deviceId = 'جاري الجلب...';
  final _keyController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    final id = await ActivationService.getDeviceId();
    setState(() {
      _deviceId = id;
      _isLoading = false;
    });
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال مفتاح التنشيط');
      return;
    }

    final success = await ActivationService.activate(key);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تنشيط التطبيق بنجاح! أهلاً بك.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      setState(() {
        _errorMessage = 'مفتاح التنشيط غير صحيح أو غير مخصص لهذا الجهاز';
      });
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رمز الجهاز بنجاح. أرسله للمطور للحصول على التفعيل.'),
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
              constraints: const BoxConstraints(maxWidth: 450),
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
                  const Icon(Icons.security, size: 60, color: Color(0xFF1E3A8A)),
                  const SizedBox(height: 12),
                  const Text(
                    'تنشيط النسخة المرخصة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'هذا التطبيق محمي ومخصص للعمل على جهاز مصرح به فقط.\nأرسل رمز الجهاز أدناه للمطور لاستلام مفتاح التفعيل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 28),

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
                    style: const TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'أدخل مفتاح التنشيط هنا',
                      hintText: 'XXXX-XXXX-XXXX-XXXX',
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
                      'تأكيد وتفعيل التطبيق',
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
