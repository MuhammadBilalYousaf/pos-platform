import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/errors/failures.dart';
import '../../core/firebase/firestore_host.dart';
import '../../core/firebase/tenant_context.dart';
import '../../core/storage/hive_boxes.dart';
import '../../core/storage/secure_store.dart';
import '../../config/firebase/firebase_options.dart';
import '../../features/auth/data/datasources/firebase_auth_datasource.dart';
import '../../features/auth/data/datasources/firestore_session_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/auth_usecases.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/products/data/repositories/catalog_repository_impl.dart';
import '../../features/products/presentation/bloc/catalog_cubit.dart';
import '../../features/pos/presentation/bloc/cart_cubit.dart';
import '../../features/pos/presentation/bloc/order_cubit.dart';
import '../../features/orders/data/repositories/order_repository.dart';
import '../../features/orders/data/repositories/held_ticket_repository.dart';
import '../../features/printing/data/printer_settings_store.dart';
import '../../features/printing/domain/printer_service.dart';
import '../../features/sync/presentation/bloc/sync_cubit.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../core/network/query_repository.dart';
import '../../features/admin/data/admin_repository.dart';
import '../../features/admin/presentation/bloc/branch_context_cubit.dart';
import '../../features/shifts/data/shift_repository.dart';

final sl = GetIt.instance;

Future<void> _openHiveBox(String name) async {
  try {
    await Hive.openBox(name);
  } catch (error) {
    final text = error.toString().toLowerCase();
    if (text.contains('lock failed') ||
        text.contains('errno = 33') ||
        text.contains('another process has locked')) {
      throw const Failure(
        'POS is already open in another window. Close the other copy, then start again.',
      );
    }
    rethrow;
  }
}

Future<void> configureDependencies() async {
  if (!kIsWeb && Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    final path = (local != null && local.isNotEmpty)
        ? '$local\\POS Platform\\hive'
        : '${Directory.systemTemp.path}\\POS Platform\\hive';
    await Directory(path).create(recursive: true);
    Hive.init(path);
  } else {
    await Hive.initFlutter();
  }
  await _openHiveBox(HiveBoxes.catalog);
  await _openHiveBox(HiveBoxes.cart);
  await _openHiveBox(HiveBoxes.pendingOrders);
  await _openHiveBox(HiveBoxes.session);
  await _openHiveBox(HiveBoxes.heldTickets);

  sl.registerLazySingleton<SecureStore>(SecureStore.new);
  try {
    final deviceId = await sl<SecureStore>().readDeviceId();
    if (deviceId == null) {
      await sl<SecureStore>().writeDeviceId(const Uuid().v4());
    }
  } catch (_) {
    // Device id is optional; never block app start in release.
  }

  sl.registerLazySingleton<TenantContext>(TenantContext.new);
  sl.registerLazySingleton<FirebaseAuthHost>(
    () => FirebaseAuthHost(DefaultFirebaseOptions.isConfigured ? FirebaseAuth.instance : null),
  );
  sl.registerLazySingleton<FirestoreHost>(
    () => FirestoreHost(DefaultFirebaseOptions.isConfigured ? FirebaseFirestore.instance : null),
  );
  sl.registerLazySingleton<FirebaseAuthDataSource>(() => FirebaseAuthDataSource(sl<FirebaseAuthHost>().auth));
  sl.registerLazySingleton<FirestoreSessionDataSource>(
    () => FirestoreSessionDataSource(
      firestore: sl(),
      tenant: sl(),
      sessionBox: Hive.box(HiveBoxes.session),
    ),
  );
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(firebase: sl(), session: sl()),
  );
  sl.registerLazySingleton(() => SignIn(sl()));
  sl.registerLazySingleton(() => SignOut(sl()));
  sl.registerLazySingleton(() => LoadSession(sl()));
  sl.registerLazySingleton(() => IsPlatformInitialized(sl()));
  sl.registerLazySingleton(() => BootstrapPlatform(sl()));
  sl.registerFactory(
    () => AuthBloc(
      signIn: sl(),
      signOut: sl(),
      loadSession: sl(),
      isPlatformInitialized: sl(),
      bootstrapPlatform: sl(),
    ),
  );

  sl.registerLazySingleton<CatalogRepository>(
    () => CatalogRepositoryImpl(sl(), sl(), Hive.box(HiveBoxes.catalog)),
  );
  sl.registerFactory(() => CatalogCubit(sl()));
  sl.registerLazySingleton(() => HeldTicketRepository(sl(), sl()));
  sl.registerFactory(() => CartCubit(Hive.box(HiveBoxes.heldTickets), sl()));

  sl.registerLazySingleton(() => AdminRepository(sl(), sl(), sl()));
  sl.registerLazySingleton(() => ShiftRepository(sl(), sl(), Hive.box(HiveBoxes.session)));
  sl.registerLazySingleton(
    () => OrderRepository(
      sl(),
      sl(),
      Hive.box(HiveBoxes.pendingOrders),
      sl<ShiftRepository>(),
      sl<AdminRepository>(),
    ),
  );
  sl.registerLazySingleton(() => PrinterSettingsStore(Hive.box(HiveBoxes.session)));
  sl.registerLazySingleton<PrinterService>(() => ThermalPrinterService(EscPosEncoder(), sl()));
  sl.registerFactory(() => OrderCubit(sl(), sl()));
  sl.registerFactory(() => SyncCubit(sl()));
  sl.registerLazySingleton(() => DashboardRepository(sl(), sl()));
  sl.registerLazySingleton(() => QueryRepository(sl(), sl()));
  sl.registerLazySingleton(() => BranchContextCubit(sl()));
}
