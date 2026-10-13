import 'package:flutter/material.dart';

/// Dispose form controllers after the dialog's closing animation has removed
/// its fields, rather than as soon as Navigator.pop returns its result.
Future<T?> showControllerDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
  bool barrierDismissible = true,
}) {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
  route.completed.then((_) {
    for (final controller in controllers) {
      controller.dispose();
    }
  });
  return Navigator.of(context, rootNavigator: true).push(route);
}
