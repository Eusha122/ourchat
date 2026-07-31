import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/state/auth_controller.dart';

const _ink = Color(0xFF1B1B1B);
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

    final user = ref.watch(authControllerProvider).value?.user;
    final rawName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.username.trim() ?? 'Johan';
    final name = rawName.isEmpty
        ? 'Johan'
        : '${rawName[0].toUpperCase()}${rawName.substring(1)}';

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAFAFF), Color(0xFFF2F3FF)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 0),
                  child: _Header(
                    name: name,
                    onSearch: () => navigationShell.goBranch(2),
                    onMenu: () => navigationShell.goBranch(3),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _SegmentedNavigation(
                    currentIndex: navigationShell.currentIndex,
                    onSelected: (index) => navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: navigationShell,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.onSearch,
    required this.onMenu,
  });

  final String name;
  final VoidCallback onSearch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hello,',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _muted,
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _ink,
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),
        _CircleControl(
          semanticLabel: 'Search',
          onTap: onSearch,
          icon: const _SearchGlyph(),
        ),
        const SizedBox(width: 11),
        _CircleControl(
          semanticLabel: 'Profile',
          onTap: onMenu,
          icon: const _MoreGlyph(),
        ),
      ],
    );
  }
}

class _CircleControl extends StatefulWidget {
  const _CircleControl({
    required this.semanticLabel,
    required this.onTap,
    required this.icon,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget icon;

  @override
  State<_CircleControl> createState() => _CircleControlState();
}

class _CircleControlState extends State<_CircleControl> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: _motion,
          curve: Curves.easeInOutCubic,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _ink, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF332D69).withValues(alpha: 0.08),
                  blurRadius: 50,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: const Color(0xFF332D69).withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: widget.icon,
          ),
        ),
      ),
    );
  }
}

class _SearchGlyph extends StatelessWidget {
  const _SearchGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 17,
      height: 17,
      child: CustomPaint(painter: _SearchPainter()),
    );
  }
}

class _SearchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(7, 7), 5.2, paint);
    canvas.drawLine(const Offset(11, 11), const Offset(15.5, 15.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vertical three-dot glyph, matching the reference exactly.
class _MoreGlyph extends StatelessWidget {
  const _MoreGlyph();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [_Dot(), SizedBox(height: 3.2), _Dot(), SizedBox(height: 3.2), _Dot()],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 2.8,
      height: 2.8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: _ink, shape: BoxShape.circle),
      ),
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
