import '../entities/session.dart';

abstract class AuthRepository {
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<Session> loadSession();
  Future<bool> isPlatformInitialized();
  Future<Session> bootstrapPlatform({
    required String name,
    required String email,
    required String password,
    required String ownerCode,
  });
  Stream<String?> authState();
}
