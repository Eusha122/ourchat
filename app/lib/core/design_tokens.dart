import 'package:flutter/material.dart';

/// Premium design tokens matching the reference Dribbble concept.
/// Based on soft neumorphism + glassmorphism with luxury minimalism.
class DesignTokens {
  // Color Palette
  static const primaryPurple = Color(0xFF5B4CF5);
  static const accentPurple = Color(0xFF7467FF);
  static const background = Color(0xFFF8F8FF);
  static const secondaryBackground = Color(0xFFF1F2FF);
  static const cardWhite = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF9B9B9B);

  // Chat specific colors (from reference)
  static const chatPurpleBg = Color(0xFF6C63FF);
  static const chatPurpleLight = Color(0xFF8B7FFF);

  // Spacing
  static const paddingXSmall = 8.0;
  static const paddingSmall = 12.0;
  static const paddingMedium = 16.0;
  static const paddingLarge = 20.0;
  static const paddingXLarge = 24.0;
  static const paddingXXLarge = 28.0;

  // Border Radius
  static const radiusSmall = 18.0;
  static const radiusMedium = 22.0;
  static const radiusLarge = 28.0;
  static const radiusXLarge = 32.0;
  static const radiusXXLarge = 36.0;
  static const radiusMax = 40.0;

  // Shadows (soft, layered)
  static List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.12),
      blurRadius: 30,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> shadowHeavy = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.15),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // Duration
  static const durationFast = Duration(milliseconds: 150);
  static const durationNormal = Duration(milliseconds: 250);
  static const durationSlow = Duration(milliseconds: 350);

  // Curves
  static const curveSmooth = Curves.easeInOutCubic;
}
