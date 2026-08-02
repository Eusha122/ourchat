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
  final auth = ref.watch(
    authControllerProvider.select((state) => state.value),
  );
  final accessToken = auth?.accessToken;
  final userId = auth?.user?.id;
  if (accessToken == null || userId == null) return null;

  final service = SocketService(
    accessToken: accessToken,
    currentUserId: userId,
    refreshAccessToken: () =>
        ref.read(authControllerProvider.notifier).refreshAccessToken(),
  );
  service.connect();
  ref.onDispose(service.dispose);
  return service;
});

/// The conversation currently open on screen, if any. Set/cleared by
/// ConversationScreen so the global notification listener can skip showing
/// a banner for the chat you're already looking at.
class ActiveConversationController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? conversationId) => state = conversationId;
}

final activeConversationIdProvider =
    NotifierProvider<ActiveConversationController, String?>(
  ActiveConversationController.new,
);
