import 'package:flutter/material.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
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
      subtitle: 'Your account details and assigned branch.',
      child: AdminSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: kAdminAccentSoft,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: kAdminAccent, fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(PosRole.label(user.role), style: const TextStyle(color: kAdminMuted)),
                  ],
                ),
              ],
            ),
            const Divider(height: 32, color: kAdminBorder),
            _ProfileField(label: 'Email', value: user.email),
            _ProfileField(label: 'Business', value: business?.name ?? '—'),
            _ProfileField(label: 'Branch', value: branch?.name ?? '—'),
            const SizedBox(height: 8),
            Text(
              'You can sell on POS for your assigned branch only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kAdminMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: kAdminMuted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
