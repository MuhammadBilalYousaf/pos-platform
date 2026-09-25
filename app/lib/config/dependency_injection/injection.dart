import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
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

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  await Hive.initFlutter();
  await Hive.openBox(HiveBoxes.catalog);
  await Hive.openBox(HiveBoxes.cart);
  await Hive.openBox(HiveBoxes.pendingOrders);
  await Hive.openBox(HiveBoxes.session);
  await Hive.openBox(HiveBoxes.heldTickets);

  sl.registerLazySingleton<SecureStore>(SecureStore.new);
  final deviceId = await sl<SecureStore>().readDeviceId();
  if (deviceId == null) {
    await sl<SecureStore>().writeDeviceId(const Uuid().v4());
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

  sl.registerLazySingleton(() => OrderRepository(sl(), sl(), Hive.box(HiveBoxes.pendingOrders)));
  sl.registerLazySingleton(() => PrinterSettingsStore(Hive.box(HiveBoxes.session)));
  sl.registerLazySingleton<PrinterService>(() => ThermalPrinterService(EscPosEncoder(), sl()));
  sl.registerFactory(() => OrderCubit(sl(), sl()));
  sl.registerFactory(() => SyncCubit(sl()));
  sl.registerLazySingleton(() => DashboardRepository(sl(), sl()));
  sl.registerLazySingleton(() => QueryRepository(sl(), sl()));
  sl.registerLazySingleton(() => AdminRepository(sl(), sl(), sl()));
  sl.registerLazySingleton(() => BranchContextCubit(sl()));
}
