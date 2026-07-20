import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

// ============================================================================
// GLOBAL HELPERS & MODELS
// ============================================================================

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const BlackPinApp());
}














// ============================================================================
// ROOT APPLICATION
// ============================================================================

class BlackPinApp extends StatelessWidget {
  const BlackPinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false, 
          title: 'BLACKPIN', 
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
            scaffoldBackgroundColor: Colors.grey.shade50, appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: Colors.black, selectedItemColor: Colors.white, unselectedItemColor: Colors.white54),
          ),
          darkTheme: ThemeData(
            useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark, surface: const Color(0xFF1A1A1A), onSurface: Colors.white),
            scaffoldBackgroundColor: Colors.black, appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0), dividerColor: Colors.grey.shade800,
            bottomNavigationBarTheme: BottomNavigationBarThemeData(backgroundColor: const Color(0xFF1A1A1A), selectedItemColor: Colors.white, unselectedItemColor: Colors.grey.shade600),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

// ============================================================================
// REUSABLE CAFE CARD WIDGET
// ============================================================================

// ============================================================================
// HOME SCREEN
// ============================================================================



// ============================================================================
// FILTERED CAFE LIST SCREEN
// ============================================================================


// ============================================================================
// SUGGESTION BOTTOM SHEET
// ============================================================================


// ============================================================================
// PASSPORT STAMPS SCREEN
// ============================================================================




// ============================================================================
// ALL PIN NOTES SCREEN
// ============================================================================




// ============================================================================
// QUICK NOTE BOTTOM SHEET
// ============================================================================


// ============================================================================
// CAFE DETAIL SCREEN
// ============================================================================

