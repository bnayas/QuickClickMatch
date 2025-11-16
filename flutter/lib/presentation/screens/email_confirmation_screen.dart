import 'package:flutter/material.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';

class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({super.key});

  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _username; // Changed to reflect primary Cognito identifier
  bool _isResending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MODIFIED: Retrieve the primary username passed as an argument from the sign-up screen
    _username = ModalRoute.of(context)?.settings.arguments as String?;
    if (_username == null) {
      // If no username is passed, show an error.
      _errorMessage = 'Error: No user identifier provided for confirmation.';
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (!_formKey.currentState!.validate() || _username == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Correctly call confirmRegistration using the primary username
      await AuthService.confirmRegistration(
        _username!,
        _codeController.text.trim(),
      );

      if (mounted) {
        // Success: User confirmed, navigate to sign-in screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Account successfully confirmed! You can now sign in.')),
        );
        // Take user back to settings and clear the stack so confirmation flow doesn't linger
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.settings,
          (route) => false,
        );
      }
    } on CognitoClientException catch (e) {
      // Handle "Already Confirmed" Error
      if (e.message != null &&
          e.message!.contains(
              'User cannot be confirmed Current status is: Confirmed')) {
        if (mounted) {
          // Treat as success and redirect to sign-in
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Account is already confirmed. Please sign in.')),
          );
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.settings,
            (route) => false,
          );
          return; // Exit the function successfully
        }
      }
      // Catch other confirmation errors (CodeMismatchException, ExpiredCodeException, etc.)
      setState(() {
        _errorMessage = 'Confirmation failed: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleResendCode() async {
    if (_username == null) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    // Use the exposed userPool getter to create a CognitoUser object for the resend operation, using the primary username
    final user = CognitoUser(_username!, AuthService.userPool);

    try {
      await user.resendConfirmationCode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('New confirmation code sent to your email.')),
        );
      }
    } on CognitoClientException catch (e) {
      setState(() {
        _errorMessage = 'Resend failed: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Account'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'Email Verification',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 16),
                // Adjusted text to be generic since we only pass the username to this screen
                const Text(
                  'A verification code was sent to the email address associated with your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),

                // Confirmation Code Field
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    hintText: 'Enter 6-digit code',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.length != 6 ||
                        int.tryParse(value) == null) {
                      return 'Please enter the 6-digit code';
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

                // Confirm Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleConfirm,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Confirm Account',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),

                // Resend Code Button
                TextButton(
                  onPressed:
                      _isResending || _isLoading ? null : _handleResendCode,
                  child: _isResending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Resend Code"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
