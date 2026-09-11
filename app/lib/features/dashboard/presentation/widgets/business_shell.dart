import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';
import '../../../../core/widgets/workbench.dart';

const Color kShellSidebar = Color(0xFF111827);
const Color kShellSidebarHover = Color(0xFF1F2937);
const Color kShellAccent = Color(0xFF7C3AED);
const Color kShellAccentSoft = Color(0xFFEDE9FE);
const Color kShellHeaderBg = Color(0xFFF8FAFC);
const Color kShellPageBg = Color(0xFFF1F5F9);

class BusinessWorkbenchShell extends StatefulWidget {
  const BusinessWorkbenchShell({
    super.key,
    required this.session,
    required this.destinations,
    required this.headerActions,
    this.initialIndex = 0,
    this.selectedIndex,
    this.onIndexChanged,
    this.onNewOrder,
    this.onLogout,
  });

  final Session session;
  final List<WorkbenchDestination> destinations;
  final List<Widget> headerActions;
  final int initialIndex;
  final int? selectedIndex;
  final ValueChanged<int>? onIndexChanged;
  final VoidCallback? onNewOrder;
  final VoidCallback? onLogout;

  @override
  State<BusinessWorkbenchShell> createState() => _BusinessWorkbenchShellState();
}

class _BusinessWorkbenchShellState extends State<BusinessWorkbenchShell> {
  late int _index = widget.initialIndex;
  bool _sidebarCollapsed = false;

  int get _activeIndex => widget.selectedIndex ?? _index;

  void _setIndex(int value) {
    if (widget.onIndexChanged != null) {
      widget.onIndexChanged!(value);
    } else {
      setState(() => _index = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    if (destinations.isEmpty) {
      return const Scaffold(body: Center(child: Text('No modules available for this role.')));
    }
    final safeIndex = _activeIndex.clamp(0, destinations.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final sidebarWidth = _sidebarCollapsed ? 76.0 : 260.0;
    final businessName = widget.session.business?.name ?? 'POS';
    final branchLabel = widget.session.branch?.name ??
        (widget.session.accessibleBranches.length == 1
            ? widget.session.accessibleBranches.first.name
            : 'All Branches');

    return Scaffold(
      backgroundColor: kShellPageBg,
      body: Row(
        children: [
          if (wide)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: sidebarWidth,
              child: _Sidebar(
                collapsed: _sidebarCollapsed,
                businessName: businessName,
                branchLabel: branchLabel,
                session: widget.session,
                destinations: destinations,
                selectedIndex: safeIndex,
                onSelect: _setIndex,
                onToggleCollapse: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                onLogout: widget.onLogout,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopHeader(
                  session: widget.session,
                  showMenu: !wide,
                  onMenu: () => _openMobileDrawer(context, destinations, safeIndex),
                  headerActions: widget.headerActions,
                  onNewOrder: widget.onNewOrder,
                ),
                Expanded(child: destinations[safeIndex].builder(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openMobileDrawer(
    BuildContext context,
    List<WorkbenchDestination> destinations,
    int selected,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kShellSidebar,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.85,
            child: _Sidebar(
              collapsed: false,
              businessName: widget.session.business?.name ?? 'POS',
              branchLabel: widget.session.branch?.name ?? 'Branch',
              session: widget.session,
              destinations: destinations,
              selectedIndex: selected,
              onSelect: (i) {
                _setIndex(i);
                Navigator.pop(ctx);
              },
              onToggleCollapse: () {},
              onLogout: widget.onLogout,
            ),
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.collapsed,
    required this.businessName,
    required this.branchLabel,
    required this.session,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.onToggleCollapse,
    this.onLogout,
  });

  final bool collapsed;
  final String businessName;
  final String branchLabel;
  final Session session;
  final List<WorkbenchDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleCollapse;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kShellSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kShellAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.icecream_outlined, color: Colors.white, size: 22),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          branchLabel,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
                IconButton(
                  onPressed: onToggleCollapse,
                  icon: Icon(
                    collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: [
                for (var i = 0; i < destinations.length; i++)
                  _NavTile(
                    collapsed: collapsed,
                    icon: destinations[i].icon,
                    label: destinations[i].label == 'Home' ? 'Dashboard' : destinations[i].label,
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.help_outline, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Need Help?',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: collapsed ? 16 : 18,
                  backgroundColor: kShellAccentSoft,
                  child: Text(
                    session.user.name.isEmpty
                        ? '?'
                        : session.user.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: kShellAccent, fontWeight: FontWeight.w800),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          PosRole.label(session.user.role),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!collapsed && onLogout != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 18),
                label: const Text('Logout', style: TextStyle(color: Colors.white70)),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? kShellAccent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: kShellSidebarHover,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? const Border(left: BorderSide(color: kShellAccent, width: 4))
                  : null,
            ),
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? Colors.white : Colors.white70),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.session,
    required this.showMenu,
    required this.onMenu,
    required this.headerActions,
    this.onNewOrder,
  });

  final Session session;
  final bool showMenu;
  final VoidCallback onMenu;
  final List<Widget> headerActions;
  final VoidCallback? onNewOrder;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('MMM d, yyyy').format(DateTime.now());
    return Material(
      color: kShellHeaderBg,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (showMenu)
              IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
            ...headerActions,
            const Spacer(),
            _HeaderChip(icon: Icons.calendar_today_outlined, label: 'Today ($today)'),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_outlined, color: Color(0xFF64748B)),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: kShellAccentSoft,
                  child: Text(
                    session.user.name.isEmpty
                        ? '?'
                        : session.user.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: kShellAccent, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  session.user.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(width: 12),
            if (onNewOrder != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kShellAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: onNewOrder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Order (POS)'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
        ],
      ),
    );
  }
}
