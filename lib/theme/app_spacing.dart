import 'package:flutter/material.dart';

/// Centralized Spacing system matching website 8-point spacing scale
/// Source of truth: D:\Projects\Personal\JoDeals\public_html\assets\css\mobile-design-system.css
class AppSpacing {
  AppSpacing._();

  static const double space1 = 4.0; // 0.5 unit (xs)
  static const double space2 = 8.0; // 1 unit (sm)
  static const double space3 = 12.0; // 1.5 units (md)
  static const double space4 = 16.0; // 2 units (lg)
  static const double space5 = 20.0; // 2.5 units (xl)
  static const double space6 = 24.0; // 3 units (2xl)
  static const double space8 = 32.0; // 4 units (3xl)
  static const double space10 = 40.0; // 5 units
  static const double space12 = 48.0; // 6 units

  // ── Semantic Aliases ───────────────────────────────────────────────────────
  static const double xs = space1; // 4px
  static const double sm = space2; // 8px
  static const double md = space3; // 12px
  static const double lg = space4; // 16px
  static const double xl = space5; // 20px
  static const double xxl = space6; // 24px
  static const double xxxl = space8; // 32px

  static const double page = space4; // 16px page horizontal padding
  static const double section = space6; // 24px gap between sections
  static const double card = space3; // 12px card internal padding
  static const double cardLg = space4; // 16px large card padding
  static const double grid = space3; // 12px grid / card gap
  static const double button = space4; // 16px button horizontal padding

  // ── Touch & Component Heights ──────────────────────────────────────────────
  static const double touchTarget = 44.0; // 44px min touch target
  static const double headerHeight = 60.0; // 60px header
  static const double buttonHeight = 48.0; // 48px standard button
  static const double buttonHeightSm = 36.0; // 36px small button
  static const double inputHeight = 48.0; // 48px input field
  static const double bottomNavHeight = 60.0; // 60px bottom nav
}
