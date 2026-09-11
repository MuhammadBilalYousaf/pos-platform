import 'package:flutter/material.dart';

const Color kAdminAccent = Color(0xFF7C3AED);
const Color kAdminAccentSoft = Color(0xFFEDE9FE);
const Color kAdminBorder = Color(0xFFE2E8F0);
const Color kAdminMuted = Color(0xFF64748B);
const Color kAdminPageBg = Color(0xFFF1F5F9);

ButtonStyle adminPrimaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: kAdminAccent,
  foregroundColor: Colors.white,
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

ButtonStyle adminOutlinedButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: kAdminAccent,
  side: const BorderSide(color: kAdminBorder),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

InputDecoration adminInputDecoration(String hint, {IconData? icon}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: kAdminMuted),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kAdminBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kAdminBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kAdminAccent, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.label, required this.tone});
  final String label;
  final AdminStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      AdminStatusTone.success => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      AdminStatusTone.warning => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      AdminStatusTone.danger => (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      AdminStatusTone.neutral => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
      AdminStatusTone.info => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

enum AdminStatusTone { success, warning, danger, neutral, info }

class AdminSurfaceCard extends StatelessWidget {
  const AdminSurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAdminBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class AdminTableHeader extends StatelessWidget {
  const AdminTableHeader({super.key, required this.columns});
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: kAdminBorder)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: i == 0 ? 2 : 1,
              child: Text(columns[i], style: const TextStyle(color: kAdminMuted, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class AdminCategoryChip extends StatelessWidget {
  const AdminCategoryChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? kAdminAccent : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? kAdminAccent : kAdminBorder),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
