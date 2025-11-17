import 'package:flutter/material.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_click_match/services/game_service.dart';
import 'package:quick_click_match/services/localization_service.dart';

class EmailSignInScreen extends StatefulWidget {
  const EmailSignInScreen({super.key});

  @override
  State<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

class _EmailSignInScreenState extends State<EmailSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  // 1. RENAMED: Use identifier to support both username/email
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  Future<String?> _askDisplayNamePreference(AuthCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    final currentName = prefs.getString('display_name');
    final candidate = credentials.displayName?.trim();
    final l10n = LocalizationService.instance;

    // If AWS provided no display name, fall back to existing without prompting.
    if (candidate == null || candidate.isEmpty) {
      return currentName;
    }

    // No local name yet – adopt AWS name automatically.
    if (currentName == null || currentName.isEmpty) {
      await prefs.setString('display_name', candidate);
      return candidate;
    }

    // Already the same – nothing to do.
    if (currentName == candidate) {
      return currentName;
    }

    if (!mounted) return currentName;

    final existingName = currentName;
    final newName = candidate;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('emailSignIn.dialog.updateDisplayName.title')),
        content: Text(l10n.format('emailSignIn.dialog.updateDisplayName.body',
            {'candidate': newName, 'current': existingName})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(l10n
                .format('emailSignIn.dialog.keep', {'current': existingName})),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'aws'),
            child: Text(
                l10n.format('emailSignIn.dialog.use', {'candidate': newName})),
          ),
        ],
      ),
    );

    if (choice == 'aws') {
      await prefs.setString('display_name', candidate);
      return candidate;
    }

    return existingName;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retrieve identifier (username or email) argument passed from confirmation screen
    final identifier = ModalRoute.of(context)?.settings.arguments as String?;
    if (identifier != null) {
      _identifierController.text = identifier;
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final l10n = LocalizationService.instance;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 2. CORRECTED CALL: Use the new function name and identifier controller
      final credentials = await AuthService.signInWithIdentifierPassword(
        _identifierController.text.trim(),
        _passwordController.text,
      );

      if (mounted && credentials != null) {
        final chosenName = await _askDisplayNamePreference(credentials);
        if (!mounted) return;
        final fallbackName =
            credentials.email.isNotEmpty ? credentials.email : credentials.id;
        final welcomeName =
            chosenName ?? credentials.displayName ?? fallbackName;
        // Success: Navigate to the home screen (or wherever the main app is)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.format('emailSignIn.snackbar.welcome', {
            'name': welcomeName,
          }))),
        );
        await GameService().disconnectMultiplayer();
        if (!mounted) return;
        Navigator.pop(context, true);
        Navigator.pop(context, true);
      }
    } on CognitoClientException catch (e) {
      setState(() {
        // This handles "Incorrect username or password" and "User is not confirmed"
        _errorMessage = l10n.format('emailSignIn.error.signInFailed', {
          'reason': e.message ?? '',
        });
      });
    } catch (e) {
      setState(() {
        _errorMessage = l10n.format('emailSignIn.error.unexpected', {
          'reason': e.toString(),
        });
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('emailSignIn.title')),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  l10n.t('emailSignIn.header'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 32),

                // Identifier Field (Username or Email)
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.t('emailSignIn.identifierLabel'),
                    hintText: l10n.t('emailSignIn.identifierHint'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.t('emailSignIn.identifierError');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('emailSignIn.passwordLabel'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.t('emailSignIn.passwordError');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Sign In Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          l10n.t('emailSignIn.button'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),

                // Forgot Password Link
                TextButton(
                  onPressed: () {
                    // Navigate to forgot password screen
                    Navigator.pushNamed(context, AppRoutes.forgotPassword);
                  },
                  child: Text(l10n.t('emailSignIn.forgotPassword')),
                ),

                // Link to Sign Up
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                        context, AppRoutes.emailSignUp);
                  },
                  child: Text(l10n.t('emailSignIn.noAccount')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
