import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../posts/data/post_models.dart' show PostAuthor;
import '../../users/state/users_providers.dart';
import '../data/album_models.dart';
import '../data/albums_api.dart';
import '../state/gallery_providers.dart';

const _ink = Color(0xFF1B1B1B);
const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);
const _motion = Duration(milliseconds: 250);

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  List<Album> _albums = [];
  bool _isLoading = true;
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
      final albums = await ref.read(albumsApiProvider).fetchAlbums();
      if (!mounted) return;
      setState(() => _albums = albums);
    } on AlbumsApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startCreateFlow() async {
    final created = await showModalBottomSheet<Album>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateAlbumSheet(),
    );
    if (created == null || !mounted) return;
    setState(() => _albums = [created, ..._albums]);
  }

  @override
  Widget build(BuildContext context) {
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
                size: 40,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 18),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _purple,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        // The create tile always leads, so an empty gallery still has an
        // obvious first action instead of a blank screen.
        itemCount: _albums.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateAlbumTile(onTap: _startCreateFlow);
          }
          final album = _albums[index - 1];
          return _AlbumTile(
            album: album,
            myAvatarUrl:
                ref.watch(authControllerProvider).value?.user?.avatarUrl,
            onTap: () async {
              await context.push('/gallery/${album.id}');
              _load();
            },
          );
        },
      ),
    );
  }
}

/// The "picture placeholder with a plus" that opens the invite flow.
class _CreateAlbumTile extends StatefulWidget {
  const _CreateAlbumTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CreateAlbumTile> createState() => _CreateAlbumTileState();
}

class _CreateAlbumTileState extends State<_CreateAlbumTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: _motion,
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _purple.withValues(alpha: 0.28),
              width: 1.4,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_purpleEnd, _purple],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'New shared album',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Invite someone',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF9A9AA5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.myAvatarUrl,
    required this.onTap,
  });

  final Album album;
  final String? myAvatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final other = album.otherMember;
    final withLabel = other == null
        ? 'Just you'
        : 'With ${other.displayName?.isNotEmpty == true ? other.displayName! : other.username}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _purpleEnd.withValues(alpha: 0.16),
                      _purple.withValues(alpha: 0.24),
                    ],
                  ),
                ),
                // Who has access matters more here than a random photo, so
                // the cover is the two members' avatars rather than
                // whichever picture happened to be uploaded first.
                child: Center(
                  child: _OverlappingAvatars(
                    backUrl: myAvatarUrl,
                    backFallback: '?',
                    frontUrl: other?.avatarUrl,
                    frontFallback: other?.username.isNotEmpty == true
                        ? other!.username.characters.first.toUpperCase()
                        : '?',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$withLabel · ${album.itemCount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFF9A9AA5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two circles offset like a Venn diagram — the back one (you) sits behind
/// and to the left, the front one (them) overlaps on top and to the right.
class _OverlappingAvatars extends StatelessWidget {
  const _OverlappingAvatars({
    required this.backUrl,
    required this.backFallback,
    required this.frontUrl,
    required this.frontFallback,
  });

  final String? backUrl;
  final String backFallback;
  final String? frontUrl;
  final String frontFallback;

  static const double _size = 72;
  static const double _overlap = 26;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size * 2 - _overlap,
      height: _size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _RingedAvatar(url: backUrl, fallback: backFallback),
          ),
          Positioned(
            left: _size - _overlap,
            child: _RingedAvatar(url: frontUrl, fallback: frontFallback),
          ),
        ],
      ),
    );
  }
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({required this.url, required this.fallback});

  final String? url;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_purpleEnd, _purple],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          fallback,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Container(
      width: _OverlappingAvatars._size,
      height: _OverlappingAvatars._size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: url == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// Two steps in one sheet: pick the person (same username search as the
/// Search tab), then name the folder and confirm.
class _CreateAlbumSheet extends ConsumerStatefulWidget {
  const _CreateAlbumSheet();

  @override
  ConsumerState<_CreateAlbumSheet> createState() => _CreateAlbumSheetState();
}

class _CreateAlbumSheetState extends ConsumerState<_CreateAlbumSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  Timer? _debounce;
  List<PostAuthor> _results = [];
  PostAuthor? _selected;
  bool _searching = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final users = await ref.read(usersApiProvider).search(query);
        if (!mounted) return;
        setState(() => _results = users);
      } catch (_) {
        if (mounted) setState(() => _results = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _create() async {
    final person = _selected;
    final name = _nameController.text.trim();
    if (person == null || name.isEmpty || _creating) return;

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final album = await ref
          .read(albumsApiProvider)
          .createAlbum(username: person.username, name: name);
      if (mounted) Navigator.of(context).pop(album);
    } on AlbumsApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

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
            const SizedBox(height: 18),
            Text(
              _selected == null ? 'Share an album with' : 'Name this album',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 14),
            if (_selected == null) ..._buildPersonStep() else ..._buildNameStep(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFFD24A4A),
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPersonStep() {
    return [
      _RoundedField(
        controller: _searchController,
        hint: 'Search by username',
        icon: Icons.search_rounded,
        onChanged: _onQueryChanged,
        autofocus: true,
      ),
      const SizedBox(height: 12),
      if (_searching)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
            ),
          ),
        )
      else if (_results.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Type a username to find someone.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFF9A9AA5),
              fontSize: 12,
            ),
          ),
        )
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final user = _results[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: _purple.withValues(alpha: 0.14),
                  backgroundImage: user.avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(user.avatarUrl!),
                  child: user.avatarUrl != null
                      ? null
                      : Text(
                          user.username.characters.first.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: _purple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                title: Text(
                  user.displayName?.isNotEmpty == true
                      ? user.displayName!
                      : user.username,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '@${user.username}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFF9A9AA5),
                    fontSize: 11.5,
                  ),
                ),
                onTap: () => setState(() => _selected = user),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _buildNameStep() {
    final person = _selected!;
    return [
      Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _purple.withValues(alpha: 0.14),
            backgroundImage: person.avatarUrl == null
                ? null
                : CachedNetworkImageProvider(person.avatarUrl!),
            child: person.avatarUrl != null
                ? null
                : Text(
                    person.username.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: _purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sharing with @${person.username}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF6E6E78),
                fontSize: 12.5,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: const Text(
              'Change',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _RoundedField(
        controller: _nameController,
        hint: 'Folder name',
        icon: Icons.folder_rounded,
        autofocus: true,
        onSubmitted: (_) => _create(),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _creating ? null : _create,
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text(
                  'OK',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    ];
  }
}

class _RoundedField extends StatelessWidget {
  const _RoundedField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4FC),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9A9AA5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: _ink,
              ),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Color(0xFF9A9AA5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
