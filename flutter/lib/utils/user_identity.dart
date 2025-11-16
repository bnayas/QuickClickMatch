class UserIdentityUtils {
  static const String _temporaryPrefix = 'guest_';

  /// Returns true when the provided ID looks like a temporary guest identifier.
  static bool isTemporaryUserId(String? userId) {
    if (userId == null) return true;
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return true;
    return trimmed.startsWith(_temporaryPrefix);
  }

  /// Registered IDs come from Cognito and are stable, unlike guest IDs.
  static bool isRegisteredUserId(String? userId) {
    return !isTemporaryUserId(userId);
  }
}
