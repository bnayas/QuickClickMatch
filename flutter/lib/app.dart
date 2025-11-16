import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'presentation/screens/menu_screen.dart';
import 'presentation/screens/game_screen.dart';
import 'presentation/screens/deck_choice_screen.dart';
import 'presentation/screens/debug_edit_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/lobby/lobby_screen.dart';
import 'presentation/screens/email_sign_in_screen.dart';
import 'presentation/screens/email_sign_up_screen.dart';
import 'presentation/screens/email_confirmation_screen.dart';
import 'presentation/screens/forgot_password_screen.dart';
import 'package:quick_click_match/infra/config_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:quick_click_match/themes/app_theme.dart';
import 'package:quick_click_match/services/localization_service.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService.instance;
    return AnimatedBuilder(
      animation: localization,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: localization.t('app.titlePlain'),
          theme: AppTheme.lightTheme,
          locale: Locale(localization.currentLanguageCode),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: localization.supportedLocales,
          builder: (context, child) => Directionality(
            textDirection: localization.textDirection,
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: AppRoutes.menu,
          routes: {
            AppRoutes.menu: (context) => MenuScreen(),
            AppRoutes.game: (context) => const GameScreen(),
            AppRoutes.deck_choice: (context) => DeckChoiceScreen(),
            if (!kReleaseMode)
              AppRoutes.debug_edit: (context) => const DebugEditScreen(),
            AppRoutes.settings: (context) =>
                SettingsPage(config: ConfigService()),
            AppRoutes.auth: (context) => const AuthScreen(),
            AppRoutes.lobby: (context) => const LobbyScreen(),
            AppRoutes.emailSignUp: (context) => const EmailSignUpScreen(),
            AppRoutes.emailSignIn: (context) => const EmailSignInScreen(),
            AppRoutes.emailConfirmation: (context) =>
                const EmailConfirmationScreen(),
            AppRoutes.forgotPassword: (context) => const ForgotPasswordScreen(),
          },
        );
      },
    );
  }
}
