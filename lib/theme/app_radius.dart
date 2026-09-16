import 'package:flutter/material.dart';

/// Centralized Border Radius tokens matching the JoDeals website design system
/// Source of truth: D:\Projects\Personal\JoDeals\public_html\assets\css\mobile-design-system.css
class AppRadius {
  AppRadius._();

  static const double xs = 4.0; // --ds-radius-xs
  static const double sm = 8.0; // --ds-radius-sm (badges, small buttons)
  static const double md = 12.0; // --ds-radius-md (buttons, category cards)
  static const double lg = 16.0; // --ds-radius-lg (deal cards, inputs, search)
  static const double xl = 20.0; // --ds-radius-xl (bottom navigation)
  static const double xxl = 24.0; // --ds-radius-2xl (bottom sheets, modals)
  static const double pill = 999.0; // --ds-radius-pill (badges, round buttons)

  // ── Semantic Component Aliases ─────────────────────────────────────────────
  static const double button = md; // 12px
  static const double card = lg; // 16px
  static const double cardSm = md; // 12px (category cards)
  static const double search = lg; // 16px
  static const double badge = pill; // 999px
  static const double badgeSquare = sm; // 8px
  static const double input = lg; // 16px
  static const double bottomNav = xl; // 20px
  static const double sheet = xxl; // 24px

  // ── BorderRadius Objects ───────────────────────────────────────────────────
  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius radiusXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius radiusPill = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius radiusButton = radiusMd;
  static const BorderRadius radiusCard = radiusLg;
  static const BorderRadius radiusInput = radiusLg;
  static const BorderRadius radiusSheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}
