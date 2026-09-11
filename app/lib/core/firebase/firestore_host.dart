import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../errors/failures.dart';

class FirestoreHost {
  const FirestoreHost(this.db);
  final FirebaseFirestore? db;

  FirebaseFirestore requireDb() {
    final firestore = db;
    if (firestore == null || Firebase.apps.isEmpty) {
      throw const Failure('Firebase is not configured on this device yet.');
    }
    return firestore;
  }
}

Object _unwrapFirebaseError(Object error) {
  Object current = error;
  for (var i = 0; i < 6; i++) {
    if (current is Failure) {
      return current;
    }
    final dynamic value = current;
    Object? next;
    try {
      next = value.error as Object?;
    } catch (_) {
      next = null;
    }
    if (next == null || identical(next, current)) {
      try {
        next = value.cause as Object?;
      } catch (_) {
        next = null;
      }
    }
    if (next == null || identical(next, current)) {
      break;
    }
    current = next;
  }
  return current;
}

String _errorText(Object error) {
  if (error is Failure) {
    return error.message;
  }
  if (error is FirebaseException) {
    return error.message ?? error.code;
  }
  if (error is FirebaseAuthException) {
    return error.message ?? error.code;
  }
  final dynamic value = error;
  try {
    final message = value.message;
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
  } catch (_) {}
  return error.toString();
}

Failure mapFirebaseFailure(Object error) {
  final root = _unwrapFirebaseError(error);
  if (root is Failure) {
    return root;
  }

  final code = root is FirebaseException
      ? root.code
      : (root is FirebaseAuthException ? root.code : '');
  final text = _errorText(root);
  final lower = text.toLowerCase();
  final wrapped = error.toString().toLowerCase();

  if (code == 'invalid-email' || lower.contains('invalid-email')) {
    return const Failure('Firebase rejected that email address. Use a normal domain such as .com.');
  }
  if (code == 'operation-not-allowed' || lower.contains('operation-not-allowed')) {
    return const Failure('Enable Email/Password under Authentication → Sign-in method.');
  }
  if (code == 'unauthorized-domain' || lower.contains('unauthorized-domain')) {
    return const Failure('Add 127.0.0.1 to Authentication → Settings → Authorized domains.');
  }
  if (code == 'permission-denied' ||
      lower.contains('permission-denied') ||
      lower.contains('permission_denied') ||
      lower.contains('missing or insufficient permissions')) {
    return const Failure(
      'Firestore blocked this sale. Publish the latest firestore.rules (cashiers need order create + orderSeq update), confirm you are signed in, and that a branch is selected.',
      code: 'PERMISSION',
    );
  }
  if (code == 'not-found' || lower.contains('does not exist') || lower.contains('cloud resource not found')) {
    return const Failure('Create a Cloud Firestore database in the Firebase console for project pos-platform-2a8af.');
  }
  if (code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'network-request-failed' ||
      lower.contains('client is offline')) {
    return const Failure(
      'Could not reach Firestore. Create the database if it is missing, then check your internet connection.',
      code: 'OFFLINE',
    );
  }
  if (code == 'failed-precondition' || lower.contains('failed-precondition')) {
    return Failure(text.isEmpty ? 'Firestore rejected this sale.' : text, code: code);
  }
  if (root is FirebaseAuthException) {
    return Failure(root.message ?? text, code: root.code);
  }
  if (root is FirebaseException) {
    return Failure(root.message ?? text, code: root.code);
  }
  if (wrapped.contains('converted future') || lower.contains('converted future')) {
    return const Failure(
      'Sale could not be completed. Check stock, branch selection, and that firestore.rules are published. Open the browser console for details.',
      code: 'UNKNOWN',
    );
  }
  return Failure(text.isEmpty ? 'Unexpected error while saving the sale.' : text);
}
