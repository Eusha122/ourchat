import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../chat/data/chat_models.dart';
import '../../chat/data/conversations_api.dart';
import '../../chat/state/chat_providers.dart';

class ShareTargetScreen extends ConsumerStatefulWidget {
  const ShareTargetScreen({super.key, required this.sharedUrl});

  final String sharedUrl;

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _sendingToConversationId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _sendTo(Conversation conversation) async {
    setState(() => _sendingToConversationId = conversation.id);
    try {
      await ref
          .read(conversationsApiProvider)
          .sendLink(conversation.id, widget.sharedUrl);
      if (!mounted) return;
      context.pushReplacement(
        '/chats/${conversation.id}',
        extra: conversation.otherParticipant,
      );
    } on ConversationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sendingToConversationId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share to...')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.link),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.sharedUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
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
      return const Center(
        child: Text('Start a chat with someone first, then share to them.'),
      );
    }

    return ListView.builder(
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final other = conversation.otherParticipant;
        final isSending = _sendingToConversationId == conversation.id;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: other.avatarUrl != null
                ? CachedNetworkImageProvider(other.avatarUrl!)
                : null,
            child: other.avatarUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Text(
            other.displayName?.isNotEmpty == true
                ? other.displayName!
                : '@${other.username}',
          ),
          trailing: isSending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _sendingToConversationId == null
              ? () => _sendTo(conversation)
              : null,
        );
      },
    );
  }
}
