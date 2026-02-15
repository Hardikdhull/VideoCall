import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/video_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
        apiKey: "AIzaSyCNlLagLaX_zUHOeyaqUiemd-zKrDJ19Oc",
        authDomain: "videocall-c18db.firebaseapp.com",
        projectId: "videocall-c18db",
        storageBucket: "videocall-c18db.firebasestorage.app",
        messagingSenderId: "545209786002",
        appId: "1:545209786002:web:4cfefebd520b261702d04b"
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CognitiveLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF202124),
        useMaterial3: true,
      ),
      home: const VideoCallScreen(),
    );
  }
}