import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool isArabic;

  const ErrorStateWidget({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
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
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 36,
                color: AppColors.primary,
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
              message,
              style: AppTypography.body(
                isArabic: isArabic,
                isDark: isDark,
                color: AppColors.textSecondary(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: isArabic ? 'إعادة المحاولة' : 'Try Again',
              onPressed: onRetry,
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
              isArabic: isArabic,
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
