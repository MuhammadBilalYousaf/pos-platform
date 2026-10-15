import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../config/firebase/firebase_options.dart';

class FirebaseAuthHost {
  const FirebaseAuthHost(this.auth);
  final FirebaseAuth? auth;
}

class FirebaseAuthDataSource {
  FirebaseAuthDataSource(this._auth);
  final FirebaseAuth? _auth;

  FirebaseAuth _require() {
    final auth = _auth;
    if (auth == null) {
      throw const Failure('Firebase is not configured on this device yet.');
    }
    return auth;
  }

  User? get currentUser => _auth?.currentUser;

  Future<void> _bindWindowsAuth(User? user) async {
    if (kIsWeb || !Platform.isWindows || user == null) {
      return;
    }
    await user.getIdToken(true);
  }

  Future<void> signIn(String email, String password) async {
    try {
      final credential = await _require().signInWithEmailAndPassword(email: email, password: password);
      await _bindWindowsAuth(credential.user);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> createOwnerAccount(String email, String password) async {
    try {
      final credential = await _require().createUserWithEmailAndPassword(email: email, password: password);
      await _bindWindowsAuth(credential.user);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        throw const Failure('That email already exists. Super Admin signup needs a new email.');
      }
      throw mapFirebaseFailure(error);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> createOrSignIn(String email, String password) async {
    final auth = _require();
    try {
      final credential = await auth.createUserWithEmailAndPassword(email: email, password: password);
      await _bindWindowsAuth(credential.user);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        await signIn(email, password);
        return;
      }
      throw mapFirebaseFailure(error);
    } catch (error) {
      final mapped = mapFirebaseFailure(error);
      if (mapped.code == 'email-already-in-use' || mapped.message.toLowerCase().contains('email-already-in-use')) {
        await signIn(email, password);
        return;
      }
      throw mapped;
    }
  }

  Future<void> signOut() async {
    await _auth?.signOut();
  }

  Future<String> createUserWithoutSwitching({required String email, required String password}) async {
    final app = await Firebase.initializeApp(
      name: 'invite-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      final credential = await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw const Failure('Unable to create that account.');
      }
      await FirebaseAuth.instanceFor(app: app).signOut();
      return uid;
    } catch (error) {
      throw mapFirebaseFailure(error);
    } finally {
      await app.delete();
    }
  }

  /// Updates login email / password for an existing Auth user without switching the admin session.
  /// Uses a secondary Firebase Auth app. Password is set by re-creating the credential when possible;
  /// otherwise a reset email is sent so the typed password can be applied by the staff member.
  Future<void> updateUserAuthWithoutSwitching({
    required String email,
    String? newEmail,
    String? newPassword,
  }) async {
    final targetEmail = (newEmail ?? email).trim();
    final password = newPassword?.trim() ?? '';
    final emailChanged = targetEmail.isNotEmpty && targetEmail.toLowerCase() != email.trim().toLowerCase();
    if (!emailChanged && password.isEmpty) {
      return;
    }

    final app = await Firebase.initializeApp(
      name: 'staff-auth-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    try {
      if (password.isNotEmpty) {
        // Already set to this password?
        try {
          await auth.signInWithEmailAndPassword(email: email.trim(), password: password);
          final user = auth.currentUser;
          if (user != null && emailChanged) {
            await user.verifyBeforeUpdateEmail(targetEmail);
          }
          await auth.signOut();
          return;
        } on FirebaseAuthException catch (error) {
          if (error.code == 'user-not-found') {
            final created = await auth.createUserWithEmailAndPassword(
              email: targetEmail,
              password: password,
            );
            await created.user?.reload();
            await auth.signOut();
            return;
          }
          if (error.code == 'wrong-password' ||
              error.code == 'invalid-credential' ||
              error.code == 'invalid-login-credentials') {
            // Cannot overwrite another user's password from the client SDK without Admin.
            // Sign-in with the NEW password failed, so send a reset link.
            await _require().sendPasswordResetEmail(email: email.trim());
            throw Failure(
              'Login password could not be overwritten directly. A reset email was sent to ${email.trim()}. '
              'Ask them to open that email and set this password: $password',
            );
          }
          throw mapFirebaseFailure(error);
        }
      }

      if (emailChanged) {
        // Email-only change without password: send reset to the current login email
        // so they can recover access; profile email is updated separately in Firestore.
        await _require().sendPasswordResetEmail(email: email.trim());
        throw Failure(
          'Profile email will be updated. A password reset email was sent to the current login ($email) '
          'so they can recover access. To change the Firebase login email itself, set a new password here '
          'as well, or update the user in Firebase Console → Authentication.',
        );
      }
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    } finally {
      try {
        await auth.signOut();
      } catch (_) {}
      await app.delete();
    }
  }

  Stream<User?> authState() => _auth?.authStateChanges() ?? const Stream.empty();
}
