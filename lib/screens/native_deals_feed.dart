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
import 'package:jodeals/theme/app_typography.dart';

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
          if (Navigator.of(context).canPop()) ...[
            BackButton(color: textColor),
            const SizedBox(width: 4),
          ],
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

}
