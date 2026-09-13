import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const TensorSightApp());
}

class TensorSightApp extends StatelessWidget {
  const TensorSightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TensorSight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
       
      ),
      home: const SplashScreen(),
    );
  }
}
