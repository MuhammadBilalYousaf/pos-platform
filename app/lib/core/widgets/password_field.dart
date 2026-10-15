import 'package:flutter/material.dart';

/// Password input with a show / hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.helperText,
    this.hintText,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints = const [AutofillHints.password],
    this.textInputAction,
    this.onSubmitted,
    this.decoration,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? hintText;
  final bool enabled;
  final bool autofocus;
  final Iterable<String> autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;
  final FocusNode? focusNode;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.decoration ??
        InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          hintText: widget.hintText,
        );
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      keyboardType: TextInputType.visiblePassword,
      inputFormatters: const [],
      decoration: base.copyWith(
        labelText: base.labelText ?? widget.label,
        helperText: base.helperText ?? widget.helperText,
        hintText: base.hintText ?? widget.hintText,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Hide password' : 'Show password',
          onPressed: widget.enabled ? () => setState(() => _visible = !_visible) : null,
          icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        ),
      ),
    );
  }
}
