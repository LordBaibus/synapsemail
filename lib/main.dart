import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'config.dart';
import 'services/api_service.dart';
import 'services/session_store.dart';
import 'screens/splash_screen.dart';


final apiService = ApiService(baseUrl: kApiBaseUrl);
final sessionStore = SessionStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(const EmailApp());
}
class EmailApp extends StatelessWidget {
  const EmailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SynapseMail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0B12),
      ),
      builder: (context, child) => AppGlassLayer(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}

class AppGlassLayer extends StatelessWidget {
  final Widget child;
  const AppGlassLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1C2E), Color(0xFF0B0B12)],
        ),
      ),
      child: AdaptiveLiquidGlassLayer(child: child),
    );
  }
}
