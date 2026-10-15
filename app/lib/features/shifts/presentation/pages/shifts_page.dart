import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../../core/widgets/workbench.dart';
import '../../data/shift_repository.dart';

class ShiftsPage extends StatefulWidget {
  const ShiftsPage({super.key});

  @override
  State<ShiftsPage> createState() => _ShiftsPageState();
}

class _ShiftsPageState extends State<ShiftsPage> {
  PosShift? _active;
  List<PosShift> _history = const [];
  ShiftSummary? _activeSummary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = sl<ShiftRepository>();
      final active = await repo.getActiveShift();
      final history = await repo.listShifts();
      ShiftSummary? summary;
      if (active != null) {
        summary = await repo.summarizeShift(active);
      }
      if (!mounted) return;
      setState(() {
        _active = active;
        _history = history;
        _activeSummary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    final cash = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Shifts can cross midnight. All orders stay on this business day until you end the shift.',
            ),
            const SizedBox(height: 12),
            TextField(controller: cash, decoration: const InputDecoration(labelText: 'Opening cash (optional)')),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Opening note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sl<ShiftRepository>().startShift(
        openingCash: cash.text.trim().isEmpty ? null : cash.text.trim(),
        openingNote: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _end() async {
    final active = _active;
    if (active == null) return;
    final cash = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Business day: ${active.businessDay}'),
            Text('Started: ${DateFormat('MMM d, h:mm a').format(active.startedAt)}'),
            if (_activeSummary != null) ...[
              const SizedBox(height: 8),
              Text('Orders: ${_activeSummary!.orderCount}'),
              Text('Sales: Rs. ${_activeSummary!.salesTotal}'),
              Text('Refunds: Rs. ${_activeSummary!.refundTotal}'),
              Text('Cancels: ${_activeSummary!.cancelCount}'),
            ],
            const SizedBox(height: 12),
            TextField(controller: cash, decoration: const InputDecoration(labelText: 'Closing cash (optional)')),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Closing note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End shift')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sl<ShiftRepository>().endShift(
        shiftId: active.id,
        closingCash: cash.text.trim().isEmpty ? null : cash.text.trim(),
        closingNote: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Shifts',
      subtitle: 'One business shift can span past midnight. Orders stay on the opening business day.',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        if (_active == null)
          FilledButton.icon(
            style: adminPrimaryButtonStyle,
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start shift'),
          )
        else
          FilledButton.icon(
            style: adminPrimaryButtonStyle,
            onPressed: _end,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('End shift'),
          ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    AdminSurfaceCard(
                      child: _active == null
                          ? const Text('No active shift. Start a shift before or while taking orders so sales attach to the correct business day.')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Active shift', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Text('Business day: ${_active!.businessDay}'),
                                Text('Started: ${DateFormat('EEE, MMM d · h:mm a').format(_active!.startedAt)}'),
                                if (_active!.openingCash != null) Text('Opening cash: ${_active!.openingCash}'),
                                if (_activeSummary != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Orders: ${_activeSummary!.orderCount} · Sales Rs. ${_activeSummary!.salesTotal}'),
                                  Text('Refunds Rs. ${_activeSummary!.refundTotal} · Cancels ${_activeSummary!.cancelCount}'),
                                ],
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text('Recent shifts', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_history.isEmpty)
                      const Text('No shifts recorded yet.')
                    else
                      for (final shift in _history)
                        Card(
                          child: ListTile(
                            title: Text('${shift.businessDay} · ${shift.status}'),
                            subtitle: Text(
                              [
                                'Start ${DateFormat('MMM d, h:mm a').format(shift.startedAt)}',
                                if (shift.endedAt != null) 'End ${DateFormat('MMM d, h:mm a').format(shift.endedAt!)}',
                                'Branch ${shift.branchId}',
                              ].join(' · '),
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}
