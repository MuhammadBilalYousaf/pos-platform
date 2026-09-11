import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/session.dart';
import '../../domain/usecases/auth_usecases.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email];
}

class AuthPlatformSetupRequested extends AuthEvent {
  const AuthPlatformSetupRequested({
    required this.name,
    required this.email,
    required this.password,
    required this.ownerCode,
  });
  final String name;
  final String email;
  final String password;
  final String ownerCode;
  @override
  List<Object?> get props => [email];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.message, this.platformInitialized = true});
  final String? message;
  final bool platformInitialized;
  @override
  List<Object?> get props => [message, platformInitialized];
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final Session session;
  @override
  List<Object?> get props => [session];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required SignIn signIn,
    required SignOut signOut,
    required LoadSession loadSession,
    required IsPlatformInitialized isPlatformInitialized,
    required BootstrapPlatform bootstrapPlatform,
  })  : _signIn = signIn,
        _signOut = signOut,
        _loadSession = loadSession,
        _isPlatformInitialized = isPlatformInitialized,
        _bootstrapPlatform = bootstrapPlatform,
        super(const AuthInitial()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginRequested>(_onLogin);
    on<AuthPlatformSetupRequested>(_onSetup);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthRefreshRequested>(_onRefresh);
  }

  final SignIn _signIn;
  final SignOut _signOut;
  final LoadSession _loadSession;
  final IsPlatformInitialized _isPlatformInitialized;
  final BootstrapPlatform _bootstrapPlatform;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    var initialized = true;
    try {
      initialized = await _isPlatformInitialized();
    } catch (_) {
      initialized = false;
    }
    try {
      final session = await _loadSession();
      emit(AuthAuthenticated(session));
    } catch (_) {
      emit(AuthUnauthenticated(platformInitialized: initialized));
    }
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    final initialized = state is AuthUnauthenticated ? (state as AuthUnauthenticated).platformInitialized : true;
    emit(const AuthLoading());
    try {
      final session = await _signIn(email: event.email, password: event.password);
      emit(AuthAuthenticated(session));
    } on Failure catch (error) {
      emit(AuthUnauthenticated(message: error.message, platformInitialized: initialized));
    } catch (error) {
      emit(AuthUnauthenticated(message: mapFirebaseFailure(error).message, platformInitialized: initialized));
    }
  }

  Future<void> _onSetup(AuthPlatformSetupRequested event, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      final session = await _bootstrapPlatform(
        name: event.name,
        email: event.email,
        password: event.password,
        ownerCode: event.ownerCode,
      );
      emit(AuthAuthenticated(session));
    } on Failure catch (error) {
      var initialized = false;
      try {
        initialized = await _isPlatformInitialized();
      } catch (_) {}
      emit(AuthUnauthenticated(message: error.message, platformInitialized: initialized));
    } catch (error) {
      var initialized = false;
      try {
        initialized = await _isPlatformInitialized();
      } catch (_) {}
      emit(AuthUnauthenticated(message: mapFirebaseFailure(error).message, platformInitialized: initialized));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _signOut();
    var initialized = true;
    try {
      initialized = await _isPlatformInitialized();
    } catch (_) {}
    emit(AuthUnauthenticated(platformInitialized: initialized));
  }

  Future<void> _onRefresh(AuthRefreshRequested event, Emitter<AuthState> emit) async {
    if (state is! AuthAuthenticated) return;
    try {
      final session = await _loadSession();
      emit(AuthAuthenticated(session));
    } catch (_) {}
  }
}
