import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/activation_screen.dart';
import 'screens/home_screen.dart';
import 'services/activation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فحص حالة الترخيص: لا يمكن الدخول إلا بترخيص ساري (تجريبي أو دائم)
  final status = await ActivationService.getLicenseStatus();
  final bool isAllowed = (status == LicenseStatus.full || status == LicenseStatus.trial);

  runApp(ExamMakerApp(isInitialAccessGranted: isAllowed));
}

class ExamMakerApp extends StatelessWidget {
  final bool isInitialAccessGranted;

  const ExamMakerApp({
    super.key,
    required this.isInitialAccessGranted,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صانع الاختبارات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('ar', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: isInitialAccessGranted ? const HomeScreen() : const ActivationScreen(),
    );
  }
}
