import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../data/album_models.dart';
import '../data/albums_api.dart';
import '../state/gallery_providers.dart';

const _ink = Color(0xFF1B1B1B);
const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);

/// video_player ships Android/iOS implementations only; on desktop the
/// controller would throw MissingPluginException, so those platforms hand
/// playback to the OS instead.
bool get _hasInlineVideo =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

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

  // Up to this many files upload at once. Sequential uploads meant total
  // time was the sum of every file's upload time; a small concurrent pool
  // overlaps the network requests instead.
  static const _maxConcurrentUploads = 3;

  int _batchTotal = 0;
  int _batchDone = 0;

  bool get _isUploading => _batchTotal > 0;

  // Ordered so the badge on each thumbnail can show 1, 2, 3... in the order
  // they were tapped, not just an unordered "selected" flag.
  final List<String> _selectedIds = [];
  bool _deleting = false;

  bool get _isSelecting => _selectedIds.isNotEmpty;

  void _toggleSelect(String itemId) {
    setState(() {
      if (!_selectedIds.remove(itemId)) _selectedIds.add(itemId);
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

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
      final detail = await ref
          .read(albumsApiProvider)
          .fetchAlbum(widget.albumId);
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
    if (_isUploading) return;

    final picker = ImagePicker();
    // A modern phone camera photo can easily be 10-30MB straight off the
    // sensor; that size (not the network) was what made uploads feel slow.
    // These caps still comfortably exceed a phone screen's resolution — no
    // visible quality loss — while cutting typical file size by 5-10x.
    // Untouched for videos: image_picker only applies these to images.
    final files = await picker.pickMultipleMedia(
      imageQuality: 88,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (files.isEmpty || !mounted) return;

    setState(() {
      _batchTotal = files.length;
      _batchDone = 0;
    });

    final api = ref.read(albumsApiProvider);
    final added = <AlbumItem>[];
    String? failure;

    for (var start = 0; start < files.length; start += _maxConcurrentUploads) {
      if (!mounted) break;
      final chunk = files.skip(start).take(_maxConcurrentUploads);
      final results = await Future.wait(
        chunk.map((file) async {
          try {
            return await api.uploadItem(
              albumId: widget.albumId,
              filePath: file.path,
              fileName: file.name,
            );
          } on AlbumsApiException catch (error) {
            failure = error.message;
            return null;
          } finally {
            if (mounted) setState(() => _batchDone++);
          }
        }),
      );
      added.addAll(results.whereType<AlbumItem>());
    }

    if (!mounted) return;
    setState(() {
      _batchTotal = 0;
      _batchDone = 0;
      if (added.isNotEmpty && _detail != null) {
        _detail = AlbumDetail(
          album: _detail!.album,
          items: [...added.reversed, ..._detail!.items],
        );
      }
    });
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure!)));
    }
  }

  Future<void> _open(AlbumItem item) async {
    final items = _detail?.items ?? const <AlbumItem>[];
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AlbumViewer(items: items, initialIndex: index),
      ),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0 || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? 'Delete this item?' : 'Delete $count items?'),
        content: Text(
          count == 1
              ? 'This permanently deletes it for both of you. This cannot be undone.'
              : 'This permanently deletes all $count for both of you. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final detail = _detail;
    if (detail == null) return;
    final ids = List<String>.of(_selectedIds);

    setState(() {
      _deleting = true;
      _detail = AlbumDetail(
        album: detail.album,
        items: detail.items.where((i) => !ids.contains(i.id)).toList(),
      );
      _selectedIds.clear();
    });

    final api = ref.read(albumsApiProvider);
    String? failure;
    await Future.wait(
      ids.map((id) async {
        try {
          await api.deleteItem(albumId: widget.albumId, itemId: id);
        } on AlbumsApiException catch (error) {
          failure = error.message;
        }
      }),
    );

    if (!mounted) return;
    setState(() => _deleting = false);
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure!)));
      _load();
    }
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
                    icon: Icon(
                      _isSelecting ? Icons.close_rounded : Icons.arrow_back_rounded,
                      color: _ink,
                    ),
                    onPressed: _isSelecting
                        ? _clearSelection
                        : () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: _isSelecting
                        ? Text(
                            '${_selectedIds.length} selected',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          )
                        : Column(
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
                  if (_isSelecting)
                    IconButton(
                      icon: _deleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE24C4C),
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFE24C4C),
                            ),
                      onPressed: _deleting ? null : _confirmDeleteSelected,
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: _isSelecting
          ? null
          : _UploadButton(
              done: _batchDone,
              total: _batchTotal,
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
          final selectionIndex = _selectedIds.indexOf(item.id);
          final selected = selectionIndex != -1;

          return GestureDetector(
            onTap: () {
              if (_isSelecting) {
                _toggleSelect(item.id);
              } else {
                _open(item);
              }
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _toggleSelect(item.id);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item.displayUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const ColoredBox(color: Color(0xFFEDECF7)),
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
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _purple, width: 3),
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '${selectionIndex + 1}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Doubles as the upload indicator: a determinate ring around the percentage
/// while a batch is in flight, so bulk uploads show real progress instead of
/// an opaque spinner.
class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.done, required this.total, required this.onTap});

  /// [total] is 0 when idle; while uploading, [done] counts completed files
  /// out of [total] (e.g. "2/10"), not bytes — several files upload at once,
  /// so a single byte-accurate percentage wouldn't mean much anyway.
  final int done;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final busy = total > 0;
    final fraction = busy ? done / total : 0.0;

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
            ? Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: TweenAnimationBuilder<double>(
                      // Smooths the jump each time a file finishes so the
                      // ring sweeps instead of stepping.
                      tween: Tween(begin: 0, end: fraction),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      builder: (context, animated, _) =>
                          CircularProgressIndicator(
                            value: animated,
                            strokeWidth: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(
                              Colors.white,
                            ),
                          ),
                    ),
                  ),
                  Text(
                    '$done/$total',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}

