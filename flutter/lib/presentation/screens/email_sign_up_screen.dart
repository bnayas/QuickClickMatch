import 'package:flutter/material.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart'; // Keep this import for CognitoClientException fallback
import 'package:quick_click_match/services/localization_service.dart';

class EmailSignUpScreen extends StatefulWidget {
  const EmailSignUpScreen({super.key});

  @override
  State<EmailSignUpScreen> createState() => _EmailSignUpScreenState();
}

class _EmailSignUpScreenState extends State<EmailSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final l10n = LocalizationService.instance;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final primaryUsername = await AuthService.signUpWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
        _displayNameController.text.trim(),
      );

      if (!mounted) return;
      // Success: Navigate to sign-in screen
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('emailSignUp.snackbar.success'))),
      );
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.emailConfirmation,
        arguments: primaryUsername,
      );
    } on CognitoUsernameExistsException {
      if (mounted) {
        // Handle: Email already exists (AliasExistsException in Cognito)
        setState(() {
          _errorMessage = l10n.t('emailSignUp.error.accountExists');
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.emailSignIn,
          arguments: _emailController.text.trim(),
        );
      }
    } on CognitoDisplayNameConflictException catch (e) {
      // Handle: Display name (primary username) is already taken (UsernameExistsException in Cognito)
      setState(() {
        _errorMessage = e.message;
      });
    } on CognitoClientException catch (e) {
      // Handle other specific Cognito errors (like InvalidParameterException for bad password policy)
      setState(() {
        _errorMessage = l10n.format('emailSignUp.error.signUpFailed', {
          'reason': e.message ?? '',
        });
      });
    } catch (e) {
      // Generic catch-all for other errors
      setState(() {
        _errorMessage = l10n.format('emailSignUp.error.unexpected', {
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
        title: Text(l10n.t('emailSignUp.title')),
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
                  l10n.t('emailSignUp.header'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 32),

                // Display Name Field
                TextFormField(
                  controller: _displayNameController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: l10n.t('emailSignUp.displayNameLabel'),
                    hintText: l10n.t('emailSignUp.displayNameHint'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.t('emailSignUp.displayNameError.empty');
                    }
                    if (value.length < 3) {
                      return l10n.t('emailSignUp.displayNameError.length');
                    }
                    if (value.contains(RegExp(r'[^a-zA-Z0-9]'))) {
                    }
                    if (value.contains('@')) {
                      return l10n.t('emailSignUp.displayNameError.atSymbol');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.t('emailSignUp.emailLabel'),
                    hintText: l10n.t('emailSignUp.emailLabel'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty ||
                        !trimmed.contains('@') ||
                        !trimmed.contains('.')) {
                      return l10n.t('emailSignUp.emailError');
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
                    labelText: l10n.t('emailSignUp.passwordLabel'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return l10n.t('emailSignUp.passwordError');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password Field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('emailSignUp.confirmPasswordLabel'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return l10n.t('emailSignUp.confirmPasswordError');
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

                // Sign Up Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          l10n.t('emailSignUp.button'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),

                // Link to Sign In
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                        context, AppRoutes.emailSignIn);
                  },
                  child: Text(l10n.t('emailSignUp.linkSignIn')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
