import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../auth/state/auth_controller.dart';
import '../data/users_api.dart';

/// Rebuilds whenever the access token changes (login, refresh, logout),
/// keeping the Authorization header current.
final apiClientProvider = Provider<ApiClient>((ref) {
  final accessToken = ref.watch(
    authControllerProvider.select((state) => state.value?.accessToken),
  );
  return ApiClient(
    accessToken: accessToken,
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).refreshAccessToken(),
  );
});

final usersApiProvider = Provider<UsersApi>((ref) {
  return UsersApi(ref.watch(apiClientProvider).dio);
});
