// lib/core/widgets/themed_native_ad.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:shimmer/shimmer.dart';

/// A themed native ad widget that blends with the app's design
/// Shows a native ad that matches the app's color scheme and styling
class ThemedNativeAd extends StatefulWidget {
  /// Height of the ad container (defaults to 280 for medium template)
  final double height;
  
  /// Whether to use small template (default is medium)
  final bool useSmallTemplate;
  
  /// Optional callback when ad loads
  final VoidCallback? onAdLoaded;
  
  /// Optional callback when ad fails to load
  final VoidCallback? onAdFailedToLoad;

  const ThemedNativeAd({
    super.key,
    this.height = 280,
    this.useSmallTemplate = false,
    this.onAdLoaded,
    this.onAdFailedToLoad,
  });

  @override
  State<ThemedNativeAd> createState() => _ThemedNativeAdState();
}

class _ThemedNativeAdState extends State<ThemedNativeAd> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _isAdFailed = false;
  bool _isAdLoadStarted = false;

  @override
  void initState() {
    super.initState();
    // Don't load ad here - Theme.of(context) isn't available yet
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load ad here where Theme.of(context) is safe to use
    // Only load once
    if (!_isAdLoadStarted) {
      _isAdLoadStarted = true;
      _loadNativeAd();
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  void _loadNativeAd() {
    // Native ads only work on mobile platforms
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      if (mounted) setState(() => _isAdFailed = true);
      return;
    }

    final templateStyle = _buildTemplateStyle();
    
    _nativeAd = NativeAd(
      adUnitId: AdUnitIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          debugPrint('✅ Native ad loaded');
          if (mounted) {
            setState(() => _isAdLoaded = true);
            widget.onAdLoaded?.call();
          }
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          debugPrint('❌ Native ad failed to load: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() => _isAdFailed = true);
            widget.onAdFailedToLoad?.call();
          }
        },
        onAdOpened: (Ad ad) => debugPrint('📱 Native ad opened'),
        onAdClosed: (Ad ad) => debugPrint('📱 Native ad closed'),
      ),
      nativeTemplateStyle: templateStyle,
    );

    _nativeAd!.load();
  }

  NativeTemplateStyle _buildTemplateStyle() {
    // Get theme colors - safe to call here from didChangeDependencies
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    
    // Define colors based on theme
    final backgroundColor = isDark 
        ? cs.surfaceContainerHigh 
        : cs.surface;
    final mainTextColor = cs.onSurface;
    final secondaryTextColor = cs.onSurfaceVariant;
    final ctaBackgroundColor = cs.primary;
    final ctaTextColor = cs.onPrimary;
    
    return NativeTemplateStyle(
      templateType: widget.useSmallTemplate 
          ? TemplateType.small 
          : TemplateType.medium,
      mainBackgroundColor: backgroundColor,
      cornerRadius: 16,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: ctaTextColor,
        backgroundColor: ctaBackgroundColor,
        style: NativeTemplateFontStyle.bold,
        size: 14,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: mainTextColor,
        backgroundColor: backgroundColor,
        style: NativeTemplateFontStyle.bold,
        size: 16,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: secondaryTextColor,
        backgroundColor: backgroundColor,
        style: NativeTemplateFontStyle.normal,
        size: 14,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: secondaryTextColor.withOpacity(0.7),
        backgroundColor: backgroundColor,
        style: NativeTemplateFontStyle.normal,
        size: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Don't show anything if ad failed
    if (_isAdFailed) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: _isAdLoaded ? widget.height : (widget.useSmallTemplate ? 100 : 160),
      decoration: BoxDecoration(
        color: isDark 
            ? cs.surfaceContainerHigh.withOpacity(0.5)
            : cs.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _isAdLoaded
          ? AdWidget(ad: _nativeAd!)
          : _buildLoadingPlaceholder(cs, isDark),
    );
  }

  Widget _buildLoadingPlaceholder(ColorScheme cs, bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark 
          ? cs.surfaceContainerHighest 
          : cs.surfaceContainerLow,
      highlightColor: isDark 
          ? cs.surfaceContainerHigh 
          : cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ad badge
            Container(
              width: 28,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            // Icon/Image placeholder
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title placeholder
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Subtitle placeholder
                      Container(
                        height: 12,
                        width: 150,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!widget.useSmallTemplate) ...[
              const SizedBox(height: 16),
              // Body placeholder
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 12,
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact native ad for tighter spaces
class CompactNativeAd extends StatelessWidget {
  const CompactNativeAd({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThemedNativeAd(
      height: 120,
      useSmallTemplate: true,
    );
  }
}