/// Full-bleed, swipeable viewer. No AppBar — even a transparent one reserves
/// layout height, which letterboxed the media into a "frame".
class _AlbumViewer extends StatefulWidget {
  const _AlbumViewer({required this.items, required this.initialIndex});

  final List<AlbumItem> items;
  final int initialIndex;

  @override
  State<_AlbumViewer> createState() => _AlbumViewerState();
}

class _AlbumViewerState extends State<_AlbumViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chromeVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Otherwise the very first swipe always shows a spinner: nothing fetches
    // a neighbouring image until the page holding it actually builds.
    _precacheNeighbors(_index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _precacheNeighbors(int index) {
    for (final neighbor in [index - 1, index + 1]) {
      if (neighbor < 0 || neighbor >= widget.items.length) continue;
      final item = widget.items[neighbor];
      // Video frames aren't cheap to prefetch this way — the player buffers
      // its own stream once its page builds.
      if (item.type != AlbumItemType.image) continue;
      precacheImage(CachedNetworkImageProvider(item.url), context);
    }
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
            onPageChanged: (page) {
              setState(() {
                _index = page;
                // Otherwise chrome hidden on a previous page leaves the next
                // one with no visible back button.
                _chromeVisible = true;
              });
              _precacheNeighbors(page);
            },
            itemBuilder: (context, index) {
              final pageItem = widget.items[index];
              if (pageItem.type == AlbumItemType.video) {
                return _VideoPage(
                  key: ValueKey(pageItem.id),
                  item: pageItem,
                  // Only the visible page owns a decoder; swiping away
                  // releases it so several videos never decode at once.
                  isActive: index == _index,
                  onToggleChrome: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                );
              }
              return GestureDetector(
                onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                child: InteractiveViewer(
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
                ),
              );
            },
          ),
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Stack(
                fit: StackFit.expand,
                children: [
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
                          child: Text(
                            'Uploaded by $name',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Color(0xFFD8D8D8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline player with Instagram-style behaviour: autoplays when its page is
/// on screen, pauses and rewinds when swiped away, tap toggles play/pause,
/// and a scrubbable progress bar sits at the bottom.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.item,
    required this.isActive,
    required this.onToggleChrome,
  });

  final AlbumItem item;
  final bool isActive;
  final VoidCallback onToggleChrome;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _failed = false;
  bool _showPlayIcon = false;

  @override
  void initState() {
    super.initState();
    if (_hasInlineVideo) _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.item.url),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      // If the page was swiped away mid-initialize, State.dispose() has
      // already torn this controller down — disposing again here would be a
      // double dispose.
      if (!mounted) return;
      setState(() => _initializing = false);
      if (widget.isActive) await controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failed = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.isActive && !oldWidget.isActive) {
      controller.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      controller
        ..pause()
        ..seekTo(Duration.zero);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showPlayIcon = true;
      } else {
        controller.play();
        _showPlayIcon = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Desktop: no inline implementation, so keep the poster + hand off to
    // the system player.
    if (!_hasInlineVideo) {
      return _ExternalVideoFallback(item: widget.item);
    }
    if (_initializing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.thumbnailUrl != null)
            CachedNetworkImage(
              imageUrl: widget.item.thumbnailUrl!,
              fit: BoxFit.contain,
            ),
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white70),
              ),
            ),
          ),
        ],
      );
    }
    if (_failed || _controller == null) {
      return _ExternalVideoFallback(item: widget.item);
    }

    final controller = _controller!;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlayback,
          onLongPress: widget.onToggleChrome,
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio > 0
                  ? controller.value.aspectRatio
                  : 16 / 9,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        // Big play badge only while paused, matching how Instagram surfaces
        // the resume affordance without covering playback.
        if (_showPlayIcon)
          IgnorePointer(
            child: Center(
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 54),
              child: _VideoScrubber(controller: controller),
            ),
          ),
        ),
      ],
    );
  }
}

/// Position readout plus a draggable progress bar, rebuilt straight from the
/// controller so it stays in step with playback.
class _VideoScrubber extends StatelessWidget {
  const _VideoScrubber({required this.controller});

  final VideoPlayerController controller;

  static String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = value.position;
        return Row(
          children: [
            Text(
              _format(position),
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  // Guard against a zero/unknown duration producing NaN.
                  value: duration.inMilliseconds == 0
                      ? 0
                      : position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                  max: duration.inMilliseconds == 0
                      ? 1
                      : duration.inMilliseconds.toDouble(),
                  onChanged: duration.inMilliseconds == 0
                      ? null
                      : (v) => controller.seekTo(
                          Duration(milliseconds: v.round()),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _format(duration),
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFD8D8D8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ExternalVideoFallback extends StatelessWidget {
  const _ExternalVideoFallback({required this.item});

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
