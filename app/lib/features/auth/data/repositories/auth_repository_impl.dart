import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/entities/session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/firebase_auth_datasource.dart';
import '../datasources/firestore_session_datasource.dart';
import '../../../../core/errors/failures.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required FirebaseAuthDataSource firebase,
    required FirestoreSessionDataSource session,
  })  : _firebase = firebase,
        _session = session;

  final FirebaseAuthDataSource _firebase;
  final FirestoreSessionDataSource _session;

  @override
  Future<void> signIn({required String email, required String password}) {
    return _firebase.signIn(email, password);
  }

  @override
  Future<void> signOut() async {
    await _session.clear();
    await _firebase.signOut();
  }

  @override
  Future<Session> loadSession() async {
    final user = _firebase.currentUser;
    if (user == null) {
      throw const Failure('Not signed in.');
    }
    if (!kIsWeb && Platform.isWindows) {
      await user.getIdToken(true);
    }
    try {
      return await _session.load(uid: user.uid, email: user.email ?? '');
    } on Failure catch (error) {
      if (error.code != 'PERMISSION' || kIsWeb || !Platform.isWindows) {
        rethrow;
      }
      await user.getIdToken(true);
      return _session.load(uid: user.uid, email: user.email ?? '');
    }
  }

  @override
  Future<bool> isPlatformInitialized() => _session.isPlatformInitialized();

  @override
  Future<Session> bootstrapPlatform({
    required String name,
    required String email,
    required String password,
    required String ownerCode,
  }) async {
    if (ownerCode.trim().isEmpty) {
      throw const Failure('Enter the Super Admin secret code.');
    }
    await _firebase.createOwnerAccount(email, password);
    final user = _firebase.currentUser;
    if (user == null) {
      throw const Failure('Unable to create the Super Admin account.');
    }
    try {
      return await _session.bootstrapPlatform(
        uid: user.uid,
        name: name,
        email: user.email ?? email,
        ownerCode: ownerCode.trim(),
      );
    } catch (error) {
      await _firebase.signOut();
      rethrow;
    }
  }

  @override
  Stream<String?> authState() => _firebase.authState().map((user) => user?.uid);
}
