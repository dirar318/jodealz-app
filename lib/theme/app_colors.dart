import 'package:flutter/material.dart';

/// Centralized color palette matching the JoDeals website design system
/// Source of truth: D:\Projects\Personal\JoDeals\public_html\assets\css\mobile-design-system.css
class AppColors {
  AppColors._();

  // ── Brand & Accent Colors ──────────────────────────────────────────────────
  static const Color primary = Color(0xFFF52A3B); // --ds-color-primary
  static const Color primaryHover = Color(0xFFB50045); // --ds-color-primary-hover
  static const Color primaryActive = Color(0xFF900037); // --ds-color-primary-active
  static const Color primaryLight = Color(0x1AF52A3B); // rgba(245, 42, 59, 0.10)
  static const Color primaryGlow = Color(0x33F52A3B); // rgba(245, 42, 59, 0.20)

  static const Color secondary = Color(0xFFFF7A2F); // --ds-color-secondary
  static const Color secondaryHover = Color(0xFFFF5E1F); // --ds-color-secondary-hover
  static const Color secondaryLight = Color(0x1FFF7A2F); // rgba(255, 122, 47, 0.12)
  static const Color secondaryGlow = Color(0x33FF7A2F); // rgba(255, 122, 47, 0.20)

  static const Color accentYellow = Color(0xFFFFC61A); // --ds-color-accent-yellow
  static const Color success = Color(0xFF10B981); // --ds-color-success
  static const Color successLight = Color(0x1A10B981); // rgba(16, 185, 129, 0.10)
  static const Color error = Color(0xFFEF4444); // Error red
  static const Color warning = Color(0xFFF59E0B); // Warning amber
  static const Color info = Color(0xFF3B82F6); // Info blue

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient mainGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFB50045),
      Color(0xFFF52A3B),
      Color(0xFFFF7A2F),
      Color(0xFFFFC61A),
    ],
    stops: [0.0, 0.40, 0.75, 1.0],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF52A3B),
      Color(0xFFFF7A2F),
    ],
  );

  static const LinearGradient discountBadgeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF52A3B),
      Color(0xFFFF3B3B),
    ],
  );

  static const LinearGradient exclusiveBadgeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED),
      Color(0xFF4F46E5),
    ],
  );

  // ── Light Theme Surfaces & Text ───────────────────────────────────────────
  static const Color lightBg = Color(0xFFF7F7F9); // --ds-color-bg-alt
  static const Color lightBgAlt = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF); // --ds-color-card
  static const Color lightCardHover = Color(0xFFF7F7F9);
  static const Color lightOverlay = Color(0x991E1E1E); // rgba(30, 30, 30, 0.60)

  static const Color lightTextPrimary = Color(0xFF1E1E1E); // --ds-color-text-primary
  static const Color lightTextSecondary = Color(0xFF6B7280); // --ds-color-text-secondary
  static const Color lightTextDisabled = Color(0xFF9CA3AF); // --ds-color-text-disabled
  static const Color lightTextInverse = Color(0xFFFFFFFF);
  static const Color lightPrice = Color(0xFFF52A3B);
  static const Color lightPriceOld = Color(0xFF6B7280);

  static const Color lightBorder = Color(0xFFE8E8E8); // --ds-color-border
  static const Color lightBorderLight = Color(0xCCE8E8E8); // rgba(232, 232, 232, 0.80)
  static const Color lightBorderFocus = Color(0xFFF52A3B);

  // ── Dark Theme Surfaces & Text ────────────────────────────────────────────
  static const Color darkBg = Color(0xFF020617); // --ds-color-bg (dark)
  static const Color darkBgAlt = Color(0xFF0F172A); // --ds-color-bg-alt (dark)
  static const Color darkCard = Color(0xFF0F172A); // --ds-color-card (dark)
  static const Color darkCardHover = Color(0xFF1E293B);
  static const Color darkOverlay = Color(0xB3000000); // rgba(0, 0, 0, 0.70)

  static const Color darkTextPrimary = Color(0xFFF1F5F9); // --ds-color-text-primary (dark)
  static const Color darkTextSecondary = Color(0xFF94A3B8); // --ds-color-text-secondary (dark)
  static const Color darkTextDisabled = Color(0xFF64748B); // --ds-color-text-disabled (dark)
  static const Color darkPrice = Color(0xFFFF6B6B);
  static const Color darkPriceOld = Color(0xFF64748B);

  static const Color darkBorder = Color(0xFF1E293B); // --ds-color-border (dark)
  static const Color darkBorderLight = Color(0xCC1E293B); // rgba(30, 41, 59, 0.80)
  static const Color darkBorderFocus = Color(0xFFF52A3B);

  // ── Shimmer / Skeleton ────────────────────────────────────────────────────
  static const Color lightSkeletonBase = Color(0xFFE2E8F0);
  static const Color lightSkeletonHighlight = Color(0xFFF1F5F9);
  static const Color darkSkeletonBase = Color(0xFF1E293B);
  static const Color darkSkeletonHighlight = Color(0xFF334155);

  // ── Dynamic Helpers Based on Brightness (Forced Light Mode) ──────────────
  static Color bg([bool? isDark]) => lightBg;
  static Color bgAlt([bool? isDark]) => lightBgAlt;
  static Color card([bool? isDark]) => lightCard;
  static Color cardHover([bool? isDark]) => lightCardHover;
  static Color textPrimary([bool? isDark]) => lightTextPrimary;
  static Color textSecondary([bool? isDark]) => lightTextSecondary;
  static Color textDisabled([bool? isDark]) => lightTextDisabled;
  static Color price([bool? isDark]) => lightPrice;
  static Color priceOld([bool? isDark]) => lightPriceOld;
  static Color border([bool? isDark]) => lightBorder;
  static Color borderLight([bool? isDark]) => lightBorderLight;
}

