import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/app_shadows.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  danger,
}

enum AppButtonSize {
  small,
  medium,
  large,
}

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Widget? icon;
  final bool isLoading;
  final bool isFullWidth;
  final bool isArabic;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.isArabic = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool disabled = onPressed == null || isLoading;

    // Heights & Paddings
    double height;
    EdgeInsets padding;
    double fontSize;

    switch (size) {
      case AppButtonSize.small:
        height = AppSpacing.buttonHeightSm; // 36px
        padding = const EdgeInsets.symmetric(horizontal: AppSpacing.sm);
        fontSize = 12;
        break;
      case AppButtonSize.large:
        height = 54.0;
        padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg);
        fontSize = 15;
        break;
      case AppButtonSize.medium:
      default:
        height = AppSpacing.buttonHeight; // 48px
        padding = const EdgeInsets.symmetric(horizontal: AppSpacing.button);
        fontSize = 14;
        break;
    }

    // Styling Colors
    Color bgColor;
    Color textColor;
    Border? border;
    List<BoxShadow> shadows = [];
    Gradient? gradient;

    if (disabled && !isLoading) {
      bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
      textColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    } else {
      switch (variant) {
        case AppButtonVariant.primary:
          gradient = AppColors.primaryGradient;
          bgColor = AppColors.primary;
          textColor = Colors.white;
          shadows = isDark ? [] : AppShadows.primaryGlow;
          break;
        case AppButtonVariant.secondary:
          bgColor = isDark ? AppColors.darkCard : AppColors.lightCard;
          textColor = AppColors.textPrimary(isDark);
          border = Border.all(color: AppColors.border(isDark));
          shadows = AppShadows.card(isDark);
          break;
        case AppButtonVariant.outline:
          bgColor = Colors.transparent;
          textColor = AppColors.primary;
          border = Border.all(color: AppColors.primary, width: 1.5);
          break;
        case AppButtonVariant.ghost:
          bgColor = Colors.transparent;
          textColor = AppColors.textPrimary(isDark);
          break;
        case AppButtonVariant.danger:
          bgColor = AppColors.error;
          textColor = Colors.white;
          break;
      }
    }

    Widget content = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          )
        else ...[
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: AppTypography.button(
              isArabic: isArabic,
              isDark: isDark,
              color: textColor,
            ).copyWith(fontSize: fontSize),
          ),
        ],
      ],
    );

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.radiusButton,
        child: InkWell(
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onPressed?.call();
                },
          borderRadius: AppRadius.radiusButton,
          child: Ink(
            decoration: BoxDecoration(
              color: gradient == null ? bgColor : null,
              gradient: gradient,
              borderRadius: AppRadius.radiusButton,
              border: border,
              boxShadow: shadows,
            ),
            padding: padding,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
