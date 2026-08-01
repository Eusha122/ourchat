import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/state/auth_controller.dart';
import '../features/chat/screens/conversation_entry_screen.dart';
import '../features/chats/chats_screen.dart';
import '../features/gallery/screens/album_detail_screen.dart';
import '../features/gallery/screens/gallery_screen.dart';
import '../features/posts/data/post_models.dart';
import '../features/posts/screens/post_detail_screen.dart';
import '../features/posts/screens/upload_post_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/share/screens/share_target_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/users/screens/public_profile_screen.dart';
import '../shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// [Listenable]-based `refreshListenable`, so the router re-evaluates
/// [GoRouter.redirect] whenever auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this.ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthListenable(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register';

      if (authState.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final isAuthenticated = authState.value?.isAuthenticated ?? false;

      if (!isAuthenticated) {
        return isAuthRoute ? null : '/login';
      }

      if (isAuthRoute || location == '/splash') {
        return '/chats';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/upload-post',
        builder: (context, state) => const UploadPostScreen(),
      ),
      GoRoute(
        path: '/share-target',
        builder: (context, state) =>
            ShareTargetScreen(sharedUrl: state.extra as String),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatsScreen(),
                routes: [
                  GoRoute(
                    path: ':conversationId',
                    builder: (context, state) {
                      final extra = state.extra;
                      return ConversationEntryScreen(
                        conversationId: state.pathParameters['conversationId']!,
                        initialOtherParticipant: extra is PostAuthor
                            ? extra
                            : null,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gallery',
                builder: (context, state) => const GalleryScreen(),
                routes: [
                  GoRoute(
                    path: ':albumId',
                    builder: (context, state) => AlbumDetailScreen(
                      albumId: state.pathParameters['albumId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
                routes: [
                  GoRoute(
                    path: ':username',
                    builder: (context, state) => PublicProfileScreen(
                      username: state.pathParameters['username']!,
                    ),
                    routes: [
                      GoRoute(
                        path: ':postId',
                        builder: (context, state) => PostDetailScreen(
                          postId: state.pathParameters['postId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
