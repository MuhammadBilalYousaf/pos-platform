import 'package:flutter/material.dart';
import 'admin_ui_kit.dart';

class WorkbenchDestination {
  const WorkbenchDestination({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

class WorkbenchShell extends StatefulWidget {
  const WorkbenchShell({
    super.key,
    required this.title,
    required this.destinations,
    this.actions = const [],
    this.initialIndex = 0,
  });

  final Widget title;
  final List<WorkbenchDestination> destinations;
  final List<Widget> actions;
  final int initialIndex;

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final safeIndex = _index.clamp(0, destinations.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        title: widget.title,
        actions: widget.actions,
      ),
      drawer: wide
          ? null
          : Drawer(
              child: ListView(
                children: [
                  const DrawerHeader(child: Text('Menu')),
                  for (var i = 0; i < destinations.length; i++)
                    ListTile(
                      leading: Icon(destinations[i].icon),
                      title: Text(destinations[i].label),
                      selected: i == safeIndex,
                      onTap: () {
                        setState(() => _index = i);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: safeIndex,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)),
              ],
            ),
          Expanded(child: destinations[safeIndex].builder(context)),
        ],
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kAdminPageBg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(subtitle!, style: const TextStyle(color: kAdminMuted, fontSize: 14)),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
