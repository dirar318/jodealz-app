import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool isArabic;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.isArabic = true,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.meta(
              isArabic: isArabic,
              isDark: isDark,
              color: AppColors.textPrimary(isDark),
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          enabled: enabled,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          style: AppTypography.body(
            isArabic: isArabic,
            isDark: isDark,
            color: AppColors.textPrimary(isDark),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            errorText: errorText,
            hintStyle: AppTypography.body(
              isArabic: isArabic,
              isDark: isDark,
              color: AppColors.textDisabled(isDark),
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: AppRadius.radiusInput,
              borderSide: BorderSide(color: AppColors.border(isDark)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.radiusInput,
              borderSide: BorderSide(color: AppColors.border(isDark)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: AppRadius.radiusInput,
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: AppRadius.radiusInput,
              borderSide: BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderRadius: AppRadius.radiusInput,
              borderSide: BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
