import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quoridor/flame/services/local_storage.dart';

import '/flame/pages/menu_page.dart';
import '/theme.dart';
import 'firebase_options.dart';
import 'flame/services/localizations.dart';
import 'flame/services/sounds.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameSounds.preload();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await localization.ensureInitialized();
  await CacheHelper.init();
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory((await getTemporaryDirectory()).path),
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const QuoridorApp());
}

class QuoridorApp extends StatefulWidget {
  const QuoridorApp({super.key});

  @override
  State<QuoridorApp> createState() => _QuoridorAppState();
}

class _QuoridorAppState extends State<QuoridorApp> {
  @override
  void initState() {
    localization.init(
      mapLocales: [
        const MapLocale('en', AppLocale.en),
        const MapLocale('ar', AppLocale.ar),
      ],
      initLanguageCode: 'en',
    );
    localization.onTranslatedLanguage = _onTranslatedLanguage;
    super.initState();
  }

  void _onTranslatedLanguage(Locale? locale) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: isDarkModeNotifier,
      builder: (context, value, child) {
        CacheHelper.saveData(key: "isDark", value: value);

        return MaterialApp(
          title: AppLocale.title.getString(context),
          supportedLocales: localization.supportedLocales,
          localizationsDelegates: localization.localizationsDelegates,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: value ? ThemeMode.dark : ThemeMode.light,
          home: const MenuPage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
