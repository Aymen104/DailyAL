import 'package:flutter/material.dart';

/// A widget that registers a callback to veto attempts by the user to dismiss
/// the enclosing [ModalRoute].
///
/// This widget is similar in behavior to the deprecated `WillPopScope` widget,
/// but implemented using the new [PopScope] widget. It takes the same arguments
/// as `WillPopScope`.
///
/// When a pop is attempted, if [onWillPop] is null, the pop is allowed.
/// Otherwise, [onWillPop] is called. If it returns a [Future] that resolves
/// to `true`, the pop is allowed. If it resolves to `false`, the pop is
/// prevented.
class WillPopWidget extends StatefulWidget {
  /// Creates a widget that registers a callback to veto attempts by the user to
  /// dismiss the enclosing [ModalRoute].
  const WillPopWidget({
    super.key,
    required this.child,
    required this.onWillPop,
  });

  /// The widget below this widget in the tree.
  final Widget child;

  /// Called to veto attempts by the user to dismiss the enclosing [ModalRoute].
  ///
  /// If the callback returns a [Future] that resolves to `false`, the enclosing
  /// route will not be popped. Otherwise, the route will be popped.
  ///
  /// If the callback is null, the enclosing route will be popped unconditionally.
  final Future<bool> Function()? onWillPop;

  @override
  State<WillPopWidget> createState() => _WillPopWidgetState();
}

class _WillPopWidgetState extends State<WillPopWidget> {
  @override
  Widget build(BuildContext context) {
    final onWillPopCallback = widget.onWillPop;

    if (onWillPopCallback == null) {
      // If onWillPop is null, allow popping unconditionally by setting canPop to true.
      return PopScope(
        canPop: true,
        child: widget.child,
      );
    }

    // If onWillPop is provided, we initially set canPop to false.
    // The decision to pop is then handled asynchronously in onPopInvoked.
    return PopScope(
      canPop: false, // Prevent immediate pop to consult onWillPop.
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // This callback is invoked after a pop attempt.
        //
        // If didPop is true, it means the pop attempt was successful.
        // This might happen if canPop was true initially (e.g. onWillPopCallback was null)
        // or if Navigator.pop() was called elsewhere (potentially with a result).
        // In such cases, we don't need to do anything further.
        if (didPop) {
          return;
        }

        // If didPop is false, it means the pop attempt was blocked by canPop: false.
        // Now, we invoke the user-provided onWillPop callback to determine
        // if the pop should proceed.
        final bool shouldPop = await onWillPopCallback();

        // If onWillPopCallback resolves to true, and the widget is still mounted,
        // we manually trigger the pop.
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
        // If shouldPop is false, we do nothing, and the pop remains prevented.
      },
      child: widget.child,
    );
  }
}
