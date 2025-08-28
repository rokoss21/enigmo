import 'package:flutter/material.dart';
import 'screens/chat_list_screen.dart';
import 'screens/splash_screen.dart';
import 'services/app_lifecycle_service.dart';
import 'services/audio_call_service.dart';
import 'services/network_service.dart';
import 'services/crypto_engine.dart';
import 'services/call_notification_service.dart';
import 'services/incoming_call_handler.dart';

void main() {
  // Initialize Flutter binding
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up the lifecycle observer without tying it to a widget
  final lifecycleObserver = AppLifecycleObserver();
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  runApp(const AnogramApp());
}

/// A standalone observer to prevent widget rebuilds on lifecycle changes.
class AppLifecycleObserver with WidgetsBindingObserver {
  final AppLifecycleService _lifecycleService = AppLifecycleService();

  AppLifecycleObserver() {
    _lifecycleService.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleService.handleAppLifecycleChange(state);
  }
}

class AnogramApp extends StatefulWidget {
  const AnogramApp({super.key});

  @override
  State<AnogramApp> createState() => _AnogramAppState();
}

class _AnogramAppState extends State<AnogramApp> {
  late final AudioCallService _audioCallService;
  late final CallNotificationService _callNotificationService;

  @override
  void initState() {
    super.initState();
    // Initialize audio call services
    // In a real app, these would be properly injected
    final networkService = NetworkService(); // This would need proper initialization
    final cryptoEngine = CryptoEngine(); // This would need proper initialization
    _audioCallService = AudioCallService(networkService, cryptoEngine);
    _callNotificationService = CallNotificationService(_audioCallService);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme darkScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Colors.white,         // neutral accent
      onPrimary: Colors.black,
      secondary: Color(0xFF9AA4AF),  // mid gray
      onSecondary: Colors.black,
      surface: Color(0xFF0F1419),
      onSurface: Color(0xFFE7ECF0),
      surfaceVariant: Color(0xFF1A222B),
      onSurfaceVariant: Color(0xFFB2BDC6),
      outline: Color(0xFF2C3E50),
      error: Color(0xFFEF5350),
      onError: Colors.white,
    );

    final ThemeData theme = ThemeData(
      colorScheme: darkScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: darkScheme.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A222B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      dividerTheme: DividerThemeData(
        color: darkScheme.outline.withOpacity(0.5),
        thickness: 0.5,
        space: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkScheme.surfaceVariant,
        contentTextStyle: TextStyle(color: darkScheme.onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkScheme.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkScheme.outline.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkScheme.outline.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkScheme.primary, width: 1),
        ),
        hintStyle: TextStyle(color: darkScheme.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: darkScheme.onSurfaceVariant,
        textColor: darkScheme.onSurface,
        tileColor: Colors.transparent,
      ),
      iconTheme: IconThemeData(color: darkScheme.onSurfaceVariant),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: darkScheme.surfaceVariant,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardColor: darkScheme.surfaceVariant,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 15),
        bodySmall: TextStyle(fontSize: 13),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );

    return MaterialApp(
      title: 'Enigmo',
      theme: theme,
      home: SplashScreen(audioCallService: _audioCallService),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            IncomingCallHandler(audioCallService: _audioCallService),
          ],
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
