import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../posts/data/post_models.dart';
import '../users/data/users_api.dart';
import '../users/state/users_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PostAuthor> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _isLoading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(trimmed),
    );
  }

  Future<void> _search(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await ref.read(usersApiProvider).search(query);
      if (!mounted) return;
      setState(() => _results = results);
    } on UsersApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14332D69),
                  blurRadius: 50,
                  offset: Offset(0, 18),
                ),
                BoxShadow(
                  color: Color(0x0A332D69),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 18),
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF5D4EF5),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: false,
                    onChanged: _onChanged,
                    cursorColor: const Color(0xFF5D4EF5),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF1B1B1B),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: 'Search by username',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF8A8A8A),
                        fontSize: 12.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
              ],
            ),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 8,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF5D4EF5),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(child: _StateLabel(_error!));
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(child: _StateLabel('Search for people by username'));
    }
    if (_results.isEmpty) {
      return const Center(child: _StateLabel('No users found'));
    }
    return ListView.builder(
      itemCount: _results.length,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemBuilder: (context, index) => _SearchResult(
        user: _results[index],
        onTap: () => context.push('/search/${_results[index].username}'),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Color(0xFF8A8A8A),
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({required this.user, required this.onTap});

  final PostAuthor user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 67,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14332D69),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                  BoxShadow(
                    color: Color(0x0A332D69),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: user.avatarUrl == null
                    ? const ColoredBox(
                        color: Color(0xFFE7E3FF),
                        child: Icon(
                          Icons.person_rounded,
                          color: Color(0xFF5D4EF5),
                          size: 21,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: user.avatarUrl!,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF1B1B1B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (user.displayName?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.displayName!,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF8A8A8A),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFFAAA6B4),
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}
