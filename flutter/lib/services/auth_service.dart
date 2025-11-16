import 'package:flutter/foundation.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/services/secure_credentials_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier._internal();
  static final AuthStateNotifier instance = AuthStateNotifier._internal();

  void notifyAuthChanged() => notifyListeners();
}

class _EnvConfig {
  static const String cognitoUserPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
    defaultValue: '',
  );

  static const String cognitoClientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
    defaultValue: '',
  );

  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: '',
  );
  static void validate() {
    final missing = <String>[];
    if (cognitoUserPoolId.isEmpty) {
      debugLog('WARNING: COGNITO_USER_POOL_ID not set');
      missing.add('COGNITO_USER_POOL_ID');
    }
    if (cognitoClientId.isEmpty) {
      debugLog('WARNING: COGNITO_CLIENT_ID not set');
      missing.add('COGNITO_CLIENT_ID');
    }
    if (awsRegion.isEmpty) {
      debugLog('WARNING: AWS_REGION not set');
      missing.add('AWS_REGION');
    }
    if (missing.isNotEmpty && kReleaseMode) {
      throw StateError(
        'Missing required environment variables: ${missing.join(', ')}. '
        'Provide them via --dart-define when building the app.',
      );
    }
  }
}

class AuthCredentials {
  final String cognitoIdToken;
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  AuthCredentials({
    required this.cognitoIdToken,
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}

// Custom Exception for email conflict (AliasExistsException in Cognito)
class CognitoUsernameExistsException implements Exception {
  final String message;
  const CognitoUsernameExistsException(this.message);
  @override
  String toString() => 'CognitoUsernameExistsException: $message';
}

// Custom Exception for display name conflict (UsernameExistsException in Cognito)
class CognitoDisplayNameConflictException implements Exception {
  final String message;
  const CognitoDisplayNameConflictException(this.message);
  @override
  String toString() => 'CognitoDisplayNameConflictException: $message';
}

class AuthService {
  // Initialize Cognito User Pool
  static final CognitoUserPool _userPool = CognitoUserPool(
    _EnvConfig.cognitoUserPoolId,
    _EnvConfig.cognitoClientId,
  );

  // Expose the User Pool for operations like resending confirmation code
  static CognitoUserPool get userPool => _userPool;

  static AuthCredentials? _currentAuthCredentials;
  static CognitoUser? _cognitoUser; // Track the current Cognito user session

  // Validate configuration on first use
  static void _ensureConfigured() {
    _EnvConfig.validate();
  }

  // --- COGNITO SIGN UP ---
  /// Returns the primary username (safeUsername) used by Cognito
  static Future<String> signUpWithEmailPassword(
      String email, String password, String displayName) async {
    _ensureConfigured();

    // 1. Create a safe, primary username from the display name.
    String safeUsername = displayName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '')
        .toLowerCase();

    if (safeUsername.isEmpty) {
      throw CognitoClientException('InvalidParameterException' +
          'Display name is required and must contain alphanumeric characters.');
    }

    // 2. Attributes for sign up (email is alias, name/displayName is an attribute)
    final attributes = [
      AttributeArg(name: 'email', value: email),
      AttributeArg(name: 'name', value: displayName),
    ];

    try {
      // Pass the safeUsername as the primary username
      final result = await _userPool.signUp(
        safeUsername,
        password.trim(),
        userAttributes: attributes,
      );

      _cognitoUser = result.user;
      debugLog(
          'Cognito Sign Up Successful. User Confirmed: ${result.userConfirmed}. Primary Username: $safeUsername');

      // Return the primary username (safeUsername) for confirmation.
      return safeUsername;
    } on CognitoClientException catch (e) {
      if (e.message?.contains('UsernameExistsException') == true) {
        throw const CognitoDisplayNameConflictException(
            'This display name is already taken. Please choose a different one.');
      }
      if (e.message?.contains('AliasExistsException') == true) {
        throw const CognitoUsernameExistsException(
            'User already exists with this email. Please sign in.');
      }
      rethrow;
    } catch (e) {
      debugLog('Error signing up: $e');
      rethrow;
    }
  }

  // --- COGNITO CONFIRMATION ---
  /// The first argument is now the primary username used by Cognito.
  static Future<void> confirmRegistration(
      String username, String confirmationCode) async {
    _ensureConfigured();

    // Use the primary username (safeUsername) to look up the user
    final user = CognitoUser(username, _userPool);

    try {
      // Use confirmRegistration as required by the library
      await user.confirmRegistration(confirmationCode);
      debugLog('User $username successfully confirmed.');
    } on CognitoClientException catch (e) {
      // Catch CodeMismatchException, ExpiredCodeException, etc.
      debugLog('User confirmation failed: ${e.message}');
      rethrow;
    } catch (e) {
      debugLog('Error confirming user: $e');
      rethrow;
    }
  }

  // --- COGNITO SIGN IN ---
  /// Uses a generic identifier (username or email alias) for sign-in.
  static Future<AuthCredentials?> signInWithIdentifierPassword(
      String identifier, String password) async {
    _ensureConfigured();

    // The identifier can be the primary username or an alias (like email),
    // depending on User Pool configuration.
    _cognitoUser = CognitoUser(identifier, _userPool);
    final authDetails =
        AuthenticationDetails(username: identifier, password: password.trim());

    try {
      // Authenticate the user using the identifier
      _cognitoUser!.setAuthenticationFlowType('USER_PASSWORD_AUTH');
      final session = await _cognitoUser!.authenticateUser(authDetails);
      if (session == null) {
        throw Exception('Authentication failed: empty session returned');
      }
      final idToken = session.getIdToken().jwtToken;
      if (idToken != null) {
        final attributes = await _cognitoUser!.getUserAttributes();

        String? cognitoEmail;
        String? displayName;

        for (final attribute in attributes!) {
          if (attribute.getName() == 'email') {
            cognitoEmail = attribute.getValue();
          }
          if (attribute.getName() == 'name') {
            displayName = attribute.getValue();
          }
        }

        _currentAuthCredentials = AuthCredentials(
          cognitoIdToken: idToken,
          id: _cognitoUser!
              .username!, // The primary username (the cleaned display name)
          email: cognitoEmail ??
              identifier, // Use retrieved email or the identifier if email wasn't found (unlikely)
          displayName: displayName,
          photoUrl: null,
        );
        await SecureCredentialsStorage.setAwsLoggedIn(true);
        await SecureCredentialsStorage.saveUserId(
          session.getIdToken().payload['sub'],
        );
        await SecureCredentialsStorage.saveUserName(
            _cognitoUser!.username!.trim());
        AuthStateNotifier.instance.notifyAuthChanged();

        debugLog('=== Cognito Sign-In Success ===');
        debugLog(await SecureCredentialsStorage.getUserId());
        return _currentAuthCredentials;
      }
    } on CognitoClientException catch (e, stackTrace) {
      debugLog('Cognito Sign-in failed: ${e.message}');
      debugPrintStack(
        label: 'CognitoClientException stack',
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (e, stackTrace) {
      debugLog('Error signing in: $e');
      debugPrintStack(
        label: 'AuthService.signIn stack',
        stackTrace: stackTrace,
      );
      rethrow;
    }
    return null;
  }

  // --- FORGOT PASSWORD FLOW ---

  /// Initiates the forgot password flow by sending a confirmation code to the user's email.
  static Future<void> forgotPassword(String identifier) async {
    _ensureConfigured();

    // Use the identifier (username or alias) to look up the user in Cognito
    final user = CognitoUser(identifier, _userPool);

    try {
      await user.forgotPassword();
      debugLog('Forgot password code initiated for $identifier');
    } on CognitoClientException catch (e) {
      debugLog('Forgot password failed: ${e.message}');
      rethrow;
    } catch (e) {
      debugLog('Error initiating forgot password: $e');
      rethrow;
    }
  }

  /// Confirms the code and sets a new password.
  static Future<void> confirmPassword(
    String identifier,
    String confirmationCode,
    String newPassword,
  ) async {
    _ensureConfigured();

    // Must use the identifier (username or alias) to reference the user in Cognito
    final user = CognitoUser(identifier, _userPool);

    try {
      await user.confirmPassword(confirmationCode, newPassword.trim());
      debugLog('Password reset successful for $identifier');
    } on CognitoClientException catch (e) {
      debugLog('Confirm password failed: ${e.message}');
      rethrow;
    } catch (e) {
      debugLog('Error confirming new password: $e');
      rethrow;
    }
  }

  // --- SIGN OUT AND HELPERS ---

  static Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await SecureCredentialsStorage.clearUserCredentials();
      await prefs.remove('last_websocket_id');

      if (_cognitoUser != null) {
        await _cognitoUser!.signOut();
        _cognitoUser = null;
      }

      _currentAuthCredentials = null;
      AuthStateNotifier.instance.notifyAuthChanged();
      debugLog('User signed out successfully');
    } catch (e) {
      debugLog('Error signing out: $e');
    }
  }

  static bool isUsernameExistsException(dynamic error) {
    return error is CognitoUsernameExistsException;
  }

  static bool isDisplayNameConflictException(dynamic error) {
    return error is CognitoDisplayNameConflictException;
  }

  static AuthCredentials? getCurrentAuthCredentials() {
    return _currentAuthCredentials;
  }
}
