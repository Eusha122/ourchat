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
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(trimmed));
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
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search by username',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(child: Text('Search for people by username'));
    }
    if (_results.isEmpty) {
      return const Center(child: Text('No users found'));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final user = _results[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user.avatarUrl != null
                ? CachedNetworkImageProvider(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null ? const Icon(Icons.person) : null,
          ),
          title: Text('@${user.username}'),
          subtitle: user.displayName != null && user.displayName!.isNotEmpty
              ? Text(user.displayName!)
              : null,
          onTap: () => context.push('/search/${user.username}'),
        );
      },
    );
  }
}
