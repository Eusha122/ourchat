import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ourchat/app.dart';
import 'package:ourchat/features/auth/data/auth_models.dart';
import 'package:ourchat/features/auth/state/auth_controller.dart';
import 'package:ourchat/features/auth/state/auth_state.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;

  @override
  Future<AuthState> build() async => _initial;
}

const _testUser = PublicUser(
  id: 'user-1',
  username: 'tester',
  email: 'tester@example.com',
);

Widget _appWith(AuthState initialAuthState) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => _FakeAuthController(initialAuthState),
      ),
    ],
    child: const OurChatApp(),
  );
}

/// Taps a pill in the custom top tab bar by its label (there's no
/// NavigationDestination widget anymore - it's a plain GestureDetector+Text).
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Shows the login screen when unauthenticated', (tester) async {
    await tester.pumpWidget(_appWith(const AuthState.unauthenticated()));
    await tester.pumpAndSettle();

    expect(find.text('OurChat'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('Lands on the Chats tab once authenticated', (tester) async {
    await tester.pumpWidget(
      _appWith(
        AuthState.authenticated(
          user: _testUser,
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello,'), findsOneWidget);
    expect(find.text('Larry Machigo'), findsWidgets);
  });

  testWidgets('Top tab bar switches to the Gallery tab', (tester) async {
    await tester.pumpWidget(
      _appWith(
        AuthState.authenticated(
          user: _testUser,
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Gallery');

    // Gallery is currently a static "coming soon" placeholder (no network
    // call), so this just proves navigation to the tab worked.
    expect(find.text('Gallery is coming soon'), findsOneWidget);
  });

  testWidgets('Profile tab shows the user and toggles the edit form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appWith(
        AuthState.authenticated(
          user: _testUser,
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Profile');

    expect(find.text('@tester'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Search tab prompts for a query before searching', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appWith(
        AuthState.authenticated(
          user: _testUser,
          accessToken: 'access',
          refreshToken: 'refresh',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapTab(tester, 'Search');

    expect(find.text('Search for people by username'), findsOneWidget);
  });
}
