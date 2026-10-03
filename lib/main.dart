import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'providers/providers.dart';
import 'router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check: Play Integrity / App Attest in release; the debug provider prints a token to
  // logcat in debug builds — register it in Firebase Console → App Check → Manage debug tokens.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    debugPrint('[firebase] App Check not started: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  installErrorHandlers();

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const BudgetMateApp(),
  ));
}

class BudgetMateApp extends ConsumerWidget {
  const BudgetMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the public profile fresh on every sign-in (web: saveUser in onAuthStateChanged)
    ref.listen(authStateProvider, (prev, next) {
      final user = next.value;
      if (user != null && prev?.value?.uid != user.uid) {
        ref.read(firestoreServiceProvider).saveUser(user).catchError((Object e) => debugPrint('Error saving user: $e'));
      }
    });

    return MaterialApp.router(
      title: 'BudgetMate',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppColors.light),
      darkTheme: buildTheme(AppColors.dark),
      themeMode: ref.watch(themeProvider),
      themeAnimationDuration: const Duration(milliseconds: 300),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
