import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'utils/app_info.dart';
import 'config/purchases_config.dart';
import 'state/push.dart';
import 'state/reminders.dart';
import 'state/subscriptions.dart';
import 'state/well_backend.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Null until the ManifestWell Firebase project is configured; the app then
  // runs local-only with the seed wishes.
  await AppInfo.init();
  final backend = await FirestoreWellBackend.tryCreate();
  final state = await AppState.load(
    backend: backend,
    reminders: LocalReminders(),
    // Pushes need Firebase; without it (no config yet) there is nothing to
    // register with, so the app simply runs without them.
    push: backend == null ? const NoPush() : FirebasePush(),
    // Without a RevenueCat key this is a stand-in and the paywall says so.
    subscriptions: await RevenueCatSubscriptions.tryCreate(apiKey: PurchasesConfig.apiKey) ??
        const NoSubscriptions(),
  );
  runApp(ManifestWellApp(state: state));
}

class ManifestWellApp extends StatelessWidget {
  final AppState state;
  const ManifestWellApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'ManifestWell',
        debugShowCheckedModeBanner: false,
        theme: MW.theme(),
        home: Consumer<AppState>(
          builder: (_, s, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: s.onboarded
                ? const HomeShell(key: ValueKey('home'))
                : const OnboardingScreen(key: ValueKey('onboarding')),
          ),
        ),
      ),
    );
  }
}
