import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/theme.dart';

import 'firebase_options.dart';
import 'flame/services/audio_service.dart';
import 'flame/services/firebase_service.dart';
import 'flame/services/app_strings.dart';
import 'flame/services/identity_service.dart';
import 'flame/services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase only backs the optional save/resume feature, so startup must not
  // wait on it. Awaiting it here meant a blocked or very slow network left the
  // user staring at a white screen; now the game paints immediately and the
  // backend connects behind it, or stays disabled if it cannot.
  unawaited(_connectFirebase());

  // Settings decide the theme and the language, so they are read before the
  // first frame; everything else can warm up behind it.
  await SettingsService.instance.load();

  // Load the sound effects once for the whole app. Failures are handled
  // inside the service and simply leave the game silent.
  unawaited(AudioService.instance.initialize());

  runApp(const QuoridorApp());
}

Future<void> _connectFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));
    FirebaseService.markReady(available: true);

    // Claim a stable anonymous identity for this device. Online play needs an
    // identity that outlives a restart so a game can be rejoined; local play
    // never touches it, so a failure here costs nothing.
    await IdentityService.instance.ensureSignedIn();
  } catch (error) {
    FirebaseService.markReady(available: false);
    debugPrint('Firebase unavailable, continuing offline: $error');
  }
}

class QuoridorApp extends StatefulWidget {
  const QuoridorApp({super.key});

  @override
  State<QuoridorApp> createState() => _QuoridorAppState();
}

class _QuoridorAppState extends State<QuoridorApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Stop playback when the app goes to the background so no native
        // player is left holding the audio focus.
        unawaited(AudioService.instance.stopAll());
      case AppLifecycleState.detached:
        unawaited(AudioService.instance.dispose());
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: SettingsService.instance.locale,
      builder: (context, locale, _) {
        return ValueListenableBuilder(
          valueListenable: isDarkModeNotifier,
          builder: (context, value, child) {
            return MaterialApp(
              onGenerateTitle: (context) => context.l10n.appTitle,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: value ? ThemeMode.dark : ThemeMode.light,
              locale: locale,
              supportedLocales: SettingsService.supportedLocales,
              // Arabic needs these delegates for right-to-left layout and for
              // the framework's own strings. Without them the locale falls
              // back to English and the direction never flips.
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const GamePage(),
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
    );
  }
}
