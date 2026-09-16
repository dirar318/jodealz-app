import 'package:flutter/material.dart';

class Shimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const Shimmer({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController.unbounded(vsync: this)
      ..repeat(min: -0.5, max: 1.5, period: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [
                0.1,
                0.3,
                0.4,
              ],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              transform: _SlidingGradientTransform(slidePercent: _shimmerController.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

class SkeletonPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        children: [
          // Header Row
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonPlaceholder(width: 140, height: 28, borderRadius: 6),
              SkeletonPlaceholder(width: 44, height: 44, borderRadius: 22),
            ],
          ),
          const SizedBox(height: 24),
          // Large Promo Banner Slider
          const SkeletonPlaceholder(width: double.infinity, height: 180, borderRadius: 16),
          const SizedBox(height: 28),
          // Horizontal Category Badges Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonPlaceholder(width: 100, height: 20),
              SkeletonPlaceholder(width: 60, height: 16),
            ],
          ),
          const SizedBox(height: 12),
          // Horizontal Category Badges List
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return const Padding(
                  padding: EdgeInsets.only(right: 12.0),
                  child: SkeletonPlaceholder(width: 80, height: 38, borderRadius: 19),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          // Featured Deals Title
          const SkeletonPlaceholder(width: 150, height: 20),
          const SizedBox(height: 16),
          // Vertical Cards list
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 2,
            itemBuilder: (context, index) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonPlaceholder(width: double.infinity, height: 150, borderRadius: 16),
                    SizedBox(height: 10),
                    SkeletonPlaceholder(width: 180, height: 18),
                    SizedBox(height: 6),
                    SkeletonPlaceholder(width: 120, height: 14),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class DealsSkeleton extends StatelessWidget {
  const DealsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        children: [
          // Search & Filter Box
          const SkeletonPlaceholder(width: double.infinity, height: 50, borderRadius: 12),
          const SizedBox(height: 20),
          // Grid layout of Deals
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SkeletonPlaceholder(width: double.infinity, height: 0, borderRadius: 16),
                  ),
                  SizedBox(height: 10),
                  SkeletonPlaceholder(width: 110, height: 16),
                  SizedBox(height: 6),
                  SkeletonPlaceholder(width: 70, height: 14),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Avatar Circle
            const SkeletonPlaceholder(width: 90, height: 90, borderRadius: 45),
            const SizedBox(height: 16),
            // User Name
            const SkeletonPlaceholder(width: 160, height: 22),
            const SizedBox(height: 8),
            // User Email
            const SkeletonPlaceholder(width: 220, height: 14),
            const SizedBox(height: 32),
            // Metric Cards Row
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SkeletonPlaceholder(width: 90, height: 70, borderRadius: 12),
                SkeletonPlaceholder(width: 90, height: 70, borderRadius: 12),
                SkeletonPlaceholder(width: 90, height: 70, borderRadius: 12),
              ],
            ),
            const SizedBox(height: 40),
            // Actions List Rows
            Column(
              children: List.generate(4, (index) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: Row(
                    children: [
                      SkeletonPlaceholder(width: 32, height: 32, borderRadius: 16),
                      SizedBox(width: 16),
                      Expanded(
                        child: SkeletonPlaceholder(width: 0, height: 16, borderRadius: 4),
                      ),
                      SizedBox(width: 32),
                      SkeletonPlaceholder(width: 16, height: 16, borderRadius: 8),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
