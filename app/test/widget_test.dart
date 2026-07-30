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

    expect(find.text('Chat list will appear here (Phase 5)'), findsOneWidget);
  });

  testWidgets('Bottom nav switches to the Feed tab', (tester) async {
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

    await tester.tap(find.widgetWithText(NavigationDestination, 'Feed'));
    await tester.pumpAndSettle();

    expect(find.text('Post feed will appear here (Phase 3)'), findsOneWidget);
  });
}
