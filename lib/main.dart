import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'features/whiteboard/state/whiteboard_provider.dart';
import 'features/whiteboard/screens/whiteboard_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set immersive mode to hide navigation and status bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => WhiteboardProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PencilAi EduAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WhiteboardScreen(),
    );
  }
}
