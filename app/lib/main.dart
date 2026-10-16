import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/dependency_injection/injection.dart';
import 'config/firebase/firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_log.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/role_home.dart';
import 'features/admin/presentation/bloc/branch_context_cubit.dart';
import 'features/pos/presentation/bloc/cart_cubit.dart';
import 'features/pos/presentation/bloc/order_cubit.dart';
import 'features/products/presentation/bloc/catalog_cubit.dart';
import 'features/sync/presentation/bloc/sync_cubit.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLog.init();

    // Keep release builds alive: surface errors instead of killing the process.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLog.error('FlutterError', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.error('Uncaught platform error', error, stack);
      return true; // mark handled — do not abort the isolate
    };
    ErrorWidget.builder = (details) {
      AppLog.error('ErrorWidget', details.exception, details.stack);
      return Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Something went wrong on this screen.\n${details.exception}\n\n'
              'Log: ${AppLog.path ?? 'Documents\\\\POS\\\\pos_app_log.txt'}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    try {
      if (DefaultFirebaseOptions.isConfigured) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        if (!kIsWeb && Platform.isWindows) {
          // The Windows release SDK drops the login token unless Auth is
          // listened to first, and its disk cache aborts sale transactions.
          FirebaseAuth.instance.idTokenChanges().listen((_) {});
          FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
        }
      }
      await configureDependencies();
      await AppLog.info('App started OK');
    } catch (error, stack) {
      await AppLog.error('Startup failed', error, stack);
      runApp(_StartupErrorApp(message: '$error\n\nLog: ${AppLog.path ?? ''}'));
      return;
    }

    runApp(const PosApp());
  }, (error, stack) {
    AppLog.error('Zone error', error, stack);
  });
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('App failed to start:\n\n$message', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  late final AuthBloc _authBloc;
  late final CatalogCubit _catalogCubit;
  late final CartCubit _cartCubit;
  late final OrderCubit _orderCubit;
  late final SyncCubit _syncCubit;
  late final BranchContextCubit _branchContext;

  @override
  void initState() {
    super.initState();
    _authBloc = sl<AuthBloc>()..add(const AuthStarted());
    _catalogCubit = sl<CatalogCubit>();
    _cartCubit = sl<CartCubit>();
    _orderCubit = sl<OrderCubit>();
    _syncCubit = sl<SyncCubit>();
    _branchContext = sl<BranchContextCubit>();
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((item) => item != ConnectivityResult.none);
      _syncCubit.setOnline(online);
    });
  }

  @override
  void dispose() {
    _authBloc.close();
    _catalogCubit.close();
    _cartCubit.close();
    _orderCubit.close();
    _syncCubit.close();
    _branchContext.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _catalogCubit),
        BlocProvider.value(value: _cartCubit),
        BlocProvider.value(value: _orderCubit),
        BlocProvider.value(value: _syncCubit),
        BlocProvider.value(value: _branchContext),
      ],
      child: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated && !state.session.user.isPlatformAdmin) {
            _branchContext.bind(state.session);
            _cartCubit.setTaxRate(state.session.business?.taxRate ?? '0');
            _catalogCubit.load(forceRefresh: true);
          }
          if (state is AuthUnauthenticated) {
            _branchContext.clear();
          }
        },
        builder: (context, state) {
          final business = state is AuthAuthenticated ? state.session.business : null;
          final theme = AppTheme.fromBranding(
            primary: AppTheme.parseHex(business?.primaryColor ?? '#1F6F4A', const Color(0xFF1F6F4A)),
            secondary: AppTheme.parseHex(business?.secondaryColor ?? '#F4EFE6', const Color(0xFFF4EFE6)),
          );
          return MaterialApp(
            title: 'POS',
            debugShowCheckedModeBanner: false,
            theme: theme,
            // Always Sign In when signed out. Role area comes from the account after auth.
            home: state is AuthAuthenticated
                ? RoleHome(session: state.session)
                : const LoginPage(),
          );
        },
      ),
    );
  }
}
