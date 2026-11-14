import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'services/native_player.dart';
import 'services/settings_repository.dart';
import 'viewmodels/player_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'views/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    // Lets you inspect the page via chrome://inspect on your PC.
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlayerViewModel(NativePlayer())..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(SettingsRepository())..load(),
        ),
      ],
      child: const BgTubeApp(),
    ),
  );
}

class BgTubeApp extends StatelessWidget {
  const BgTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BgTube',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.red,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}