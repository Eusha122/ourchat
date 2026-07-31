import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/state/auth_controller.dart';
import '../features/calls/ringtone_settings_sheet.dart';

const _muted = Color(0xFF8A8A8A);
const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);
const _motion = Duration(milliseconds: 250);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = GoRouterState.of(context).uri.pathSegments;
    final isRootDestination =
        segments.length == 1 &&
        const {'chats', 'feed', 'search', 'profile'}.contains(segments.first);

    if (!isRootDestination) {
      return navigationShell;
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAFAFF), Color(0xFFF2F3FF)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top: OurChat logo + avatar
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF312A70).withValues(alpha: 0.08),
                      blurRadius: 50,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: const Color(0xFF312A70).withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: _TopBar(
                    onAvatarTap: () => navigationShell.goBranch(3),
                  ),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: navigationShell,
              ),
            ),
            // Bottom: Navigation bar
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF312A70).withValues(alpha: 0.08),
                      blurRadius: 50,
                      offset: const Offset(0, -18),
                    ),
                    BoxShadow(
                      color: const Color(0xFF312A70).withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: _SegmentedNavigation(
                    currentIndex: navigationShell.currentIndex,
                    onSelected: (index) => navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onAvatarTap});

  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.value?.user;
    final avatarUrl = user?.avatarUrl;

    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_purpleEnd, _purple],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          user?.username.isNotEmpty == true
              ? user!.username.characters.first.toUpperCase()
              : '?',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'OurChat',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF1B1B1B),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: onAvatarTap,
              child: SizedBox(
                width: 40,
                height: 40,
                child: ClipOval(
                  child: avatarUrl == null
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => placeholder,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => const RingtoneSettingsSheet(),
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F4FC),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE9E7F5)),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  size: 19,
                  color: _purple,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SegmentedNavigation extends StatelessWidget {
  const _SegmentedNavigation({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const labels = ['All Chats', 'Gallery', 'Search', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: _motion,
                curve: Curves.easeInOutCubic,
                left: segmentWidth * currentIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_purpleEnd, _purple],
                    ),
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [
                      BoxShadow(
                        color: _purple.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: _purple.withValues(alpha: 0.14),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(index),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: _motion,
                            curve: Curves.easeInOutCubic,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: index == currentIndex
                                  ? Colors.white
                                  : _muted,
                              fontSize: 12.5,
                              height: 1,
                              fontWeight: index == currentIndex
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
