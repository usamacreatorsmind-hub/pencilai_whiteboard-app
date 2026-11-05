import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'features/whiteboard/state/whiteboard_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/whiteboard/screens/whiteboard_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WhiteboardProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
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
      title: 'PencilAi App',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
      home: const WhiteboardScreen(),
    );
  }
}



// 1. Slider importing message: write only importing slides. No need to show sliders number. Done
// 2. Erasing from palm is lacking.Done
// 3. Scale (Ruler) can be moved from any point. Now,it is doing on press of a button. Done
// 4. Image can be dragged from Google and dropped on board. Done
// 5. Add a selective shape into tool like  if we draw a circle ,it should be auto formatted like ⭕.
// 6. Quick quiz: first time it showing correct but second time it is coming wrong. Done
// 7. Touch point should be multiple like 40,60 etc. Done
// 8. Ai button which is right bottom corner should be shifted and placed anywehere. Done
// 9. Add text pen.
// 10. Pen color image showing blur. Done
// 11. PPT slider is starting from 1 in case of selected any slider number. It should be hold. Done