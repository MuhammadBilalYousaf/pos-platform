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

  Stream<User?> authState() => _auth?.authStateChanges() ?? const Stream.empty();
}
