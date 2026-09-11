import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/dependency_injection/injection.dart';
import 'config/firebase/firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/role_home.dart';
import 'features/admin/presentation/bloc/branch_context_cubit.dart';
import 'features/pos/presentation/bloc/cart_cubit.dart';
import 'features/pos/presentation/bloc/order_cubit.dart';
import 'features/products/presentation/bloc/catalog_cubit.dart';
import 'features/sync/presentation/bloc/sync_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await configureDependencies();
  runApp(const PosApp());
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
            _catalogCubit.load();
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
