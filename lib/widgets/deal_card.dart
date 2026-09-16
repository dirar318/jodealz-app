import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/app_shadows.dart';
import 'optimized_image.dart';

class DealCard extends StatefulWidget {
  final Map<String, dynamic> deal;
  final String baseUrl;
  final bool isArabic;
  final VoidCallback? onTap;
  final void Function(bool isFavorite)? onFavoriteToggle;
  final bool isFavorite;

  const DealCard({
    super.key,
    required this.deal,
    required this.baseUrl,
    this.isArabic = true,
    this.onTap,
    this.onFavoriteToggle,
    this.isFavorite = false,
  });

  @override
  State<DealCard> createState() => _DealCardState();
}

class _DealCardState extends State<DealCard> with SingleTickerProviderStateMixin {
  late bool _isFav;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _isFav = widget.isFavorite;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant DealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      setState(() {
        _isFav = widget.isFavorite;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '';
    final num? val = num.tryParse(price.toString());
    if (val == null) return price.toString();
    if (val == val.toInt()) {
      return '${val.toInt()} ${widget.isArabic ? "د.أ" : "JOD"}';
    }
    return '${val.toStringAsFixed(2)} ${widget.isArabic ? "د.أ" : "JOD"}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final deal = widget.deal;

    final String title = (widget.isArabic ? (deal['title_ar'] ?? deal['title']) : (deal['title_en'] ?? deal['title'])) ?? '';
    final String merchant = (widget.isArabic ? (deal['merchant_ar'] ?? deal['merchant_name'] ?? deal['merchant']) : (deal['merchant_en'] ?? deal['merchant_name'] ?? deal['merchant'])) ?? '';
    final String? imageUrl = deal['image_url'] ?? deal['image'];
    final dynamic priceNew = deal['discount_price'] ?? deal['deal_price'] ?? deal['price'];
    final dynamic priceOld = deal['original_price'] ?? deal['old_price'];
    final dynamic discountVal = deal['discount_percentage'] ?? deal['discount'];

    String discountText = '';
    if (discountVal != null && discountVal.toString().isNotEmpty) {
      final String strVal = discountVal.toString().replaceAll('%', '').replaceAll('-', '').trim();
      final num? numVal = num.tryParse(strVal);
      if (numVal != null && numVal > 0) {
        discountText = '-${numVal.toInt()}%';
      }
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _animController.forward(),
        onTapUp: (_) => _animController.reverse(),
        onTapCancel: () => _animController.reverse(),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card(isDark),
            borderRadius: AppRadius.radiusCard,
            border: Border.all(color: AppColors.borderLight(isDark), width: 1),
            boxShadow: AppShadows.card(isDark),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1:1 Aspect Ratio Image Container with Badges
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OptimizedImage(
                      imageUrl: imageUrl,
                      baseUrl: widget.baseUrl,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                    ),

                    // Discount Badge (Top Start)
                    if (discountText.isNotEmpty)
                      PositionedDirectional(
                        top: AppSpacing.sm,
                        start: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: AppColors.discountBadgeGradient,
                            borderRadius: AppRadius.radiusXs,
                            boxShadow: AppShadows.primaryGlow,
                          ),
                          child: Text(
                            discountText,
                            style: AppTypography.badge(isArabic: widget.isArabic),
                          ),
                        ),
                      ),

                    // Favorite Button (Top End)
                    PositionedDirectional(
                      top: AppSpacing.sm,
                      end: AppSpacing.sm,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isFav = !_isFav;
                            });
                            widget.onFavoriteToggle?.call(_isFav);
                          },
                          borderRadius: AppRadius.radiusPill,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDark 
                                  ? const Color(0xE60F172A) 
                                  : const Color(0xF2FFFFFF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? const Color(0x33FFFFFF) : const Color(0xCCE8E8E8),
                              ),
                              boxShadow: AppShadows.sm,
                            ),
                            child: Icon(
                              _isFav ? Icons.favorite : Icons.favorite_border,
                              color: _isFav ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280)),
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Card Details Body
              Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Merchant Name
                    if (merchant.isNotEmpty) ...[
                      Text(
                        merchant,
                        style: AppTypography.merchant(
                          isArabic: widget.isArabic,
                          isDark: isDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                    ],

                    // Deal Title (2 lines clamp)
                    Text(
                      title,
                      style: AppTypography.productTitle(
                        isArabic: widget.isArabic,
                        isDark: isDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // Prices Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (priceNew != null)
                          Text(
                            _formatPrice(priceNew),
                            style: AppTypography.price(
                              isArabic: widget.isArabic,
                              isDark: isDark,
                            ),
                          ),
                        if (priceOld != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatPrice(priceOld),
                            style: AppTypography.priceOld(
                              isArabic: widget.isArabic,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
