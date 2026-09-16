import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:jodeals/services/local_db_service.dart';
import 'package:jodeals/services/cache_service.dart';
import 'package:jodeals/widgets/deal_card.dart';
import 'package:jodeals/widgets/category_chip.dart';
import 'package:jodeals/widgets/search_bar_widget.dart';
import 'package:jodeals/widgets/empty_state_widget.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';
import 'package:jodeals/theme/app_spacing.dart';
import 'package:jodeals/theme/app_typography.dart';
import 'package:jodeals/widgets/optimized_image.dart';

/// Native Flutter deals feed screen replacing the heavy WebView listing.
///
/// Features:
/// - Infinite scroll pagination from local SQLite cache
/// - Pull-to-refresh with background re-sync
/// - Category filter chips
/// - Search bar with live filtering
/// - Offline-first: shows cached data immediately, syncs in background
class NativeDealsFeedScreen extends StatefulWidget {
  final String baseUrl;
  final String? authToken;
  final bool isArabic;
  final void Function(String url)? onDealTap;

  const NativeDealsFeedScreen({
    super.key,
    required this.baseUrl,
    this.authToken,
    this.isArabic = false,
    this.onDealTap,
  });

  @override
  State<NativeDealsFeedScreen> createState() => _NativeDealsFeedScreenState();
}

class _NativeDealsFeedScreenState extends State<NativeDealsFeedScreen> {
  final _db = LocalDbService.instance;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _deals = [];
  List<Map<String, dynamic>> _categories = [];

