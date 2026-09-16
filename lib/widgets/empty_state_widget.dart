import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onAction;
  final bool isArabic;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionText,
    this.onAction,
    this.isArabic = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderLight(isDark)),
              ),
              child: Icon(
                icon,
                size: 36,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTypography.sectionTitle(
                isArabic: isArabic,
                isDark: isDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: AppTypography.body(
                isArabic: isArabic,
                isDark: isDark,
                color: AppColors.textSecondary(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 24),
              AppButton(
                text: actionText!,
                onPressed: onAction,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.small,
                isArabic: isArabic,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
