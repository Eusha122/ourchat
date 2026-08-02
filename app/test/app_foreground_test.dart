// Regression coverage for the bug where a real read-receipt outage was
// traced to AppForeground.update() gating on `== resumed`: desktop reports
// `inactive` for a window that's created and visible but not yet
// OS-confirmed as focused, and unlike mobile it often never follows with an
// explicit `resumed` afterward — so a single `inactive` event permanently
// latched isForeground to false and silently blocked every read receipt for
// the rest of the session, even while the conversation was plainly on
// screen. Confirmed live: zero POST /read requests across a whole session
// with 5 conversation loads and 4 sent messages, and the DB read cursor
// stayed NULL throughout.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourchat/core/app_foreground.dart';

void main() {
  test('starts optimistic: foreground before any lifecycle event fires', () {
    // Mirrors app startup order — widgets exist and may need to know
    // visibility before the platform has dispatched anything.
    expect(AppForeground.instance.isForeground, isTrue);
  });

  test('inactive does not count as backgrounded', () {
    // The exact state that caused the outage: desktop on window
    // create/focus-loss, or a transient mobile overlay (incoming call,
    // control center) where the user has not left the screen.
    AppForeground.instance.update(AppLifecycleState.inactive);
    expect(AppForeground.instance.isForeground, isTrue);
  });

  test('resumed counts as foreground', () {
    AppForeground.instance.update(AppLifecycleState.paused);
    AppForeground.instance.update(AppLifecycleState.resumed);
    expect(AppForeground.instance.isForeground, isTrue);
  });

  test('paused counts as backgrounded', () {
    AppForeground.instance.update(AppLifecycleState.paused);
    expect(AppForeground.instance.isForeground, isFalse);
  });

  test('detached counts as backgrounded', () {
    AppForeground.instance.update(AppLifecycleState.detached);
    expect(AppForeground.instance.isForeground, isFalse);
  });

  test('hidden counts as backgrounded', () {
    AppForeground.instance.update(AppLifecycleState.hidden);
    expect(AppForeground.instance.isForeground, isFalse);
  });

  test(
    'the exact desktop sequence that caused the outage no longer '
    'latches backgrounded: created -> inactive, no further event',
    () {
      // No prior state (simulates a fresh singleton): only `inactive` ever
      // arrives, precisely as observed on the Windows build. Must stay
      // foreground so read receipts keep firing.
      AppForeground.instance.update(AppLifecycleState.inactive);
      expect(AppForeground.instance.isForeground, isTrue);
    },
  );
}
