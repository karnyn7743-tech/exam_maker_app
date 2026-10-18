import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/activation_screen.dart';
import 'screens/home_screen.dart';
import 'services/activation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فحص هل مسموح له بالدخول (مفعل بالكامل أو متبقي له الاختبار التجريبي)
  final bool canAccess = await ActivationService.canAccessApp();

  runApp(ExamMakerApp(initialAccessGranted: canAccess));
}

class ExamMakerApp extends StatelessWidget {
  final bool initialAccessGranted;

  const ExamMakerApp({
    super.key,
    required this.initialAccessGranted,
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
      home: initialAccessGranted ? const HomeScreen() : const ActivationScreen(),
    );
  }
}
