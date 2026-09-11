import 'package:flutter/material.dart';
import '../../../admin/presentation/pages/platform_shell.dart';
import '../../../dashboard/presentation/pages/app_shell.dart';
import '../../domain/entities/session.dart';
import '../../domain/permissions.dart';

/// Routes an authenticated session to the area for that account's role.
/// Role comes from the user profile — never from a Sign In choice.
class RoleHome extends StatelessWidget {
  const RoleHome({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final role = session.user.role;
    switch (role) {
      case PosRole.platformSuperAdmin:
        // Super Admin → platform dashboard (businesses, audit)
        return const PlatformShell();
      case PosRole.businessAdmin:
        // Business Admin → full business workbench
        return const AppShell();
      case PosRole.branchManager:
        // Manager → branch operations (nav filtered by permissions)
        return const AppShell();
      case PosRole.cashier:
        // Employee → POS-first workbench
        return const AppShell();
      default:
        return const AppShell();
    }
  }
}
