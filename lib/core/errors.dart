/// An error whose message is safe to show to the user verbatim
/// (web: `error.userFacing = true`).
class UserFacingError implements Exception {
  const UserFacingError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown by the validators in validation.dart (web: ZodError).
class ValidationError implements Exception {
  const ValidationError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Message to show for an arbitrary error: user-facing messages verbatim, else [fallback].
String userMessage(Object error, String fallback) =>
    error is UserFacingError ? error.message : fallback;
