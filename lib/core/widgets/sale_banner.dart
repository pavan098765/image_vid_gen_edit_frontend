import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/ai_tools_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app_state.dart';
import '../services/sale_service.dart';
import '../theme/app_theme.dart';

/// Where the banner is shown — drives size and layout so promos fit the screen.
enum SaleBannerDisplay {
  /// Default card — secondary surfaces (fallback).
  standard,

  /// Hero promo — Explore, Create Studio, category pages; main focal point.
  highlight,

  /// Small pill — optional use where space is tight.
  compact,

  /// Full-width slim strip — minimal vertical use (e.g. dense tool chrome).
  strip,
}

class SaleBanner extends StatelessWidget {
  final SaleBannerDisplay display;

  const SaleBanner({
    super.key,
    this.display = SaleBannerDisplay.standard,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SaleState>(
      valueListenable: SaleService().state,
      builder: (context, sale, _) {
        if (sale.isActive) {
          return _ActiveBanner(sale: sale, display: display);
        }
        if (sale.nextWindowStart != null && sale.timeUntilNext > Duration.zero) {
          return _UpcomingBanner(sale: sale, display: display);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

String _formatCountdown(Duration remaining) {
  final hh = remaining.inHours;
  final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hh > 0 ? '${hh.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
}

/// Sale frame: crisp border + depth shadow + slow accent glow (retail-style “hero” emphasis).
///
/// Glow follows common promo patterns: layered `box-shadow`-like halos with a long period
/// so it reads premium, not arcadey.
class _SaleBannerFrame extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool live;
  final EdgeInsetsGeometry? margin;

  const _SaleBannerFrame({
    required this.child,
    required this.borderRadius,
    required this.live,
    this.margin,
  });

  @override
  State<_SaleBannerFrame> createState() => _SaleBannerFrameState();
}

class _SaleBannerFrameState extends State<_SaleBannerFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.live ? const Color(0xFFFF7043) : KalaColors.cyan;
    final secondary =
        widget.live ? const Color(0xFFFF2D6B) : KalaColors.purple;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // One smooth inhale/exhale per controller loop (avoids harsh triangle wave).
        final w = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
        final borderAlpha =
            (isDark ? 0.34 : 0.26) + 0.2 * w;
        final haloNear = 0.12 + 0.2 * w;
        final haloFar = 0.045 + 0.1 * w;
        final depthAlpha = (isDark ? 0.26 : 0.075) + 0.06 * w;

        return Container(
          margin: widget.margin,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: Color.lerp(
                    accent.withValues(alpha: borderAlpha),
                    secondary.withValues(alpha: borderAlpha * 0.92),
                    w,
                  ) ??
                  accent.withValues(alpha: borderAlpha),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: depthAlpha),
                blurRadius: 10 + 5 * w,
                offset: Offset(0, 3 + 1.5 * w),
              ),
              BoxShadow(
                color: accent.withValues(alpha: haloNear),
                blurRadius: 22 + 16 * w,
                spreadRadius: 0,
                offset: Offset(0, 5 + 3 * w),
              ),
              BoxShadow(
                color: secondary.withValues(alpha: haloFar),
                blurRadius: 42 + 22 * w,
                spreadRadius: -2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Short, high-signal copy — banner stays the source of truth for live % and timer.
void showSaleDetailsBottomSheet(BuildContext context, SaleState sale) {
  HapticFeedback.lightImpact();
  final cs = Theme.of(context).colorScheme;
  final isLive = sale.isActive;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLive
                                ? const [Color(0xFFFF6B35), Color(0xFFE91E63)]
                                : [KalaColors.cyan, KalaColors.purple],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(LucideIcons.zap, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isLive ? 'Sale Live! Save on AI tools' : 'How flash sales work',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // const SizedBox(height: 14),
                  // Wrap(
                  //   spacing: 6,
                  //   runSpacing: 6,
                  //   children: ['10%', '20%', '30%', '40%']
                  //       .map(
                  //         (p) => Container(
                  //           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  //           decoration: BoxDecoration(
                  //             color: cs.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.65),
                  //             borderRadius: BorderRadius.circular(8),
                  //             border: Border.all(
                  //               color: cs.primary.withValues(alpha: 0.2),
                  //             ),
                  //           ),
                  //           child: Text(
                  //             p,
                  //             style: TextStyle(
                  //               color: cs.onPrimaryContainer,
                  //               fontWeight: FontWeight.w700,
                  //               fontSize: 12,
                  //             ),
                  //           ),
                  //         ),
                  //       )
                  //       .toList(),
                  // ),
                  const SizedBox(height: 12),
                  Text(
                    '💸 SAVE BIG on AI Tools — Daily Mega Sales!\n\n'
                    '🔥 Discounts: 10% to 40% OFF on ALL AI tools!\n\n'
                    '⏰ Schedule: NEW sale drops every 3 hours (8 times daily!)\n\n'
                    '⏳ Duration: Only 15 MINUTES per sale — DO NOT blink!!\n\n'
                    '⚡ Act fast! Prices revert to normal as soon as the sale ends.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: KalaColors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _SaleInfoButtonStyle {
  onLiveWarmGradient,
  onUpcomingMutedSurface,
  onShowcaseHeroCard,
}

/// Reliable tap target for [showSaleDetailsBottomSheet] (dense / stacked banners).
class _SaleDetailsInfoButton extends StatelessWidget {
  final SaleState sale;
  final _SaleInfoButtonStyle style;
  final bool compact;

  const _SaleDetailsInfoButton({
    required this.sale,
    required this.style,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d = compact ? 30.0 : 40.0;
    final iconSz = compact ? 15.0 : 20.0;

    late Color bg;
    late Color borderC;
    late Color iconC;
    List<BoxShadow>? shadows;

    switch (style) {
      case _SaleInfoButtonStyle.onLiveWarmGradient:
        bg = Colors.black.withValues(alpha: 0.22);
        borderC = Colors.white.withValues(alpha: 0.38);
        iconC = Colors.white.withValues(alpha: 0.96);
        shadows = null;
        break;
      case _SaleInfoButtonStyle.onUpcomingMutedSurface:
        bg = cs.surfaceContainerHigh.withValues(alpha: isDark ? 0.5 : 0.92);
        borderC = cs.outlineVariant.withValues(alpha: 0.5);
        iconC = cs.tertiary;
        shadows = null;
        break;
      case _SaleInfoButtonStyle.onShowcaseHeroCard:
        final live = sale.isActive;
        bg = (isDark ? const Color(0xFF1A1520) : Colors.white)
            .withValues(alpha: isDark ? 0.78 : 0.88);
        borderC = Colors.white.withValues(alpha: isDark ? 0.2 : 0.52);
        iconC = live ? const Color(0xFFE65100) : const Color(0xFF00838F);
        shadows = null;
        break;
    }

    return Tooltip(
      message: 'Sale details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showSaleDetailsBottomSheet(context, sale),
          child: Ink(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: Border.all(color: borderC, width: 1.2),
              boxShadow: shadows,
            ),
            child: Center(
              child: Icon(
                LucideIcons.info,
                size: iconSz,
                color: iconC,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  final SaleState sale;
  final SaleBannerDisplay display;

  const _ActiveBanner({required this.sale, required this.display});

  @override
  Widget build(BuildContext context) {
    final remaining = sale.timeRemaining;
    final timeStr = _formatCountdown(remaining);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final gradient = LinearGradient(
      colors: isDark
          ? const [Color(0xFFC2410C), Color(0xFFBE185D)]
          : const [Color(0xFFFF5F2D), Color(0xFFFF2D6B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    switch (display) {
      case SaleBannerDisplay.compact:
        return _marginWrap(
          display,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showSaleDetailsBottomSheet(context, sale),
            child: _SaleBannerFrame(
              live: true,
              borderRadius: BorderRadius.circular(999),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: Colors.white.withValues(alpha: 0.95), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${sale.discountPercent}% OFF TOOLS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SaleDetailsInfoButton(
                    sale: sale,
                    style: _SaleInfoButtonStyle.onLiveWarmGradient,
                    compact: true,
                  ),
                ],
              ),
            ),
            ),
          ),
        );
      case SaleBannerDisplay.strip:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSaleDetailsBottomSheet(context, sale),
          child: _SaleBannerFrame(
            live: true,
            margin: const EdgeInsets.only(bottom: 6),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: gradient,
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: Colors.white.withValues(alpha: 0.95), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Flash sale · ${sale.discountPercent}% off on all AI tools',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SaleDetailsInfoButton(
                  sale: sale,
                  style: _SaleInfoButtonStyle.onLiveWarmGradient,
                  compact: true,
                ),
              ],
            ),
          ),
          ),
        );
      case SaleBannerDisplay.highlight:
        return _FlashySaleShowcaseBanner(
          margin: const EdgeInsets.only(bottom: 10, top: 0),
          sale: sale,
          timeStr: timeStr,
          isLiveSale: true,
          discountPercent: sale.discountPercent,
        );
      case SaleBannerDisplay.standard:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSaleDetailsBottomSheet(context, sale),
          child: _SaleBannerFrame(
            live: true,
            margin: const EdgeInsets.only(bottom: 10, top: 2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Icon(Icons.local_fire_department_rounded,
                    color: Colors.white.withValues(alpha: 0.98), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${sale.discountPercent}% off tool costs — live now',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Discount applies to all AI tools.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Ends in',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SaleDetailsInfoButton(
                sale: sale,
                style: _SaleInfoButtonStyle.onLiveWarmGradient,
              ),
            ],
          ),
        ),
          ),
        );
    }
  }
}

/// Outer spacing: parent scroll views already apply horizontal padding — avoid double inset.
Widget _marginWrap(SaleBannerDisplay display, Widget child) {
  if (display == SaleBannerDisplay.compact) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: child,
    );
  }
  return child;
}

class _UpcomingBanner extends StatelessWidget {
  final SaleState sale;
  final SaleBannerDisplay display;

  const _UpcomingBanner({required this.sale, required this.display});

  @override
  Widget build(BuildContext context) {
    final until = sale.timeUntilNext;
    final timeStr = _formatCountdown(until);
    final pct = sale.nextDiscountPercent ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final line =
        'Next sale in $timeStr${pct > 0 ? ' · up to $pct% off tool costs' : ''}';

    switch (display) {
      case SaleBannerDisplay.compact:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showSaleDetailsBottomSheet(context, sale),
            child: _SaleBannerFrame(
              live: false,
              borderRadius: BorderRadius.circular(999),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.tertiaryContainer.withValues(alpha: 0.35)
                    : cs.tertiaryContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, color: cs.tertiary, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SaleDetailsInfoButton(
                      sale: sale,
                      style: _SaleInfoButtonStyle.onUpcomingMutedSurface,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        );
      case SaleBannerDisplay.strip:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSaleDetailsBottomSheet(context, sale),
          child: _SaleBannerFrame(
            live: false,
            margin: const EdgeInsets.only(bottom: 6),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
                  : cs.tertiaryContainer.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: cs.tertiary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SaleDetailsInfoButton(
                  sale: sale,
                  style: _SaleInfoButtonStyle.onUpcomingMutedSurface,
                  compact: true,
                ),
              ],
            ),
          ),
          ),
        );
      case SaleBannerDisplay.highlight:
        return _FlashySaleShowcaseBanner(
          margin: const EdgeInsets.only(bottom: 10, top: 0),
          sale: sale,
          timeStr: timeStr,
          isLiveSale: false,
          discountPercent: pct,
        );
      case SaleBannerDisplay.standard:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSaleDetailsBottomSheet(context, sale),
          child: _SaleBannerFrame(
            live: false,
            margin: const EdgeInsets.only(bottom: 10, top: 2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
                  : cs.secondaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: cs.tertiary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _SaleDetailsInfoButton(
                  sale: sale,
                  style: _SaleInfoButtonStyle.onUpcomingMutedSurface,
                ),
              ],
            ),
          ),
          ),
        );
    }
  }
}

