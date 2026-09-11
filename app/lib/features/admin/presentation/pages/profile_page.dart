import 'package:flutter/material.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final business = session.business;
    final branch = session.branch;
    return PageFrame(
      title: 'Profile',
      subtitle: 'You can sell on POS for your assigned branch only.',
      child: ListView(
        children: [
          ListTile(title: const Text('Name'), subtitle: Text(user.name)),
          ListTile(title: const Text('Email'), subtitle: Text(user.email)),
          ListTile(title: const Text('Role'), subtitle: Text(PosRole.label(user.role))),
          ListTile(title: const Text('Business'), subtitle: Text(business?.name ?? '-')),
          ListTile(title: const Text('Branch'), subtitle: Text(branch?.name ?? '-')),
        ],
      ),
    );
  }
}
