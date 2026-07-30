import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../chat/data/chat_models.dart';
import '../chat/data/conversations_api.dart';
import '../chat/state/chat_providers.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    ref.listenManual(socketServiceProvider, (previous, next) {
      next?.onConversationUpdate.listen(_onConversationUpdated);
    }, fireImmediately: true);
  }

  void _onConversationUpdated(ConversationUpdateEvent event) {
    if (!mounted) return;
    setState(() {
      final index = _conversations.indexWhere(
        (c) => c.id == event.conversationId,
      );
      if (index == -1) {
        _load();
        return;
      }
      final updated = _conversations[index].copyWith(
        lastMessage: event.lastMessage,
        unreadCount: _conversations[index].unreadCount + 1,
      );
      _conversations
        ..removeAt(index)
        ..insert(0, updated);
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final conversations = await ref
          .read(conversationsApiProvider)
          .fetchConversations();
      if (!mounted) return;
      setState(() => _conversations = conversations);
    } on ConversationsApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Text(
                  'No chats yet. Find someone in Search to say hi!',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          final other = conversation.otherParticipant;
          final lastMessage = conversation.lastMessage;
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: other.avatarUrl != null
                  ? CachedNetworkImageProvider(other.avatarUrl!)
                  : null,
              child: other.avatarUrl == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(
              other.displayName?.isNotEmpty == true
                  ? other.displayName!
                  : '@${other.username}',
            ),
            subtitle: lastMessage != null
                ? Text(
                    lastMessage.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const Text('Say hi!'),
            trailing: conversation.unreadCount > 0
                ? CircleAvatar(
                    radius: 10,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  )
                : null,
            onTap: () async {
              await context.push('/chats/${conversation.id}', extra: other);
              _load();
            },
          );
        },
      ),
    );
  }
}
