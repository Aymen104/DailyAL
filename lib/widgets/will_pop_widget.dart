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
    return WillPopScope(
      onWillPop: onWillPopCallback,
      child: widget.child,
    );
  }
}
