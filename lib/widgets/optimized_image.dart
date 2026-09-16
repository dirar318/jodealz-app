import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:jodeals/widgets/skeleton_loader.dart';

/// A premium, memory-efficient lazy-loaded image widget.
/// Utilizes cached network images with memory constraints [memCacheWidth] and [memCacheHeight]
/// to decode images at target render sizes, dramatically reducing GPU memory usage during scrolling.
class OptimizedImage extends StatelessWidget {
  final String? imageUrl;
  final String? baseUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.baseUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (baseUrl != null && baseUrl!.isNotEmpty) {
      final cleanBase = baseUrl!.endsWith('/') ? baseUrl!.substring(0, baseUrl!.length - 1) : baseUrl!;
      final cleanPath = url.startsWith('/') ? url : '/$url';
      return '$cleanBase$cleanPath';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = imageUrl?.trim() ?? '';
    if (rawUrl.isEmpty) {
      return _buildErrorPlaceholder(context);
    }
    final resolvedUrl = _resolveUrl(rawUrl);

    final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final int? targetWidth = width != null && width != double.infinity ? (width! * pixelRatio).round() : null;
    final int? targetHeight = height != null && height != double.infinity ? (height! * pixelRatio).round() : null;

    final imageWidget = CachedNetworkImage(
      imageUrl: resolvedUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: targetWidth,
      memCacheHeight: targetHeight,
      placeholder: (context, url) =>
          placeholder ??
          SkeletonLoader(
            width: width ?? double.infinity,
            height: height ?? 180,
            borderRadius: borderRadius ?? BorderRadius.zero,
          ),
      errorWidget: (context, url, error) => errorWidget ?? _buildErrorPlaceholder(context),
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 150),
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          size: 28,
        ),
      ),
    );
  }
}

