import 'package:flutter/material.dart';

/// Shows a dialog only when the page [context] is still mounted/active.
/// Returns null if the context is already invalid (avoids release crashes).
Future<T?> showSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) async {
  if (!context.mounted) return null;
  try {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: builder,
    );
  } catch (error) {
    // Release builds otherwise terminate on invalid BuildContext.
    debugPrint('showSafeDialog skipped: $error');
    return null;
  }
}

/// Runs [action] on the next frame after the current dialog route has closed.
void runAfterDialogClosed(State state, Future<void> Function() action) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!state.mounted) return;
    try {
      await action();
    } catch (error, stack) {
      debugPrint('runAfterDialogClosed error: $error\n$stack');
      if (state.mounted) {
        ScaffoldMessenger.maybeOf(state.context)?.showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  });
}
