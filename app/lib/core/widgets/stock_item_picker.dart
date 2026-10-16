import 'package:flutter/material.dart';
import '../../features/admin/data/admin_repository.dart';

/// Searchable stock / ingredient selector for inventory and recipe dialogs.
class StockItemPicker extends StatefulWidget {
  const StockItemPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label = 'Stock item',
    this.enabled = true,
    this.excludeIds = const {},
  });

  final List<IngredientOption> items;
  final String? value;
  final ValueChanged<IngredientOption?> onChanged;
  final String label;
  final bool enabled;
  final Set<String> excludeIds;

  @override
  State<StockItemPicker> createState() => _StockItemPickerState();
}

class _StockItemPickerState extends State<StockItemPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<IngredientOption> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return widget.items.where((item) {
      if (widget.excludeIds.contains(item.id) && item.id != widget.value) return false;
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          item.id.toLowerCase().contains(q) ||
          item.kind.toLowerCase().contains(q) ||
          item.unit.toLowerCase().contains(q);
    }).toList();
  }

  IngredientOption? _find(String? id) {
    if (id == null) return null;
    for (final item in widget.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final selected = _find(widget.value);
    final valueInFiltered = selected != null && filtered.any((item) => item.id == selected.id) ? selected.id : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: 'Search ${widget.label.toLowerCase()}',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No matching stock items.',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('picker-$valueInFiltered-${filtered.length}'),
            initialValue: valueInFiltered,
            decoration: InputDecoration(labelText: widget.label),
            isExpanded: true,
            items: [
              for (final item in filtered)
                DropdownMenuItem(
                  value: item.id,
                  child: Text('${item.name} (${item.unit})${item.kind.toUpperCase() == 'MIXTURE' ? ' · mixture' : ''}'),
                ),
            ],
            onChanged: widget.enabled
                ? (value) {
                    widget.onChanged(_find(value));
                  }
                : null,
          ),
      ],
    );
  }
}
