import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// Tracks whether the app is in the foreground.
///
/// Reading `WidgetsBinding.instance.lifecycleState` directly is unsafe for
/// this: it is nullable and, per the Flutter docs, is only populated once the
/// platform dispatches a `SystemChannels.lifecycle` notification. Before that
/// first notification it is `null`, so a `!= AppLifecycleState.resumed` check
/// silently reports "backgrounded" for an app that is plainly on screen — which
/// is exactly how read receipts ended up never being sent.
///
/// The Flutter docs name `didChangeAppLifecycleState` as the supported way to
/// observe this, which is what this does. It starts optimistic (`true`): the
/// engine only runs Dart while the app is live, so foreground is the correct
/// assumption until the platform says otherwise.
class AppForeground {
  AppForeground._();

  static final AppForeground instance = AppForeground._();

  final ValueNotifier<bool> _resumed = ValueNotifier<bool>(true);

  ValueListenable<bool> get listenable => _resumed;

  bool get isForeground => _resumed.value;

  void update(AppLifecycleState state) {
    _resumed.value = state == AppLifecycleState.resumed;
  }
}

/// Feeds [AppForeground] from a single app-level observer.
class AppForegroundObserver extends StatefulWidget {
  const AppForegroundObserver({super.key, required this.child});

  final Widget child;

  @override
  State<AppForegroundObserver> createState() => _AppForegroundObserverState();
}

class _AppForegroundObserverState extends State<AppForegroundObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If the platform already reported a state before this mounted, adopt it;
    // otherwise the optimistic default stands.
    final known = WidgetsBinding.instance.lifecycleState;
    if (known != null) AppForeground.instance.update(known);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppForeground.instance.update(state);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
