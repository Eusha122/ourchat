import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/socket_service.dart';
import '../../auth/state/auth_controller.dart';
import '../../users/state/users_providers.dart';
import '../data/conversations_api.dart';

final conversationsApiProvider = Provider<ConversationsApi>((ref) {
  return ConversationsApi(ref.watch(apiClientProvider).dio);
});

/// Rebuilds (and reconnects) whenever the access token changes; disposed
/// automatically when it becomes null (e.g. on logout).
final socketServiceProvider = Provider<SocketService?>((ref) {
  final accessToken = ref.watch(
    authControllerProvider.select((state) => state.value?.accessToken),
  );
  if (accessToken == null) return null;

  final service = SocketService(accessToken: accessToken);
  service.connect();
  ref.onDispose(service.dispose);
  return service;
});
