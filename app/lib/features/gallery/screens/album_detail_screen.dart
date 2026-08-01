import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
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

  // Batch upload progress, spread across every file in the batch so the
  // button reads 0-100% for the whole selection rather than per file.
  int _batchTotal = 0;
  int _batchDone = 0;
  double _currentFraction = 0;

  bool get _isUploading => _batchTotal > 0;

  double get _uploadProgress {
    if (_batchTotal == 0) return 0;
    return ((_batchDone + _currentFraction) / _batchTotal).clamp(0.0, 1.0);
  }

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
    final files = await picker.pickMultipleMedia();
    if (files.isEmpty || !mounted) return;

    setState(() {
      _batchTotal = files.length;
      _batchDone = 0;
      _currentFraction = 0;
    });

    final api = ref.read(albumsApiProvider);
    final added = <AlbumItem>[];
    String? failure;

    for (final file in files) {
      if (!mounted) break;
      try {
        added.add(
          await api.uploadItem(
            albumId: widget.albumId,
            filePath: file.path,
            fileName: file.name,
            onProgress: (fraction) {
              if (mounted) setState(() => _currentFraction = fraction);
            },
          ),
        );
      } on AlbumsApiException catch (error) {
        failure = error.message;
      } finally {
        if (mounted) {
          setState(() {
            _batchDone++;
            _currentFraction = 0;
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _batchTotal = 0;
      _batchDone = 0;
      _currentFraction = 0;
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
      ).showSnackBar(SnackBar(content: Text(failure)));
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
      floatingActionButton: _UploadButton(
        progress: _isUploading ? _uploadProgress : null,
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
                ],
              ),
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
  const _UploadButton({required this.progress, required this.onTap});

  /// Null when idle; 0.0-1.0 while uploading.
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final busy = value != null;

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
                      // Smooths the jumps between chunk callbacks so the ring
                      // sweeps instead of stepping.
                      tween: Tween(begin: 0, end: value),
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
                    '${(value * 100).round()}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 13,
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
            onPageChanged: (page) => setState(() {
              _index = page;
              // Otherwise chrome hidden on a previous page leaves the next
              // one with no visible back button.
              _chromeVisible = true;
            }),
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
