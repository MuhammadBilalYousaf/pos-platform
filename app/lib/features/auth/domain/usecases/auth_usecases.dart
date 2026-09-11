import '../repositories/auth_repository.dart';
import '../entities/session.dart';

class SignIn {
  SignIn(this._repository);
  final AuthRepository _repository;

  Future<Session> call({required String email, required String password}) async {
    await _repository.signIn(email: email, password: password);
    return _repository.loadSession();
  }
}

class SignOut {
  SignOut(this._repository);
  final AuthRepository _repository;
  Future<void> call() => _repository.signOut();
}

class LoadSession {
  LoadSession(this._repository);
  final AuthRepository _repository;
  Future<Session> call() => _repository.loadSession();
}

class IsPlatformInitialized {
  IsPlatformInitialized(this._repository);
  final AuthRepository _repository;
  Future<bool> call() => _repository.isPlatformInitialized();
}

class BootstrapPlatform {
  BootstrapPlatform(this._repository);
  final AuthRepository _repository;
  Future<Session> call({
    required String name,
    required String email,
    required String password,
    required String ownerCode,
  }) {
    return _repository.bootstrapPlatform(
      name: name,
      email: email,
      password: password,
      ownerCode: ownerCode,
    );
  }
}
