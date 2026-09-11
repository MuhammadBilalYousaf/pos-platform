import 'package:flutter/material.dart';
import '../../config/dependency_injection/injection.dart';
import '../network/query_repository.dart';

class ResourceListPage extends StatefulWidget {
  const ResourceListPage({
    super.key,
    required this.title,
    required this.kind,
    required this.titleKey,
    this.subtitleKey,
  });

  final String title;
  final PosListKind kind;
  final String titleKey;
  final String? subtitleKey;

  @override
  State<ResourceListPage> createState() => _ResourceListPageState();
}

class _ResourceListPageState extends State<ResourceListPage> {
  List<Map<String, dynamic>> _rows = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<QueryRepository>().list(widget.kind);
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_rows.isEmpty) {
      return Center(child: Text('No ${widget.title.toLowerCase()} yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        for (final row in _rows)
          Card(
            child: ListTile(
              title: Text(row[widget.titleKey]?.toString() ?? 'Record'),
              subtitle: widget.subtitleKey == null ? null : Text(row[widget.subtitleKey!]?.toString() ?? ''),
            ),
          ),
      ],
    );
  }
}
