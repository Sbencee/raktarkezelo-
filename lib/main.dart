import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // Ez kell a kIsWeb ellenőrzéshez!
import 'screens/home_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // PLATFORM FÜGGŐ FIREBASE INICIALIZÁLÁS
  if (kIsWeb) {
    // Ha weben (Chrome) futunk, most már a Te VALÓDI kulcsaidat használja:
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyB4lmsceBcI8fV5plm05eKUrQRGA4uA9lY",
        appId: "1:882471268847:web:ec75ad11faa65f29c9c61a",
        messagingSenderId: "882471268847",
        projectId: "raktarapp-24984",
        authDomain: "raktarapp-24984.firebaseapp.com", 
        storageBucket: "raktarapp-24984.firebasestorage.app",
      ),
    );
  } else {
    // Ha Mobilon (Android) futunk, továbbra is a google-services.json-t használja
    await Firebase.initializeApp();
  }
  
  runApp(const RaktarApp());
}

class RaktarApp extends StatelessWidget {
  const RaktarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Raktár Pro Cloud',
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.light),
          darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
          themeMode: mode,
          home: const HomeScreen(),
        );
      },
    );
  }
}