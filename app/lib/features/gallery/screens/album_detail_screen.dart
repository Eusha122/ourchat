import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/album_models.dart';
import '../data/albums_api.dart';
import '../state/gallery_providers.dart';

const _ink = Color(0xFF1B1B1B);
const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);

class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  AlbumDetail? _detail;
  bool _isLoading = true;
  String? _error;
  int _uploading = 0;

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
      final detail = await ref.read(albumsApiProvider).fetchAlbum(widget.albumId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on AlbumsApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final files = await picker.pickMultipleMedia();
    if (files.isEmpty || !mounted) return;

    final api = ref.read(albumsApiProvider);
    final added = <AlbumItem>[];
    String? failure;

    // One caption prompt per file, in sequence, rather than one shared
    // caption for the whole batch — each photo gets its own comment.
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!mounted) break;
      // Not dismissible: returning from the native picker delivers a stray
      // pointer event that was landing on the barrier and closing this
      // instantly, so the upload ran before the caption could be typed.
      final caption = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => _CaptionSheet(
          file: file,
          position: files.length > 1 ? '${i + 1} of ${files.length}' : null,
        ),
      );
      if (!mounted) break;

      setState(() => _uploading++);
      try {
        added.add(
          await api.uploadItem(
            albumId: widget.albumId,
            filePath: file.path,
            fileName: file.name,
            caption: caption,
          ),
        );
      } on AlbumsApiException catch (error) {
        failure = error.message;
      } finally {
        if (mounted) setState(() => _uploading--);
      }
    }

    if (!mounted) return;
    if (added.isNotEmpty && _detail != null) {
      setState(() {
        _detail = AlbumDetail(
          album: _detail!.album,
          items: [...added.reversed, ..._detail!.items],
        );
      });
    }
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _open(AlbumItem item) async {
    final items = _detail?.items ?? const <AlbumItem>[];
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AlbumImageViewer(items: items, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final other = detail?.album.otherMember;
    final subtitle = other == null
        ? 'Shared album'
        : 'Shared with @${other.username}';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FD),
      body: SafeArea(
        child: Column(
          children: [
            // Header card, matching the conversation screen's treatment.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF312A70).withValues(alpha: 0.07),
                    blurRadius: 40,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(10, 12, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail?.album.name ?? 'Album',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFF9A9AA5),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      // Sits on the right, low on the screen — clear of the content but
      // still within thumb reach.
      floatingActionButton: _UploadButton(
        busy: _uploading > 0,
        onTap: _pickAndUpload,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFB9B9C4),
                size: 38,
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF9A9AA5),
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: _purple),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = _detail?.items ?? const <AlbumItem>[];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_purpleEnd, _purple],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.26),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nothing here yet',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _ink,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap the plus button to add photos and videos. '
                'Both of you will see them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF9A9AA5),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _purple,
      onRefresh: _load,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return GestureDetector(
            onTap: () => _open(item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: item.displayUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const ColoredBox(
                      color: Color(0xFFEDECF7),
                    ),
                    errorWidget: (_, _, _) => const ColoredBox(
                      color: Color(0xFFEDECF7),
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Color(0xFFB9B9C4),
                        size: 20,
                      ),
                    ),
                  ),
                  if (item.type == AlbumItemType.video)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x66000000),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_purpleEnd, _purple],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _purple.withValues(alpha: 0.38),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}

/// A true full-bleed viewer: no AppBar (even a transparent one still
/// reserves its own height in the Scaffold's layout, which was shrinking the
/// image into a letterboxed "frame" instead of using the whole display).
/// The back button and caption float as overlays on top of an image that
/// fills the entire screen, the way a device's own gallery app does.
/// A true full-bleed, swipeable viewer. No AppBar (even a transparent one
/// reserves its own height in the Scaffold's layout, which was letterboxing
/// the photo into a "frame"); the back button and caption float on top of an
/// image that fills the whole display, the way a device gallery app does.
class _AlbumImageViewer extends StatefulWidget {
  const _AlbumImageViewer({required this.items, required this.initialIndex});

  final List<AlbumItem> items;
  final int initialIndex;

  @override
  State<_AlbumImageViewer> createState() => _AlbumImageViewerState();
}

class _AlbumImageViewerState extends State<_AlbumImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final name = item.uploader.displayName?.isNotEmpty == true
        ? item.uploader.displayName!
        : '@${item.uploader.username}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (page) => setState(() => _index = page),
            itemBuilder: (context, index) {
              final pageItem = widget.items[index];
              if (pageItem.type == AlbumItemType.video) {
                return _VideoPage(item: pageItem);
              }
              // SizedBox.expand makes BoxFit.contain size against the full
              // screen rather than the image's intrinsic pixels, so
              // InteractiveViewer pans and zooms across the entire display.
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: SizedBox.expand(
                  child: CachedNetworkImage(
                    imageUrl: pageItem.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white24),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const Spacer(),
                    if (widget.items.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.items.length}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB0000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.caption?.isNotEmpty == true) ...[
                        Text(
                          item.caption!,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'Uploaded by $name',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Color(0xFFD8D8D8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Videos stay in the swipe order so paging matches the grid, but playback
/// is handed to the device's own player rather than bundling a video engine.
class _VideoPage extends StatelessWidget {
  const _VideoPage({required this.item});

  final AlbumItem item;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumbnailUrl != null)
          CachedNetworkImage(imageUrl: item.thumbnailUrl!, fit: BoxFit.contain),
        Center(
          child: GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(item.url),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              width: 74,
              height: 74,
              decoration: const BoxDecoration(
                color: Color(0x88000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Preview-and-comment step shown once per picked file before it uploads.
class _CaptionSheet extends StatefulWidget {
  const _CaptionSheet({required this.file, this.position});

  final XFile file;
  final String? position;

  @override
  State<_CaptionSheet> createState() => _CaptionSheetState();
}

class _CaptionSheetState extends State<_CaptionSheet> {
  final _controller = TextEditingController();

  bool get _isVideo {
    final ext = widget.file.name.toLowerCase();
    return ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.m4v') ||
        ext.endsWith('.webm');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E1EC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Add a comment',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (widget.position != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.position!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF9A9AA5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 180,
                child: _isVideo
                    ? const ColoredBox(
                        color: Color(0xFFF4F3FF),
                        child: Icon(
                          Icons.videocam_rounded,
                          color: _purple,
                          size: 34,
                        ),
                      )
                    : Image.file(File(widget.file.path), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F4FC),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: _ink,
                ),
                decoration: const InputDecoration(
                  hintText: 'Write a comment (optional)',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF9A9AA5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                // The sheet is deliberately barrier-proof, so skipping needs
                // to be an explicit action rather than a tap-outside.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Color(0xFF9A9AA5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Post',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
