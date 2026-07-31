import 'package:flutter/material.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              width: 420,
              padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5146C4).withValues(alpha: 0.12),
                    blurRadius: 34,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B7FFF), Color(0xFF5642D8)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF624FE7).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 9),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: Colors.white,
                      size: 31,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Gallery is coming soon',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: const Color(0xFF2F2850),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A beautiful place for every shared moment is on its way.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF7C7690), height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECE9FF),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'IN DEVELOPMENT',
                      style: TextStyle(
                        color: Color(0xFF5A48D5),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
