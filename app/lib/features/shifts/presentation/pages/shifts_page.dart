import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/utils/order_totals.dart';
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
              'Count the cash in the drawer first. All sales stay on this business day until you end the shift.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cash,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening cash',
                helperText: 'Cash already in the drawer (recommended)',
              ),
            ),
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
        openingCash: cash.text.trim().isEmpty ? '0' : cash.text.trim(),
        openingNote: note.text.trim().isEmpty ? null : note.text.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      cash.dispose();
      note.dispose();
    }
  }

  Future<void> _end() async {
    final active = _active;
    if (active == null) return;
    final summary = _activeSummary ?? await sl<ShiftRepository>().summarizeShift(active);
    if (!mounted) return;

    final cash = TextEditingController(text: summary.expectedCash);
    final note = TextEditingController();
    var varianceLabel = '0.00';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            varianceLabel = summary.varianceFor(cash.text);
            final variance = moneyOrZero(varianceLabel);
            final varianceText = variance == Decimal.zero
                ? 'Drawer matches expected'
                : variance > Decimal.zero
                    ? 'Over by Rs. $varianceLabel'
                    : 'Short by Rs. ${moneyString(variance.abs())}';
            return AlertDialog(
              title: const Text('End shift — cash count'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Business day: ${active.businessDay}'),
                    Text('Started: ${DateFormat('MMM d, h:mm a').format(active.startedAt)}'),
                    const SizedBox(height: 10),
                    Text('Orders: ${summary.orderCount} · Sales Rs. ${summary.salesTotal}'),
                    Text('Refunds Rs. ${summary.refundTotal} · Cancels ${summary.cancelCount}'),
                    Text('Cash sales Rs. ${summary.cashSalesTotal} · Cash refunds Rs. ${summary.cashRefundTotal}'),
                    Text(
                      'Expected in drawer: Rs. ${summary.expectedCash}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '(Opening ${active.openingCash ?? '0'} + cash sales − cash refunds)',
                      style: const TextStyle(fontSize: 12, color: kAdminMuted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cash,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Counted closing cash',
                        helperText: 'Count the notes/coins in the drawer now',
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      varianceText,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: variance == Decimal.zero
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'Closing note (optional)')),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(
                  style: adminPrimaryButtonStyle,
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('End shift'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) {
      cash.dispose();
      note.dispose();
      return;
    }
    try {
      final counted = cash.text.trim().isEmpty ? '0' : cash.text.trim();
      final variance = summary.varianceFor(counted);
      await sl<ShiftRepository>().endShift(
        shiftId: active.id,
        closingCash: counted,
        closingNote: note.text.trim().isEmpty ? null : note.text.trim(),
        expectedCash: summary.expectedCash,
        cashVariance: variance,
        cashSalesTotal: summary.cashSalesTotal,
        cashRefundTotal: summary.cashRefundTotal,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift closed. Cash variance: Rs. $variance')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      cash.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Shifts',
      subtitle: 'Open a shift, take sales, then count the drawer. Variance = counted − expected.',
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
                          ? const Text(
                              'No active shift. Start a shift before taking orders so sales attach to the correct business day and cash can be reconciled.',
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active shift',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text('Business day: ${_active!.businessDay}'),
                                Text('Started: ${DateFormat('EEE, MMM d · h:mm a').format(_active!.startedAt)}'),
                                Text('Opening cash: Rs. ${_active!.openingCash ?? '0'}'),
                                if (_activeSummary != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Orders: ${_activeSummary!.orderCount} · Sales Rs. ${_activeSummary!.salesTotal}'),
                                  Text('Refunds Rs. ${_activeSummary!.refundTotal} · Cancels ${_activeSummary!.cancelCount}'),
                                  Text(
                                    'Expected drawer now: Rs. ${_activeSummary!.expectedCash}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
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
                                if (shift.expectedCash != null) 'Expected Rs. ${shift.expectedCash}',
                                if (shift.closingCash != null) 'Counted Rs. ${shift.closingCash}',
                                if (shift.cashVariance != null) 'Variance Rs. ${shift.cashVariance}',
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
