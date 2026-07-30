import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/chat_models.dart';

class LinkMessageCard extends StatelessWidget {
  const LinkMessageCard({super.key, required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  String get _domain {
    try {
      return Uri.parse(message.linkUrl!).host.replaceFirst('www.', '');
    } catch (_) {
      return message.linkUrl ?? '';
    }
  }

  Future<void> _open() async {
    final url = message.linkUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = isMine
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.primary;
    final foreground = isMine
        ? Theme.of(context).colorScheme.onSurface
        : Colors.white;

    return GestureDetector(
      onTap: _open,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.linkImageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: message.linkImageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, size: 14, color: foreground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _domain,
                          style: TextStyle(fontSize: 12, color: foreground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.linkTitle ?? message.linkUrl ?? 'Shared link',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
