import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/app_shadows.dart';

class CategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final bool isArabic;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.isArabic = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.radiusMd,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        borderRadius: AppRadius.radiusMd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkCard : AppColors.lightCard),
            borderRadius: AppRadius.radiusMd,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.borderLight(isDark),
              width: 1,
            ),
            boxShadow: isSelected ? AppShadows.primaryGlow : AppShadows.card(isDark),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? const Color(0xFFcbd5e1) : AppColors.primary),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTypography.meta(
                  isArabic: isArabic,
                  isDark: isDark,
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimary(isDark),
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
