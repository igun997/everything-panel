import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Optional Google account. Everything works without it; it only identifies
/// you so push notifications can follow you across devices.
class AuthService extends ChangeNotifier {
  AuthService();

  bool available = false;
  User? user;
  bool busy = false;
  String? error;
  StreamSubscription<User?>? _sub;

  /// Call after Firebase has been initialised ([available] = Firebase is ready).
  Future<void> init({required bool firebaseReady}) async {
    available = firebaseReady;
    if (!available) {
      notifyListeners();
      return;
    }
    try {
      await GoogleSignIn.instance.initialize();
    } catch (e) {
      debugPrint('Google sign-in init failed: $e');
      available = false;
      notifyListeners();
      return;
    }
    user = FirebaseAuth.instance.currentUser;
    _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
      user = u;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<bool> signInWithGoogle() async {
    if (!available || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('Google returned no ID token.');
      await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return true;
    } on GoogleSignInException catch (e) {
      // Closing the account picker is not an error worth showing.
      if (e.code != GoogleSignInExceptionCode.canceled) error = 'Google sign-in failed (${e.code.name}).';
      return false;
    } catch (e) {
      error = 'Google sign-in failed. Check the Firebase setup.';
      debugPrint('Google sign-in error: $e');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (!available) return;
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
