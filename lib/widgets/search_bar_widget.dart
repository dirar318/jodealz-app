import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isArabic;
  final void Function(String)? onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onTap;
  final bool readOnly;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.hintText,
    this.isArabic = true,
    this.onChanged,
    this.onClear,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: AppRadius.radiusInput,
        border: Border.all(color: AppColors.border(isDark)),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: onChanged,
        style: AppTypography.body(
          isArabic: isArabic,
          isDark: isDark,
          color: AppColors.textPrimary(isDark),
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.body(
            isArabic: isArabic,
            isDark: isDark,
            color: AppColors.textDisabled(isDark),
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 20,
            color: AppColors.primary,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.cancel,
                    size: 18,
                    color: AppColors.textDisabled(isDark),
                  ),
                  onPressed: () {
                    controller.clear();
                    onClear?.call();
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
