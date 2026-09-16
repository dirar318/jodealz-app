import 'package:flutter/material.dart';

/// Centralized Elevation Shadows matching website CSS
/// Source of truth: D:\Projects\Personal\JoDeals\public_html\assets\css\mobile-design-system.css
class AppShadows {
  AppShadows._();

  // ── Light Theme Shadows ───────────────────────────────────────────────────
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x14000000), // rgba(0, 0, 0, 0.08)
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1F000000), // rgba(0, 0, 0, 0.12)
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x29000000), // rgba(0, 0, 0, 0.16)
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0x33F52A3B), // rgba(245, 42, 59, 0.20)
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> secondaryGlow = [
    BoxShadow(
      color: Color(0x33FF7A2F), // rgba(255, 122, 47, 0.20)
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  // ── Dark Theme Shadows ────────────────────────────────────────────────────
  static const List<BoxShadow> darkSm = [
    BoxShadow(
      color: Color(0x40000000), // rgba(0, 0, 0, 0.25)
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> darkMd = [
    BoxShadow(
      color: Color(0x59000000), // rgba(0, 0, 0, 0.35)
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> darkLg = [
    BoxShadow(
      color: Color(0x73000000), // rgba(0, 0, 0, 0.45)
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
  ];

  // ── Semantic Helpers (Forced Light Mode) ───────────────────────────────────
  static List<BoxShadow> card([bool? isDark]) => sm;
  static List<BoxShadow> float([bool? isDark]) => md;
  static List<BoxShadow> modal([bool? isDark]) => lg;
}