  String _selectedCategory = '';
  String _searchQuery = '';
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 20;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300 &&
        pos.userScrollDirection == ScrollDirection.reverse &&
        !_isLoading &&
        _hasMore) {
      _loadMoreDeals();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _hasMore = true;
    });

    // Load categories
    final cats = await _db.getCategories();
    // Load first page of deals
    final deals = await _db.getDeals(
      category: _selectedCategory,
      searchQuery: _searchQuery,
      limit: _pageSize,
      offset: 0,
    );

    if (mounted) {
      setState(() {
        _categories = cats;
        _deals = deals;
        _currentOffset = deals.length;
        _hasMore = deals.length == _pageSize;
        _isLoading = false;
      });
    }

    // Background sync if cache is stale
    _backgroundSync();
  }

  Future<void> _loadMoreDeals() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final more = await _db.getDeals(
      category: _selectedCategory,
      searchQuery: _searchQuery,
      limit: _pageSize,
      offset: _currentOffset,
    );

    if (mounted) {
      setState(() {
        _deals.addAll(more);
        _currentOffset += more.length;
        _hasMore = more.length == _pageSize;
        _isLoading = false;
      });
    }
  }

  Future<void> _backgroundSync() async {
    try {
      final expired = await CacheService.instance.isDealsCacheExpired();
      if (!expired) return;
      await CacheService.instance.syncDealsAndCategories(
        widget.baseUrl,
        token: widget.authToken,
      );
      // Refresh view after sync
      if (mounted) await _loadInitialData();
    } catch (e) {
      debugPrint('NativeDealsFeedScreen: Background sync error: $e');
    }
  }



  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _searchQuery = query.trim();
        _deals = [];
        _currentOffset = 0;
        _hasMore = true;
      });
      _loadInitialData();
    });
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = _selectedCategory == category ? '' : category;
      _deals = [];
      _currentOffset = 0;
      _hasMore = true;
    });
    _loadInitialData();
  }

  String _title(Map<String, dynamic> item, {String enKey = 'name_en', String arKey = 'name_ar'}) {
    return (widget.isArabic ? item[arKey] : item[enKey])?.toString() ?? item[enKey]?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppColors.bg(isDark);
    final textColor = AppColors.textPrimary(isDark);
    final subColor = AppColors.textSecondary(isDark);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark, textColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SearchBarWidget(
                controller: _searchController,
                hintText: widget.isArabic ? 'ابحث عن عرض...' : 'Search deals...',
                isArabic: widget.isArabic,
                onChanged: _onSearchChanged,
                onClear: () => _onSearchChanged(''),
              ),
            ),
            if (_categories.isNotEmpty) _buildCategoryChips(isDark, textColor, subColor),
            Expanded(
              child: _deals.isEmpty && !_isLoading
                  ? EmptyStateWidget(
                      icon: Icons.local_offer_outlined,
                      title: widget.isArabic ? 'لا توجد عروض متاحة' : 'No Deals Found',
                      description: widget.isArabic ? 'لم نتمكن من العثور على أي عروض تطابق بحثك' : 'We could not find any deals matching your query',
                      isArabic: widget.isArabic,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      cacheExtent: 500.0,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: true,
                      itemCount: _deals.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _deals.length) {
                          return _buildLoadingIndicator();
                        }
                        final deal = _deals[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DealCard(
                            deal: deal,
                            baseUrl: widget.baseUrl,
                            isArabic: widget.isArabic,
                            onTap: () {
                              final slug = deal['slug']?.toString() ?? '';
                              if (slug.isNotEmpty) {
                                widget.onDealTap?.call('${widget.baseUrl}/deal.php?slug=$slug');
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppRadius.radiusMd,
            ),
            child: const Icon(Icons.local_offer_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            widget.isArabic ? 'أحدث العروض' : 'Latest Deals',
            style: AppTypography.sectionTitle(
              isArabic: widget.isArabic,
              isDark: isDark,
              color: textColor,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 22),
            onPressed: _loadInitialData,
            tooltip: widget.isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
    );
  }


  Widget _buildCategoryChips(bool isDark, Color textColor, Color subColor) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final catId = cat['name_en']?.toString() ?? '';
          final isSelected = _selectedCategory == catId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CategoryChip(
              label: _title(cat),
              isSelected: isSelected,
              isArabic: widget.isArabic,
              onTap: () => _onCategorySelected(catId),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDealCard(
    Map<String, dynamic> deal,
    Color cardBg,
    Color textColor,
    Color subColor,
    bool isDark,
  ) {
    final title = _title(deal, enKey: 'title_en', arKey: 'title_ar');
    final merchant = deal['merchant_name']?.toString() ?? '';
    final imageUrl = deal['image_url']?.toString() ?? '';
    final discount = deal['discount']?.toString() ?? deal['discount_en']?.toString() ?? '';
    final location = (widget.isArabic ? deal['location_ar'] : deal['location_en'])?.toString() ?? '';
    final isFeatured = (deal['is_featured'] as int? ?? 0) == 1;
    final dealUrl = '${widget.baseUrl}/deals/${deal['id']}';

    return GestureDetector(
      onTap: () => widget.onDealTap?.call(dealUrl),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: isFeatured
              ? Border.all(color: const Color(0xFFFF9F0A).withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(
                children: [
                  _buildDealImage(imageUrl),
                  if (discount.isNotEmpty)
                    Positioned(
                      top: 10,
                      left: widget.isArabic ? null : 10,
                      right: widget.isArabic ? 10 : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF4D4D), Color(0xFFFF9F0A)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          discount,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  if (isFeatured)
                    Positioned(
                      top: 10,
                      right: widget.isArabic ? null : 10,
                      left: widget.isArabic ? 10 : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F0A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              widget.isArabic ? 'مميز' : 'Featured',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: widget.isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontFamily: widget.isArabic ? 'Cairo' : 'Inter',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: widget.isArabic ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (merchant.isNotEmpty) ...[
                        Icon(Icons.storefront_rounded, size: 13, color: subColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            merchant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: subColor, fontFamily: 'Inter'),
                          ),
                        ),
                      ],
                      if (location.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.location_on_rounded, size: 13, color: subColor),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: subColor, fontFamily: 'Inter'),
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
    );
  }

  Widget _buildDealImage(String imageUrl) {
    final isAbsolute = imageUrl.startsWith('http');
    final fullUrl = isAbsolute ? imageUrl : '${widget.baseUrl}$imageUrl';

    if (imageUrl.isEmpty) {
      return Container(
        height: 180,
        color: const Color(0xFFFF4D4D).withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.image_not_supported_rounded, color: Colors.grey, size: 36),
        ),
      );
    }

    return OptimizedImage(
      imageUrl: fullUrl,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: CircularProgressIndicator(
          color: Color(0xFFFF4D4D),
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textColor, Color subColor) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(Icons.local_offer_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        Text(
          widget.isArabic ? 'لا توجد عروض متاحة' : 'No deals available',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
        ),
        const SizedBox(height: 8),
        Text(
          widget.isArabic ? 'اسحب للأسفل للتحديث' : 'Pull down to refresh',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: subColor),
        ),
      ],
    );
  }
}
