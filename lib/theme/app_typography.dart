import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralized Typography system matching the website Noon-inspired scale
/// Arabic font: Cairo
/// English font: Inter
/// Source of truth: D:\Projects\Personal\JoDeals\public_html\assets\css\mobile-typography.css
class AppTypography {
  AppTypography._();

  static TextStyle _font({
    required bool isArabic,
    required double fontSize,
    required FontWeight fontWeight,
    required double height,
    required Color color,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    if (isArabic) {
      return GoogleFonts.cairo(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        color: color,
        letterSpacing: letterSpacing ?? 0.01,
        decoration: decoration,
      );
    } else {
      return GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        color: color,
        letterSpacing: letterSpacing ?? 0.0,
        decoration: decoration,
      );
    }
  }

  // ── Display / Hero: 24px Bold (Line-height 32px / 1.33) ───────────────────
  static TextStyle display({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 32 / 24,
      letterSpacing: -0.2,
      color: color ?? AppColors.textPrimary(isDark),
    );
  }

  // ── Page Title: 20px Bold (Line-height 28px / 1.40) ───────────────────────
  static TextStyle pageTitle({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 28 / 20,
      letterSpacing: -0.2,
      color: color ?? AppColors.textPrimary(isDark),
    );
  }

  // ── Section Title: 18px Bold (Line-height 24px / 1.33) ─────────────────────
  static TextStyle sectionTitle({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 24 / 18,
      letterSpacing: -0.1,
      color: color ?? AppColors.textPrimary(isDark),
    );
  }

  // ── Product / Deal Title: 15px SemiBold (Line-height 20px / 1.33) ─────────
  static TextStyle productTitle({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 20 / 15,
      color: color ?? AppColors.textPrimary(isDark),
    );
  }

  // ── Price Current: 18px-20px Bold (Line-height 24px) ──────────────────────
  static TextStyle price({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 19,
      fontWeight: FontWeight.w700,
      height: 24 / 19,
      letterSpacing: -0.2,
      color: color ?? AppColors.price(isDark),
    );
  }

  // ── Price Old: 13px Regular line-through (Line-height 18px) ───────────────
  static TextStyle priceOld({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 18 / 13,
      decoration: TextDecoration.lineThrough,
      color: color ?? AppColors.priceOld(isDark),
    );
  }

  // ── Merchant / Category: 13px Medium (Line-height 18px) ───────────────────
  static TextStyle merchant({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 18 / 13,
      color: color ?? AppColors.textSecondary(isDark),
    );
  }

  // ── Body Text: 14px Regular (Line-height 20px) ────────────────────────────
  static TextStyle body({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 20 / 14,
      color: color ?? AppColors.textPrimary(isDark),
    );
  }

  // ── Body Small / Meta: 12px Medium (Line-height 16px) ─────────────────────
  static TextStyle meta({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
      color: color ?? AppColors.textSecondary(isDark),
    );
  }

  // ── Button Label: 14px SemiBold (Line-height 20px) ────────────────────────
  static TextStyle button({required bool isArabic, required bool isDark, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 20 / 14,
      color: color ?? Colors.white,
    );
  }

  // ── Badge Label: 11px-12px ExtraBold (Line-height 16px) ───────────────────
  static TextStyle badge({required bool isArabic, Color? color}) {
    return _font(
      isArabic: isArabic,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      height: 16 / 11,
      color: color ?? Colors.white,
    );
  }
}