void _flashySalePromoTap(BuildContext context) {
  HapticFeedback.selectionClick();
  if (context.findAncestorWidgetOfExactType<AiToolsPage>() != null) {
    selectedIndexNotifier.value = AppTabs.explore;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const AiToolsPage()),
  );
}

String _flashySalePromoLabel(BuildContext context) {
  if (context.findAncestorWidgetOfExactType<AiToolsPage>() != null) {
    return 'Browse AI Explore';
  }
  return 'Open tools';
}

/// Hero promo — calm layout, no motion (timer & headline stay stable).
class _FlashySaleShowcaseBanner extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final SaleState sale;
  final String timeStr;
  final bool isLiveSale;
  final int discountPercent;

  const _FlashySaleShowcaseBanner({
    required this.margin,
    required this.sale,
    required this.timeStr,
    required this.isLiveSale,
    required this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final live = isLiveSale;
    final tt = Theme.of(context).textTheme;

    final baseGrad = live
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF1B0A24), Color(0xFF281018), Color(0xFF0F172A)]
                : const [Color(0xFFFFF7F7), Color(0xFFFFE8EE), Color(0xFFE8F2FF)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF0A1628), Color(0xFF141238), Color(0xFF06202A)]
                : const [Color(0xFFF0F7FF), Color(0xFFF5F0FF), Color(0xFFE8FBFF)],
          );

    final accentRail = live
        ? const [Color(0xFFFF6B35), Color(0xFFFF2D6B), Color(0xFFFFD54F)]
        : const [Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF80AB)];

    const radius = 20.0;
    const bannerHeight = 170.0;

    return _SaleBannerFrame(
      margin: margin,
      borderRadius: BorderRadius.circular(radius),
      live: live,
      child: SizedBox(
          height: bannerHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(gradient: baseGrad)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SaleHighlightBackdropPainter(live: live, isDark: isDark),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: accentRail,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(0.85, -0.92),
                        end: Alignment.bottomLeft,
                        colors: [
                          (live ? const Color(0xFFFF6B35) : const Color(0xFF7C4DFF))
                              .withValues(alpha: isDark ? 0.1 : 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => showSaleDetailsBottomSheet(context, sale),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        _SaleEyebrowPill(live: live, isDark: isDark),
                                        const SizedBox(width: 8),
                                        _SaleDetailsInfoButton(
                                          sale: sale,
                                          style:
                                              _SaleInfoButtonStyle.onShowcaseHeroCard,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    _SalePercentHero(
                                      discountPercent: discountPercent,
                                      live: live,
                                      isDark: isDark,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              _SalePromoCtaButton(
                                label: _flashySalePromoLabel(context),
                                live: live,
                                onPressed: () => _flashySalePromoTap(context),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                discountPercent > 0
                                    ? 'Upto $discountPercent% off on ALL AI tools'
                                    : (live
                                        ? 'Discounted pricing on tools'
                                        : 'Savings on tools when live'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.labelSmall?.copyWith(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.62)
                                          : Colors.black.withValues(alpha: 0.48),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                      height: 1.15,
                                    ) ??
                                    TextStyle(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.62)
                                          : Colors.black.withValues(alpha: 0.48),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10.5,
                                      height: 1.15,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showSaleDetailsBottomSheet(context, sale),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                          child: Center(
                            child: _SaleFrostedTimerPanel(
                              timeStr: timeStr,
                              live: live,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _SaleEyebrowPill extends StatelessWidget {
  final bool live;
  final bool isDark;

  const _SaleEyebrowPill({
    required this.live,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (live ? const Color(0xFFFFB74D) : const Color(0xFF64FFDA))
              .withValues(alpha: 0.42),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (live ? const Color(0xFFFF6B35) : const Color(0xFF00BCD4))
                .withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            const _SaleLivePulseDot(),
            const SizedBox(width: 8),
          ],
          Text(
            live ? 'SALE LIVE!' : 'NEXT SALE',
            style: TextStyle(
              color: live ? const Color(0xFFFFE082) : const Color(0xFFFFE082),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleLivePulseDot extends StatelessWidget {
  const _SaleLivePulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFF3D5C).withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3D5C).withValues(alpha: 0.45),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

class _SalePercentHero extends StatelessWidget {
  final int discountPercent;
  final bool live;
  final bool isDark;

  const _SalePercentHero({
    required this.discountPercent,
    required this.live,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (discountPercent > 0) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: live
                ? const [Color(0xFFFFFDE7), Color(0xFFFFAB40), Color(0xFFFF3D00)]
                : const [Color(0xFFE1F5FE), Color(0xFF7C4DFF), Color(0xFF00BCD4)],
          ).createShader(bounds),
          child: Text(
            '$discountPercent%',
            style: const TextStyle(
              fontSize: 44,
              height: 0.92,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Text(
      live ? 'MEGA DEALS' : 'BIG SAVINGS',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
      ),
    );
  }
}

class _SalePromoCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool live;

  const _SalePromoCtaButton({
    required this.label,
    required this.onPressed,
    required this.live,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: live
                  ? const [Color(0xFFFF6B35), Color(0xFFE91E63)]
                  : const [Color(0xFF00ACC1), Color(0xFF7C4DFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: (live ? const Color(0xFFFF5722) : const Color(0xFF0097A7))
                    .withValues(alpha: 0.42),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleFrostedTimerPanel extends StatelessWidget {
  final String timeStr;
  final bool live;
  final bool isDark;

  const _SaleFrostedTimerPanel({
    required this.timeStr,
    required this.live,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final parts = timeStr.split(':');
    final unitLabels = parts.length >= 3
        ? const ['H', 'M', 'S']
        : const ['M', 'S'];

    final accentA = live ? const Color(0xFFFF6B35) : const Color(0xFF00E5FF);
    final accentB = live ? const Color(0xFFFF2D6B) : const Color(0xFF7C4DFF);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentA, accentB],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accentA.withValues(alpha: 0.38),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.25),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.75),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (isDark ? const Color(0xFF1A1520) : Colors.white)
                      .withValues(alpha: isDark ? 0.72 : 0.78),
                  (isDark ? const Color(0xFF120E18) : const Color(0xFFF5F7FA))
                      .withValues(alpha: isDark ? 0.62 : 0.88),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.55),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 11,
                      color: live
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFF4DD0E1),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      live ? 'ENDS IN' : 'STARTS IN',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.35,
                        height: 1,
                        color: live
                            ? const Color(0xFFFFE0B2)
                            : const Color(0xFFB2EBF2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < parts.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, left: 1, right: 1),
                          child: Text(
                            ':',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SaleTimeSegment(
                            value: parts[i],
                            live: live,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            unitLabels[i],
                            style: TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                              height: 1,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : Colors.black.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleTimeSegment extends StatelessWidget {
  final String value;
  final bool live;
  final bool isDark;

  const _SaleTimeSegment({
    required this.value,
    required this.live,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final rim = live ? const Color(0xFFFFB74D) : const Color(0xFF64FFDA);
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rim.withValues(alpha: isDark ? 0.22 : 0.14),
            Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
          ],
        ),
        border: Border.all(
          color: rim.withValues(alpha: isDark ? 0.55 : 0.42),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: rim.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
      ),
    );
  }
}

/// Soft orbs, light grid, and faint diagonals — fills negative space without competing with copy.
class _SaleHighlightBackdropPainter extends CustomPainter {
  final bool live;
  final bool isDark;

  _SaleHighlightBackdropPainter({required this.live, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final warm = live ? const Color(0xFFFF6B35) : const Color(0xFF00B8D4);
    final cool = live ? const Color(0xFFFF4081) : const Color(0xFF5C6BC0);

    final orb = Paint()..style = PaintingStyle.fill;
    orb.color = warm.withValues(alpha: isDark ? 0.085 : 0.055);
    canvas.drawCircle(
      Offset(size.width * 0.92, -size.height * 0.08),
      size.width * 0.38,
      orb,
    );
    orb.color = cool.withValues(alpha: isDark ? 0.065 : 0.045);
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 1.02),
      size.width * 0.42,
      orb,
    );
    orb.color = warm.withValues(alpha: isDark ? 0.035 : 0.028);
    canvas.drawCircle(
      Offset(size.width * 0.55, size.height * 0.35),
      size.width * 0.22,
      orb,
    );

    final dot = Paint()..style = PaintingStyle.fill;
    dot.color = Colors.white.withValues(alpha: isDark ? 0.032 : 0.048);
    for (var x = 10.0; x < size.width; x += 34) {
      for (var y = 12.0; y < size.height; y += 34) {
        if (((x ~/ 34) + (y ~/ 34)) % 3 == 0) continue;
        canvas.drawCircle(Offset(x, y), 1.05, dot);
      }
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: isDark ? 0.022 : 0.035);
    for (var i = -1; i < 7; i++) {
      final x0 = i * 44.0;
      canvas.drawLine(Offset(x0, 0), Offset(x0 + size.height * 0.85, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant _SaleHighlightBackdropPainter oldDelegate) =>
      oldDelegate.live != live || oldDelegate.isDark != isDark;
}

class SalePriceBadge extends StatelessWidget {
  final int originalCost;
  final TextStyle? originalStyle;
  final TextStyle? discountedStyle;
  final TextStyle? badgeTextStyle;
  final bool showBadge;

  const SalePriceBadge({
    super.key,
    required this.originalCost,
    this.originalStyle,
    this.discountedStyle,
    this.badgeTextStyle,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<SaleState>(
      valueListenable: SaleService().state,
      builder: (context, sale, _) {
        if (!sale.isActive || sale.discountPercent <= 0) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.diamond_outlined, size: 14, color: cs.primary),
              const SizedBox(width: 3),
              Text(
                '$originalCost',
                style: originalStyle ?? const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          );
        }
        final discounted = sale.applyDiscount(originalCost);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.diamond_outlined, size: 14, color: cs.primary),
            const SizedBox(width: 3),
            Text(
              '$originalCost',
              style: (originalStyle ?? const TextStyle()).copyWith(
                decoration: TextDecoration.lineThrough,
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$discounted',
              style: discountedStyle ??
                  TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.tertiary,
                  ),
            ),
            if (showBadge) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '-${sale.discountPercent}%',
                  style: badgeTextStyle ??
                      TextStyle(
                        color: cs.tertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
