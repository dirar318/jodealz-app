import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jodeals/services/local_db_service.dart';
import 'package:jodeals/services/cache_service.dart';
import 'package:jodeals/widgets/optimized_image.dart';
import 'package:jodeals/theme/app_colors.dart';
import 'package:jodeals/theme/app_radius.dart';

class ErrorScreen extends StatefulWidget {
  final VoidCallback onRetry;
  final String? errorMessage;
  final String baseUrl;
  final bool isArabic;

  const ErrorScreen({
    super.key,
    required this.onRetry,
    required this.baseUrl,
    this.isArabic = true,
    this.errorMessage,
  });

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen> with SingleTickerProviderStateMixin {
  bool _isLoadingDb = true;
  List<Map<String, dynamic>> _allDeals = [];
  List<Map<String, dynamic>> _filteredDeals = [];
  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategory;
  String _lastSyncedText = '';
  int _dealsCount = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadOfflineData();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadOfflineData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDb = true;
    });

    try {
      final db = LocalDbService.instance;
      final cacheService = CacheService.instance;

      final deals = await db.getDeals();
      final categories = await db.getCategories();
      final count = await db.getDealsCount();
      final syncText = await cacheService.getLastSyncedText(widget.isArabic);

      if (mounted) {
        setState(() {
          _allDeals = deals;
          _filteredDeals = deals;
          _categories = categories;
          _dealsCount = count;
          _lastSyncedText = syncText;
          _isLoadingDb = false;
        });
      }
    } catch (e) {
      debugPrint('ErrorScreen: Error loading offline cache data: $e');
      if (mounted) {
        setState(() {
          _isLoadingDb = false;
        });
      }
    }
  }

  void _filterByCategory(String? categoryName) {
    setState(() {
      _selectedCategory = categoryName;
      if (categoryName == null) {
        _filteredDeals = _allDeals;
      } else {
        _filteredDeals = _allDeals
            .where((deal) => deal['category']?.toString().toLowerCase() == categoryName.toLowerCase())
            .toList();
      }
    });
  }

  String _txt(String ar, String en) => widget.isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    const Color brandRed = AppColors.primary;
    const Color brandAmber = AppColors.secondary;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = AppColors.bg(isDark);
    final Color cardColor = AppColors.card(isDark);
    final Color textColor = AppColors.textPrimary(isDark);
    final Color subtextColor = AppColors.textSecondary(isDark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.lightBg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: _isLoadingDb
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(brandRed),
                  ),
                )
              : Column(
                  children: [
                    _buildOfflineHeader(brandRed, brandAmber, isDark, cardColor, textColor, subtextColor),
                    Expanded(
                      child: _dealsCount > 0
                          ? _buildOfflineBrowser(brandRed, brandAmber, isDark, cardColor, textColor, subtextColor)
                          : _buildNoCacheState(brandRed, brandAmber, isDark, textColor, subtextColor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildOfflineHeader(
    Color brandRed,
    Color brandAmber,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subtextColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: brandRed.withValues(alpha: _pulseAnimation.value),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: brandRed.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                _txt('وضع أوفلاين', 'Offline Mode'),
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: brandRed,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _lastSyncedText,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: subtextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _txt('الصفقات المحفوظة: $_dealsCount', 'Cached Deals: $_dealsCount'),
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: subtextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildOfflineBrowser(
    Color brandRed,
    Color brandAmber,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subtextColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildCategoryPills(brandRed, isDark, cardColor, textColor),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredDeals.isEmpty
              ? Center(
                  child: Text(
                    _txt('لا توجد صفقات في هذا القسم حالياً', 'No cached deals in this category'),
                    style: GoogleFonts.cairo(
                      color: subtextColor,
                      fontSize: 14,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _filteredDeals.length,
                  itemBuilder: (context, index) {
                    final deal = _filteredDeals[index];
                    return _buildDealCard(deal, brandRed, brandAmber, isDark, cardColor, textColor, subtextColor);
                  },
                ),
        ),
        _buildRetryBottomBar(brandRed, brandAmber),
      ],
    );
  }

  Widget _buildCategoryPills(
    Color brandRed,
    bool isDark,
    Color cardColor,
    Color textColor,
  ) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _categories.length + 1,
        itemBuilder: (context, index) {
          final bool isAll = index == 0;
          final dynamic category = isAll ? null : _categories[index - 1];
          final String catName = isAll 
              ? _txt('الكل', 'All') 
              : _txt(category['name_ar'] ?? '', category['name_en'] ?? '');
          final String? catSlug = isAll ? null : category['name_en'];

          final bool isSelected = (isAll && _selectedCategory == null) ||
              (!isAll && _selectedCategory == catSlug);

          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8.0),
            child: ChoiceChip(
              label: Text(
                catName,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : textColor,
                ),
              ),
              selected: isSelected,
              selectedColor: brandRed,
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : brandRed.withValues(alpha: 0.2),
                ),
              ),
              onSelected: (_) => _filterByCategory(catSlug),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDealCard(
    Map<String, dynamic> deal,
    Color brandRed,
    Color brandAmber,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subtextColor,
  ) {
    final title = _txt(deal['title_ar'] ?? '', deal['title_en'] ?? '');
    final price = deal['price'] ?? '';
    final discount = deal['discount'] ?? '';
    final imageUrl = deal['image_url'] ?? '';
    final merchantName = deal['merchant_name'] ?? '';

    String fullImageUrl = imageUrl;
    if (!fullImageUrl.startsWith('http://') && !fullImageUrl.startsWith('https://')) {
      fullImageUrl = widget.baseUrl + (fullImageUrl.startsWith('/') ? '' : '/') + fullImageUrl;
    }

    return Card(
      color: cardColor,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: brandRed.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showDealDetailsModal(deal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OptimizedImage(
                    imageUrl: fullImageUrl,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      child: Center(
                        child: Icon(
                          Icons.local_offer_outlined,
                          color: brandRed,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  if (discount.isNotEmpty)
                    Positioned.directional(
                      textDirection: Directionality.of(context),
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [brandRed, brandAmber],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: brandRed.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '$discount%',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    merchantName,
                    style: GoogleFonts.cairo(
                      color: brandAmber,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (price.isNotEmpty)
                    Text(
                      '$price ${widget.isArabic ? "د.أ" : "JOD"}',
                      style: GoogleFonts.inter(
                        color: brandRed,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRetryBottomBar(Color brandRed, Color brandAmber) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: brandRed.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [brandRed, brandAmber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onRetry,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      _txt('إعادة المحاولة', 'Try Again'),
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoCacheState(
    Color brandRed,
    Color brandAmber,
    bool isDark,
    Color textColor,
    Color subtextColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: brandRed.withValues(alpha: isDark ? 0.12 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: brandRed,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _txt('لا يوجد اتصال بالشبكة', 'Connection Lost'),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.errorMessage ?? _txt(
                'يبدو أنك لست متصلاً بالإنترنت حالياً ولا تتوفر صفقات محفوظة للمشاهدة بدون شبكة.',
                'We cannot connect to JO-Dealz right now, and there are no cached deals available for offline browsing.',
              ),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: subtextColor,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [brandRed, brandAmber],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onRetry,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      _txt('إعادة المحاولة', 'Try Again'),
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDealDetailsModal(Map<String, dynamic> deal) {
    final title = _txt(deal['title_ar'] ?? '', deal['title_en'] ?? '');
    final description = _txt(deal['description_ar'] ?? '', deal['description_en'] ?? '');
    final price = deal['price'] ?? '';
    final discount = deal['discount'] ?? '';
    final imageUrl = deal['image_url'] ?? '';
    final merchantName = deal['merchant_name'] ?? '';
    final location = _txt(deal['location_ar'] ?? '', deal['location_en'] ?? '');

    String fullImageUrl = imageUrl;
    if (!fullImageUrl.startsWith('http://') && !fullImageUrl.startsWith('https://')) {
      fullImageUrl = widget.baseUrl + (fullImageUrl.startsWith('/') ? '' : '/') + fullImageUrl;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color modalBg = AppColors.card(isDark);
        final Color modalTextColor = AppColors.textPrimary(isDark);

        return Container(
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: AppRadius.radiusSheetTop,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(isDark),
                      borderRadius: AppRadius.radiusPill,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: AppRadius.radiusCard,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: OptimizedImage(
                      imageUrl: fullImageUrl,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        child: const Icon(Icons.local_offer, size: 48, color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        merchantName,
                        style: GoogleFonts.cairo(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (discount.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: AppRadius.radiusSm,
                        ),
                        child: Text(
                          '-$discount%',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: modalTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.3,
                  ),
                ),
                if (price.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '$price ${widget.isArabic ? "د.أ" : "JOD"}',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
                const Divider(height: 24, thickness: 1),
                Text(
                  _txt('تفاصيل الصفقة', 'Deal Description'),
                  style: GoogleFonts.cairo(
                    color: modalTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.cairo(
                    color: AppColors.textSecondary(isDark),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          style: GoogleFonts.cairo(
                            color: AppColors.textSecondary(isDark),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: AppRadius.radiusMd,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _txt(
                            'أنت تتصفح هذه الصفقة أوفلاين. يرجى الاتصال بالإنترنت للشراء أو الحجز.',
                            'You are viewing this deal offline. Please connect to the internet to purchase or book.',
                          ),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

