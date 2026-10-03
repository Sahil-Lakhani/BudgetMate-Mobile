// Firebase Auth + native Google Sign-In (web: signInWithPopup(GoogleAuthProvider)).
// The account chooser shows the app name from the OAuth consent screen ("BudgetMate").
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';
import 'local_data.dart';

/// Thrown when the user closes the Google account chooser — not an error to display.
class SignInCancelled implements Exception {}

class AuthService {
  AuthService(this._auth, this._localData);

  final FirebaseAuth _auth;
  final LocalData _localData;
  bool _initialized = false;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
    _initialized = true;
  }

  Future<OAuthCredential> _googleCredential() async {
    await _init();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('Google returned no ID token');
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw SignInCancelled();
      }
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    final credential = await _googleCredential();
    await _auth.signInWithCredential(credential);
    // Profile is written by the auth-state listener (see providers.dart)
  }

  /// Deleting an account needs a recent login (web: reauthenticateWithPopup).
  Future<void> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final credential = await _googleCredential();
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> signOut() async {
    try {
      await _localData.clearUserData();
      await _auth.signOut();
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Error logging out: $e');
    }
  }
}

/// Safe, useful messages for sign-in failures (web: loginErrorMessage).
String loginErrorMessage(Object error) {
  if (error is SignInCancelled) return '';
  if (error is FirebaseAuthException && error.code == 'network-request-failed') {
    return 'Network error. Check your connection and try again.';
  }
  if (error is GoogleSignInException && error.code == GoogleSignInExceptionCode.clientConfigurationError) {
    return "Sign-in isn't available in this build yet. Please try again later.";
  }
  return 'Sign-in failed. Please try again.';
}
