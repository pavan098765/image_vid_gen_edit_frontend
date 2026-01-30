import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/purchase_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/credits/offerwall_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final AdService _adService = AdService();
  final PurchaseService _purchaseService = PurchaseService.instance;
  bool _isRefreshing = false;
  
  // Offerwall visibility - set to true when AdGem is approved
  static const bool _showOfferwall = false;
  
  // Purchase state
  String? _selectedGemPackId;
  bool _isPurchasing = false;
  
  // Daily spin state
  bool _canSpin = true;
  bool _isCheckingSpinEligibility = true;
  DateTime? _nextSpinDateTime;
  Timer? _spinCountdownTimer;
  Duration _spinCountdownDuration = Duration.zero;
  
  // Rewarded ad state
  RewardedAdStatus? _adStatus;
  bool _isCheckingAdEligibility = true;
  bool _isShowingAd = false;
  Timer? _adResetCountdownTimer;
  Duration _adResetCountdownDuration = Duration.zero;
  
  // Ad cooldown state (between ads)
  Timer? _adCooldownTimer;
  Duration _adCooldownDuration = Duration.zero;
  
  /// Check if features requiring verification are blocked
  /// (User signed up via email but hasn't verified yet)
  bool get _needsEmailVerification => _authService.needsEmailVerification;

  @override
  void initState() {
    super.initState();
    // Listen to auth state and user data changes
    _authService.authStateChanges.listen((_) {
      if (mounted) setState(() {});
      // Re-check eligibility when auth state changes
      if (_authService.isSignedIn) {
        _checkSpinEligibility();
        _checkAdEligibility();
      }
    });
    currentUserNotifier.addListener(_onUserChanged);
    
    // Listen to ad status changes
    _adService.statusNotifier.addListener(_onAdStatusChanged);
    _adService.isAdReadyNotifier.addListener(_onAdReadyChanged);
    _adService.cooldownNotifier.addListener(_onCooldownChanged);
    _adService.availabilityNotifier.addListener(_onAdAvailabilityChanged);
    
    // Listen to global email verification status changes (from Settings or other pages)
    emailVerifiedNotifier.addListener(_onEmailVerificationChanged);
    
    // Initialize purchase service and listen to updates
    _initPurchaseService();
    _purchaseService.statusNotifier.addListener(_onPurchaseStatusChanged);
    _purchaseService.productsNotifier.addListener(_onProductsChanged);
    
    // Set default selected pack (Power Pack - popular)
    _selectedGemPackId = kCredits500ProductId;
    
    // Refresh credits on page load if signed in
    if (_authService.isSignedIn) {
      _refreshCredits();
      _checkSpinEligibility();
      _checkAdEligibility();
    }
  }
  
  void _initPurchaseService() async {
    await _purchaseService.initialize();
  }
  
  void _onPurchaseStatusChanged() {
    if (mounted) {
      setState(() {
        _isPurchasing = _purchaseService.statusNotifier.value == IAPState.purchasing ||
                        _purchaseService.statusNotifier.value == IAPState.verifying;
      });
      
      // Handle purchase completion
      final status = _purchaseService.statusNotifier.value;
      final productId = _purchaseService.currentPurchaseProductId;
      if (status == IAPState.completed) {
        _showPurchaseSuccessSnackBar(productId: productId);
      } else if (status == IAPState.failed) {
        _showPurchaseErrorSnackBar(_purchaseService.errorNotifier.value, productId: productId);
      }
    }
  }
  
  void _onProductsChanged() {
    if (mounted) setState(() {});
  }
  
  void _showPurchaseSuccessSnackBar({String? productId}) {
    // Determine message based on product type
    final isAdFree = productId == kRemoveAdsProductId;
    final message = isAdFree 
        ? 'Ad-free activated! Enjoy the app without ads.'
        : 'Purchase successful! Gems added to your account.';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isAdFree ? LucideIcons.bellOff : LucideIcons.checkCircle, 
              color: Colors.white, 
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _showPurchaseErrorSnackBar(String? error, {String? productId}) {
    // Handle "already owned" for ad-free (not really an error)
    final isAdFree = productId == kRemoveAdsProductId;
    if (isAdFree && error != null && 
        (error.contains('itemUnavailable') || error.contains('already own'))) {
      // User already purchased - check with server and update UI
      _checkAndRestoreAdFree();
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.alertCircle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(error ?? 'Purchase failed. Please try again.')),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  /// Check with server if user has ad-free and restore it
  Future<void> _checkAndRestoreAdFree() async {
    try {
      final isAdFree = await _userService.checkAdFreeStatus();
      if (isAdFree) {
        _showPurchaseSuccessSnackBar(productId: kRemoveAdsProductId);
      } else {
        // Not ad-free on server - maybe refunded or different account
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(LucideIcons.alertCircle, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text('Please sign in with the account used for purchase.')),
              ],
            ),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking ad-free status: $e');
    }
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }
  
  void _onAdStatusChanged() {
    if (mounted) {
      setState(() {
        _adStatus = _adService.statusNotifier.value;
      });
    }
  }
  
  void _onAdReadyChanged() {
    if (mounted) setState(() {});
  }
  
  void _onCooldownChanged() {
    if (mounted) {
      final cooldownEndsAt = _adService.cooldownNotifier.value;
      if (cooldownEndsAt != null) {
        _startAdCooldownTimer(cooldownEndsAt);
      } else {
        _stopAdCooldownTimer();
      }
    }
  }
  
  void _onAdAvailabilityChanged() {
    if (mounted) setState(() {});
  }
  
  void _startAdCooldownTimer(DateTime cooldownEndsAt) {
    _stopAdCooldownTimer();
    
    _updateAdCooldownDuration(cooldownEndsAt);
    
    // Update every second
    _adCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _stopAdCooldownTimer();
        return;
      }
      
      _updateAdCooldownDuration(cooldownEndsAt);
      
      // Stop timer when cooldown expires
      if (_adCooldownDuration.inSeconds <= 0) {
        _stopAdCooldownTimer();
      }
    });
  }
  
  void _updateAdCooldownDuration(DateTime cooldownEndsAt) {
    final now = DateTime.now();
    final remaining = cooldownEndsAt.difference(now);
    setState(() {
      _adCooldownDuration = remaining.isNegative ? Duration.zero : remaining;
    });
  }
  
  void _stopAdCooldownTimer() {
    _adCooldownTimer?.cancel();
    _adCooldownTimer = null;
    if (mounted) {
      setState(() {
        _adCooldownDuration = Duration.zero;
      });
    }
  }
  
  void _onEmailVerificationChanged() {
    if (mounted) {
      setState(() {});
      // Re-check eligibility when verification status changes
      if (_authService.isSignedIn && _authService.isEmailVerified) {
        _checkSpinEligibility();
        _checkAdEligibility();
      }
    }
  }

  @override
  void dispose() {
    currentUserNotifier.removeListener(_onUserChanged);
    _adService.statusNotifier.removeListener(_onAdStatusChanged);
    _adService.isAdReadyNotifier.removeListener(_onAdReadyChanged);
    _adService.cooldownNotifier.removeListener(_onCooldownChanged);
    _adService.availabilityNotifier.removeListener(_onAdAvailabilityChanged);
    emailVerifiedNotifier.removeListener(_onEmailVerificationChanged);
    _purchaseService.statusNotifier.removeListener(_onPurchaseStatusChanged);
    _purchaseService.productsNotifier.removeListener(_onProductsChanged);
    _adService.stopPrefetching(); // Stop background prefetch when leaving page
    _spinCountdownTimer?.cancel();
    _adResetCountdownTimer?.cancel();
    _adCooldownTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _checkSpinEligibility() async {
    if (!_authService.isSignedIn) {
      setState(() {
        _isCheckingSpinEligibility = false;
        _canSpin = false;
      });
      return;
    }
    
    setState(() => _isCheckingSpinEligibility = true);
    
    try {
      final result = await _userService.checkDailySpinEligibility();
      
      if (mounted) {
        final nextSpinStr = result['next_spin_time'] as String?;
        DateTime? nextSpinDt;
        
        if (nextSpinStr != null && nextSpinStr != 'Tomorrow') {
          try {
            nextSpinDt = DateTime.parse(nextSpinStr);
          } catch (_) {
            nextSpinDt = DateTime.now().toUtc().add(const Duration(days: 1));
            nextSpinDt = DateTime.utc(nextSpinDt.year, nextSpinDt.month, nextSpinDt.day);
          }
        }
        
        setState(() {
          _canSpin = result['can_spin'] ?? true;
          _nextSpinDateTime = nextSpinDt;
          _isCheckingSpinEligibility = false;
        });
        
        if (!_canSpin && _nextSpinDateTime != null) {
          _startSpinCountdownTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _canSpin = true; // Default to allow on error
          _isCheckingSpinEligibility = false;
        });
      }
    }
  }
  
  void _startSpinCountdownTimer() {
    _spinCountdownTimer?.cancel();
    if (_nextSpinDateTime == null) return;
    
    _spinCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final remaining = _nextSpinDateTime!.difference(now);
      
      if (remaining.isNegative) {
        timer.cancel();
        setState(() {
          _canSpin = true;
          _spinCountdownDuration = Duration.zero;
        });
      } else {
        setState(() {
          _spinCountdownDuration = remaining;
        });
      }
    });
    
    // Initial update
    final now = DateTime.now();
    final remaining = _nextSpinDateTime!.difference(now);
    setState(() {
      _spinCountdownDuration = remaining.isNegative ? Duration.zero : remaining;
    });
  }
  
  String _formatSpinCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  // ============================================================
  // REWARDED ADS
  // ============================================================
  
  Future<void> _checkAdEligibility() async {
    if (!_authService.isSignedIn) {
      setState(() {
        _isCheckingAdEligibility = false;
        _adStatus = null;
      });
      return;
    }
    
    setState(() => _isCheckingAdEligibility = true);
    
    try {
      final status = await _adService.checkEligibility();
      
      if (mounted) {
        setState(() {
          _adStatus = status;
          _isCheckingAdEligibility = false;
        });
        
        // Start countdown if limit reached
        if (status.hasReachedLimit && status.nextResetTime != null) {
          _startAdResetCountdownTimer(status.nextResetTime!);
        }
        
        // Start cooldown timer if in cooldown
        if (status.cooldownEndsAt != null && status.isInCooldown) {
          _startAdCooldownTimer(status.cooldownEndsAt!);
        }
        
        // Start prefetching if eligible
        if (status.canWatchNow) {
          _adService.startPrefetching();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingAdEligibility = false;
          // Default to allowing ads on error
          _adStatus = RewardedAdStatus.defaultStatus();
        });
        _adService.loadRewardedAd();
      }
    }
  }
  
  void _startAdResetCountdownTimer(DateTime resetTime) {
    _adResetCountdownTimer?.cancel();
    
    _adResetCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final remaining = resetTime.difference(now);
      
      if (remaining.isNegative) {
        timer.cancel();
        // Reset reached - refresh eligibility
        _checkAdEligibility();
      } else {
        setState(() {
          _adResetCountdownDuration = remaining;
        });
      }
    });
    
    // Initial update
    final now = DateTime.now();
    final remaining = resetTime.difference(now);
    setState(() {
      _adResetCountdownDuration = remaining.isNegative ? Duration.zero : remaining;
    });
  }
  
  String _formatAdResetCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Future<void> _refreshCredits() async {
    setState(() => _isRefreshing = true);
    try {
      await _userService.refreshCredits();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _watchAdForCredits() async {
    if (!_authService.isSignedIn) {
      final signedIn = await requireSignIn(context, feature: 'earning gems');
      if (!signedIn) return;
    }
    
    // Check eligibility first
    if (_adStatus?.hasReachedLimit == true) {
      _showDailyLimitReachedSheet();
      return;
    }
    
    // ⚠️ Check cooldown BEFORE loading/showing ad
    if (_adService.isInCooldown) {
      _showCooldownSnackbar();
      return;
    }
    
    // Check if ad is ready
    if (!_adService.isAdReadyNotifier.value) {
      setState(() => _isShowingAd = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading ad... Please wait'),
          duration: Duration(seconds: 2),
        ),
      );
      await _adService.loadRewardedAd();
      
      // Wait for ad to load (with timeout)
      for (int i = 0; i < 10; i++) {
        if (_adService.isAdReadyNotifier.value) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (!_adService.isAdReadyNotifier.value) {
        if (mounted) {
          setState(() => _isShowingAd = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load ad. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    
    // Double-check cooldown right before showing (in case it expired while loading)
    if (_adService.isInCooldown) {
      _showCooldownSnackbar();
      setState(() => _isShowingAd = false);
      return;
    }
    
    setState(() => _isShowingAd = true);
    
    try {
      final creditsEarned = await _adService.showRewardedAd();
      
      if (mounted) {
        // Refresh ad eligibility status FIRST to get updated adsWatchedToday
        await _checkAdEligibility();
        
        if (creditsEarned != null && creditsEarned >= 0) {
          // Show success/progress message (0 = progress, 1+ = earned)
          _showAdRewardDialog(creditsEarned);
        } else if (creditsEarned == -1) {
          // Cooldown triggered (shouldn't happen with pre-check, but just in case)
          _showCooldownSnackbar();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ad error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isShowingAd = false);
      }
    }
  }
  
  void _showCooldownSnackbar() {
    final remaining = _adService.remainingCooldown;
    final seconds = remaining.inSeconds;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.clock, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Next ad available in ${seconds}s'),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  
  
  void _showAdRewardDialog(int credits) {
    final cs = Theme.of(context).colorScheme;
    
    // credits = 0 means we haven't reached 4 ads yet - no credit earned yet
    // credits > 0 means this was the 4th ad (4th, 8th, 12th...) - credit was earned
    final didEarnCredit = credits > 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: didEarnCredit 
                    ? const LinearGradient(colors: KalaColors.brandGradient)
                    : LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade600]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                didEarnCredit ? LucideIcons.gift : LucideIcons.checkCircle,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (didEarnCredit) ...[
              // Earned credit message
              Text(
                'You earned',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.gem, size: 28, color: KalaColors.gold),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: KalaColors.brandGradient,
                    ).createShader(bounds),
                    child: Text(
                      '+$credits',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                credits == 1 ? 'Gem' : 'Gems',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ] else ...[
              // Progress message - need more ads to earn a gem
              // Calculate current progress (after this ad was just watched)
              Builder(
                builder: (context) {
                  final adsWatched = _adStatus?.adsWatchedToday ?? 0;
                  final progress = adsWatched % 4;
                  // If progress is 0 after watching, we just earned (shouldn't reach here)
                  // Otherwise progress shows how many of 4 ads we've watched
                  final displayProgress = progress == 0 ? 4 : progress;
                  final remaining = 4 - displayProgress;
                  
                  return Column(
                    children: [
              Text(
                'Ad watched!',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
                      // Visual progress: show 4 dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                          for (int i = 0; i < 4; i++) ...[
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                                color: i < displayProgress ? cs.primary : null,
                                border: i < displayProgress 
                                    ? null 
                                    : Border.all(color: cs.outline, width: 2),
                    ),
                              child: i < displayProgress 
                                  ? Icon(LucideIcons.check, size: 14, color: cs.onPrimary)
                                  : null,
                            ),
                            if (i < 3) const SizedBox(width: 6),
                          ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                        remaining == 1 
                            ? '1 more ad for 1 gem'
                            : '$remaining more ads for 1 gem',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
        actions: [
          Center(
            child: GradientButton(
              label: didEarnCredit ? 'Awesome!' : 'Got it',
              icon: didEarnCredit ? LucideIcons.sparkles : LucideIcons.check,
              onPressed: () => Navigator.pop(context),
              variant: ButtonVariant.primary,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showDailyLimitReachedSheet() {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.clock,
                  size: 40,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Daily Limit Reached',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve watched ${_adStatus?.dailyLimit ?? 30} ads today.\nCome back tomorrow for more free gems!',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (_adStatus?.nextResetTime != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.timer, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Resets in ${_formatAdResetCountdown(_adResetCountdownDuration)}',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              GradientButton(
                label: 'Got it',
                onPressed: () => Navigator.pop(context),
                variant: ButtonVariant.secondary,
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showVerificationRequiredSheet() {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.mailWarning,
                  size: 40,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Email Verification Required',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please verify your email address to unlock free gems features like Lucky Spin and Watch Ads.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Email display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.mail, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _authService.userEmail ?? 'your email',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await _authService.resendEmailVerification();
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(LucideIcons.mailCheck, color: Colors.white, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Verification email sent!')),
                                  ],
                                ),
                                backgroundColor: Colors.green.shade600,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to send: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.send, size: 16),
                      label: const Text('Resend'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: cs.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        // Check verification status
                        await _authService.reloadUser();
                        await _authService.forceRefreshToken();
                        
                        if (mounted) {
                          Navigator.pop(context);
                          if (_authService.isEmailVerified) {
                            // Sync user to get signup bonus
                            await _userService.syncUser(isNewSignUp: true);
                            await _refreshCredits();
                            _checkSpinEligibility();
                            _checkAdEligibility();
                            
                            // Notify all other pages about verification status change
                            notifyEmailVerificationChanged(true);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(LucideIcons.checkCircle, color: Colors.white, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Email verified! Features unlocked.')),
                                  ],
                                ),
                                backgroundColor: Colors.green.shade600,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            setState(() {});
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(LucideIcons.alertCircle, color: Colors.white, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Email not verified yet. Check your inbox.')),
                                  ],
                                ),
                                backgroundColor: Colors.orange.shade700,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.checkCircle, size: 16),
                      label: const Text('I\'ve Verified'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.green.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Note about purchases
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You can still purchase gems without verification.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
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

  void _showAuthSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignInRequiredScreen(
          feature: 'Gems',
          onSignInSuccess: () {
            _refreshCredits();
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _openDailySpinner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailySpinnerPage(
          onCreditsWon: (credits) {
            _refreshCredits();
          },
        ),
      ),
    );
    // Re-check spin eligibility when returning from spinner
    if (mounted && _authService.isSignedIn) {
      _checkSpinEligibility();
    }
  }

  Future<bool> _handleSystemBack() async {
    final ok = await _confirmExitApp();
    if (ok) {
      // User confirmed exit - actually exit the app
      SystemNavigator.pop();
    }
    return false; // Always prevent default back navigation
  }
  
  Future<bool> _confirmExitApp() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitAppDialog(),
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSignedIn = _authService.isSignedIn;
    
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
      appBar: AppBar(
        title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (isSignedIn)
            IconButton(
              icon: _isRefreshing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : const Icon(LucideIcons.refreshCw),
              onPressed: _isRefreshing ? null : _refreshCredits,
              tooltip: 'Refresh gems',
            ),
        ],
      ),
      body: isSignedIn 
          ? _buildCreditsContent(cs)
          : _buildSignInPrompt(cs),
      ),
    );
  }

  Widget _buildSignInPrompt(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppStyles.spacing24),
        child: Column(
          children: [
          const SizedBox(height: 40),
          // Illustration
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KalaColors.purple.withOpacity(0.15),
                  KalaColors.cyan.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: KalaColors.brandGradient,
              ).createShader(bounds),
              child: const Icon(
                LucideIcons.gem,
                size: 64,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            'Sign in to manage gems',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an account to earn and use gems for AI tools',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          // Bonus callout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: KalaColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KalaColors.gold.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.gift, size: 20, color: KalaColors.gold),
                SizedBox(width: 8),
                Text(
                  '50 free gems on signup!',
                  style: TextStyle(
                    color: KalaColors.gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Sign in button
          GradientButton(
            icon: LucideIcons.logIn,
            label: 'Sign In / Sign Up',
            onPressed: _showAuthSheet,
            variant: ButtonVariant.primary,
            size: ButtonSize.large,
            expanded: true,
          ),
          const SizedBox(height: 40),
          
          // Benefits
          _buildBenefit(
            cs,
            icon: LucideIcons.zap,
            title: 'Use AI Tools',
            description: 'Generate images and videos with AI',
          ),
          const SizedBox(height: 16),
          _buildBenefit(
            cs,
            icon: LucideIcons.playCircle,
            title: 'Watch Ads',
            description: 'Earn free gems by watching ads',
          ),
          const SizedBox(height: 16),
          _buildBenefit(
            cs,
            icon: LucideIcons.cloud,
            title: 'Sync Everywhere',
            description: 'Your gems sync across all devices',
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(ColorScheme cs, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: cs.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreditsContent(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Compact gem balance header
          _buildCompactGemBalance(cs),
          const SizedBox(height: 24),
          
          // Free Gems Section - Combined Daily Spin + Ads
          _buildSectionHeader(cs, 'Free Gems', LucideIcons.gift),
          const SizedBox(height: 10),
          _buildFreeGemsRow(cs),
          const SizedBox(height: 24),
          
          // Buy Gems Section
          _buildSectionHeader(cs, 'Buy Gems', LucideIcons.store),
          const SizedBox(height: 10),
          _buildGemPacksSection(cs),
          
          const SizedBox(height: 24),
          
          // Premium Section - Combined Remove Ads + VIP
          _buildSectionHeader(cs, 'Premium', LucideIcons.crown),
          const SizedBox(height: 10),
          _buildPremiumSection(cs),
          
          const SizedBox(height: 20),
          
          // Restore Purchases link
          Center(
            child: TextButton.icon(
              onPressed: _restorePurchases,
              icon: Icon(LucideIcons.refreshCw, size: 16, color: cs.primary),
              label: Text(
                'Restore Purchases',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: AppStyles.spacing8),
          
          // Legal links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _showLegalDocument(
                  title: 'Terms of Service',
                  rawUrl: 'https://pastebin.com/raw/bprTSU66',
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Terms of Service',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '•',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
              TextButton(
                onPressed: () => _showLegalDocument(
                  title: 'Privacy Policy',
                  rawUrl: 'https://pastebin.com/raw/66qXZNSW',
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: AppStyles.spacing12),
          
          // Info text
          Text(
            'Gems never expire. Use them anytime for AI generation.',
            style: TextStyle(
              color: cs.onSurfaceVariant.withOpacity(0.6),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ColorScheme cs, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: cs.primary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
  
  /// Compact gem balance card - streamlined hero section
  Widget _buildCompactGemBalance(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KalaColors.purple.withOpacity(0.12),
            KalaColors.cyan.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KalaColors.purple.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Gem icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: KalaColors.brandGradient),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.gem, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 16),
          // Balance info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Gems',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: userCreditsNotifier,
                  builder: (context, credits, _) {
                    return ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: KalaColors.brandGradient,
                      ).createShader(bounds),
                      child: Text(
                        '$credits',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // VIP Badge if active, otherwise show gems never expire
          ValueListenableBuilder<VipStatus>(
            valueListenable: vipStatusNotifier,
            builder: (context, vipStatus, _) {
              if (vipStatus.isVip) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade600, Colors.orange.shade700],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.crown, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'VIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.infinity, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Never expires',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  /// Free gems section - Daily Spin, Watch Ads, and Offerwall
  Widget _buildFreeGemsRow(ColorScheme cs) {
    return Column(
      children: [
        // Row 1: Daily Spin and Watch Ads
        Row(
          children: [
            Expanded(child: _buildCompactDailySpinCard(cs)),
            const SizedBox(width: 10),
            Expanded(child: _buildWatchAdsCard(cs)),
          ],
        ),
        // Offerwall - AdGem integration (hidden until approved)
        if (_showOfferwall) ...[
          const SizedBox(height: 10),
          _buildOfferwallCard(cs),
        ],
      ],
    );
  }
  
  /// Open the AdGem Offerwall
  void _openOfferwall() async {
    if (!_authService.isSignedIn) {
      final signedIn = await requireSignIn(context, feature: 'Offerwall');
      if (!signedIn) return;
    }
    
    if (!mounted) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfferwallScreen(
          onReturn: () {
            // Refresh credits when returning from offerwall
            // Credits may take a few minutes to appear after completing offers
            _refreshCredits();
          },
        ),
      ),
    );
    
    // Also refresh when the navigation completes
    if (mounted) {
      _refreshCredits();
    }
  }
  
  /// Offerwall card - Opens AdGem offerwall for users to earn free gems
  /// Styled consistently with Daily Spin and Watch Ads cards
  Widget _buildOfferwallCard(ColorScheme cs) {
    // Green/teal theme for offerwall
    final List<Color> offerwallColors = [Colors.green.shade500, Colors.teal.shade600];
    
    return GestureDetector(
      onTap: _openOfferwall,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: offerwallColors[0].withOpacity(0.4),
          ),
      ),
      child: Row(
        children: [
            // Left section: Icon with gradient (like other cards when active)
          Container(
              padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: offerwallColors),
                borderRadius: BorderRadius.circular(8),
            ),
              child: const Icon(LucideIcons.gift, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
            // Middle section: Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offerwall',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                  const SizedBox(height: 2),
                Text(
                  'Complete offers for gems',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
            // Right section: FREE badge (like other cards)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: offerwallColors),
                borderRadius: BorderRadius.circular(6),
            ),
              child: const Text(
                'FREE',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
  
  /// Compact Daily Spin card for row layout
  Widget _buildCompactDailySpinCard(ColorScheme cs) {
    final bool showCountdown = !_canSpin && !_isCheckingSpinEligibility && !_needsEmailVerification;
    final bool isDisabled = _needsEmailVerification;
    final bool isActive = !isDisabled && _canSpin && !_isCheckingSpinEligibility;
    
    return GestureDetector(
      onTap: isDisabled ? _showVerificationRequiredSheet : _openDailySpinner,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: showCountdown 
              ? Colors.green.withOpacity(0.08)
              : isActive 
                  ? cs.primaryContainer.withOpacity(0.12)
                  : cs.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: showCountdown 
                ? Colors.green.withOpacity(0.3)
                : isActive 
                    ? cs.primary.withOpacity(0.4)
                    : cs.outline.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: isActive 
                        ? const LinearGradient(colors: KalaColors.brandGradient)
                        : null,
                    color: showCountdown 
                        ? Colors.green.withOpacity(0.12)
                        : isActive ? null : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    showCountdown ? LucideIcons.checkCircle2 : LucideIcons.gift,
                    size: 16,
                    color: showCountdown 
                        ? Colors.green 
                        : isActive ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: KalaColors.brandGradient),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'FREE',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Lucky Spin',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              showCountdown 
                  ? _formatSpinCountdown(_spinCountdownDuration)
                  : isActive ? 'Win up to 30 💎' : 'Verify email',
              style: TextStyle(
                color: showCountdown ? Colors.green.shade700 : cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Watch Ads card with 4 ads = 1 gem progress display
  Widget _buildWatchAdsCard(ColorScheme cs) {
    final bool hasReachedLimit = _adStatus?.hasReachedLimit ?? false;
    final bool isLoading = _isCheckingAdEligibility || _isShowingAd;
    final bool isDisabled = _needsEmailVerification;
    final bool isInCooldown = _adCooldownDuration.inSeconds > 0;
    final bool isActive = !isDisabled && !hasReachedLimit && !isInCooldown;
    final int adsWatchedToday = _adStatus?.adsWatchedToday ?? 0;
    final int earnedToday = _adStatus?.creditsEarnedToday ?? 0;
    
    // Progress toward next gem (0, 1, 2, or 3 ads watched toward next gem)
    final int progressToNextGem = adsWatchedToday % 4;
    
    return GestureDetector(
      onTap: isDisabled 
          ? _showVerificationRequiredSheet 
          : (isActive && !isLoading) ? _watchAdForCredits : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasReachedLimit 
              ? Colors.green.withOpacity(0.08)
              : isActive 
                  ? cs.primaryContainer.withOpacity(0.12)
                  : cs.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasReachedLimit 
                ? Colors.green.withOpacity(0.3)
                : isActive 
                    ? cs.primary.withOpacity(0.4)
                    : cs.outline.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: isActive 
                        ? const LinearGradient(colors: KalaColors.brandGradient)
                        : null,
                    color: hasReachedLimit 
                        ? Colors.green.withOpacity(0.12)
                        : isActive ? null : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        )
                      : Icon(
                          hasReachedLimit ? LucideIcons.checkCircle2 : LucideIcons.playCircle,
                          size: 16,
                          color: hasReachedLimit 
                              ? Colors.green 
                              : isActive ? Colors.white : cs.onSurfaceVariant,
                        ),
                ),
                const Spacer(),
                if (isInCooldown)
                  Text(
                    '${_adCooldownDuration.inSeconds}s',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (isActive && !hasReachedLimit)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: KalaColors.brandGradient),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'FREE',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Watch Ads',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            // Progress indicator: 4 ads = 1 gem
            if (hasReachedLimit) ...[
              Text(
                'Limit reached',
                style: TextStyle(color: Colors.green.shade700, fontSize: 11),
              ),
            ] else if (isDisabled) ...[
              Text(
                'Verify email',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ] else ...[
              // Visual progress: 4 dots showing progress to next gem
              Row(
                children: [
                  // Progress dots (4 total)
                  for (int i = 0; i < 4; i++) ...[
                  Container(
                      width: 10,
                      height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                        color: progressToNextGem > i ? cs.primary : cs.surfaceContainerHighest,
                      border: Border.all(
                          color: progressToNextGem > i 
                              ? cs.primary.withOpacity(0.5)
                              : cs.outline.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                      child: progressToNextGem > i 
                          ? Icon(LucideIcons.check, size: 6, color: cs.onPrimary)
                        : null,
                  ),
                    if (i < 3) const SizedBox(width: 2),
                  ],
                  const SizedBox(width: 4),
                  Text(
                    '= 1💎',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$earnedToday/30 💎',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Premium section - Combined Remove Ads + VIP
  Widget _buildPremiumSection(ColorScheme cs) {
    return Column(
      children: [
        // Remove Ads - Compact inline
        _buildCompactRemoveAdsCard(cs),
        const SizedBox(height: 10),
        // VIP Section
        _buildVipSection(cs),
      ],
    );
  }
  
  /// Compact Remove Ads card - styled consistently with gem packs
  Widget _buildCompactRemoveAdsCard(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Use brand gradient colors to match gem packs section
    const List<Color> removeAdColors = KalaColors.brandGradient;
    
    return ValueListenableBuilder<bool>(
      valueListenable: isAdFreeNotifier,
      builder: (context, isAdFree, _) {
        final removeAdsProduct = _purchaseService.removeAdsProduct;
        final price = removeAdsProduct?.price ?? '...';
        
        return GestureDetector(
          onTap: isAdFree ? null : _purchaseRemoveAds,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isAdFree 
                    ? [Colors.green.shade600.withOpacity(0.15), Colors.green.shade700.withOpacity(0.08)]
                    : isDark
                        ? [removeAdColors[0].withOpacity(0.15), removeAdColors[1].withOpacity(0.08)]
                        : [removeAdColors[0].withOpacity(0.1), removeAdColors[1].withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAdFree 
                    ? Colors.green.withOpacity(0.4)
                    : removeAdColors[0].withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isAdFree 
                      ? Colors.green.withOpacity(0.15)
                      : removeAdColors[0].withOpacity(0.15),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
            ),
              ],
          ),
          child: Row(
            children: [
                // Icon with gradient background
              Container(
                  padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isAdFree 
                          ? [Colors.green.shade500, Colors.green.shade700]
                          : removeAdColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                  color: isAdFree 
                            ? Colors.green.withOpacity(0.3)
                            : removeAdColors[0].withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                ),
                child: Icon(
                  isAdFree ? LucideIcons.checkCircle2 : LucideIcons.bellOff,
                  size: 18,
                    color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                  children: [
                    Text(
                      isAdFree ? 'Ad-Free Active' : 'Remove Ads',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                              fontWeight: FontWeight.w700,
                      ),
                    ),
                          if (!isAdFree) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: KalaColors.brandGradient),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'FOREVER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                    Text(
                        isAdFree ? 'Enjoying ad-free experience!' : 'One-time purchase, no subscription',
                      style: TextStyle(
                        color: isAdFree ? Colors.green.shade700 : cs.onSurfaceVariant,
                          fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isAdFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: KalaColors.brandGradient),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: KalaColors.brandGradient[0].withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      price,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.check, color: Colors.green, size: 18),
                  ),
            ],
            ),
          ),
        );
      },
    );
  }

  /// Build the gem packs section with modern design
  Widget _buildGemPacksSection(ColorScheme cs) {
    final products = _purchaseService.productsNotifier.value;
    final isLoading = _purchaseService.statusNotifier.value == IAPState.loadingProducts;
    final hasError = _purchaseService.statusNotifier.value == IAPState.error;
    
    // Get selected pack config for the buy button
    final selectedConfig = kGemPacks.firstWhere(
      (p) => p.productId == _selectedGemPackId,
      orElse: () => kGemPacks[2], // Default to Power Pack
    );
    final selectedProduct = _purchaseService.getProduct(_selectedGemPackId ?? '');
    
    // Loading state
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 12),
            Text(
              'Loading store...',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    
    // Error state
    if (hasError || products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.errorContainer.withOpacity(0.2),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          border: Border.all(color: cs.error.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.alertTriangle, color: cs.error, size: 32),
            const SizedBox(height: 8),
            Text(
              'Store unavailable',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _purchaseService.errorNotifier.value ?? 'Please try again later',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _purchaseService.loadProducts(),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    // Find featured pack (popular one)
    final featuredPack = kGemPacks.firstWhere((p) => p.isPopular, orElse: () => kGemPacks[2]);
    final featuredProduct = _purchaseService.getProduct(featuredPack.productId);
    
    // Other packs (excluding featured)
    final otherPacks = kGemPacks.where((p) => !p.isPopular).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Featured Pack - Large Hero Card
        _buildFeaturedPackCard(cs, featuredPack, featuredProduct),
        
        const SizedBox(height: 16),
        
        // Other Packs - Horizontal Scroll
        Text(
          'More Options',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none, // Allow badge to overflow
            padding: const EdgeInsets.only(top: 8), // Space for floating badge
            itemCount: otherPacks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final pack = otherPacks[index];
              final product = _purchaseService.getProduct(pack.productId);
              return _buildCompactPackCard(cs, pack, product);
            },
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Purchase Button
        if (selectedProduct != null)
          _buildPurchaseButton(cs, selectedConfig, selectedProduct),
      ],
    );
  }
  
  /// Build the featured/popular pack card (large hero style)
  Widget _buildFeaturedPackCard(ColorScheme cs, GemPackConfig pack, ProductDetails? product) {
    final bool isSelected = _selectedGemPackId == pack.productId;
    final bool isAvailable = product != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: isAvailable ? () {
        HapticFeedback.mediumImpact();
        setState(() => _selectedGemPackId = pack.productId);
      } : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    KalaColors.brandGradient[0].withOpacity(0.25),
                    KalaColors.brandGradient[1].withOpacity(0.15),
                  ]
                : isDark
                    ? [cs.surface, cs.surface]
                    : [Colors.white, cs.surfaceContainerHighest.withOpacity(0.5)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? KalaColors.brandGradient[0]
                : cs.outlineVariant.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: KalaColors.brandGradient[0].withOpacity(0.3),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            // Left: Gem Icon with glow
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: KalaColors.brandGradient,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: KalaColors.brandGradient[0].withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(LucideIcons.gem, size: 32, color: Colors.white),
                  // Sparkle effect
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      LucideIcons.sparkles,
                      size: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Middle: Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge + Title Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: KalaColors.brandGradient),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.flame, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'MOST POPULAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Pack name
                  Text(
                    '${pack.label} Pack',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Gem amount
                  Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: KalaColors.brandGradient,
                        ).createShader(bounds),
                        child: Text(
                          _formatGemAmount(pack.gems),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'gems',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Right: Price & Selection
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Price
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? KalaColors.brandGradient[0]
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isAvailable ? product.price : '...',
                    style: TextStyle(
                      color: isSelected ? Colors.white : cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Selection indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? KalaColors.brandGradient[0]
                        : cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected 
                          ? KalaColors.brandGradient[0]
                          : cs.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.check,
                    size: 14,
                    color: isSelected ? Colors.white : Colors.transparent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build compact pack card for horizontal scroll
  Widget _buildCompactPackCard(ColorScheme cs, GemPackConfig pack, ProductDetails? product) {
    final bool isSelected = _selectedGemPackId == pack.productId;
    final bool isAvailable = product != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Color scheme based on pack tier
    final List<Color> tierColors = pack.isBestValue
        ? [Colors.amber.shade600, Colors.orange.shade700]
        : pack.gems >= 5000
            ? [Colors.purple.shade400, Colors.purple.shade700]
            : pack.gems >= 1000
                ? [Colors.blue.shade400, Colors.blue.shade700]
                : [Colors.teal.shade400, Colors.teal.shade600];
    
    return GestureDetector(
      onTap: isAvailable ? () {
        HapticFeedback.selectionClick();
        setState(() => _selectedGemPackId = pack.productId);
      } : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 105,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isSelected
                ? [tierColors[0].withOpacity(0.2), tierColors[1].withOpacity(0.1)]
                : isDark
                    ? [cs.surfaceContainerHigh, cs.surface]
                    : [Colors.white, cs.surfaceContainerHighest.withOpacity(0.5)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? tierColors[0] : cs.outlineVariant.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: tierColors[0].withOpacity(0.25),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ] : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Badge for best value - positioned as overlay at top center
            if (pack.isBestValue)
              Positioned(
                top: -16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tierColors),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: tierColors[0].withOpacity(0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Text(
                      '⭐ BEST',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Main content - centered and fills width
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Add top spacing if has badge
                    if (pack.isBestValue) const SizedBox(height: 2),
                    
                    // Gem icon
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: tierColors),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tierColors[0].withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(LucideIcons.gem, size: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                
                // Gem amount
                Text(
                  _formatGemAmount(pack.gems),
                  style: TextStyle(
                    color: isSelected ? tierColors[0] : cs.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                // Pack label
                Text(
                  pack.label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 9,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                
                // Price
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? tierColors[0].withOpacity(0.15)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isAvailable ? product.price : '...',
                    style: TextStyle(
                      color: isSelected ? tierColors[0] : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                // Selection indicator
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      LucideIcons.checkCircle2,
                      size: 12,
                      color: tierColors[0],
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
  
  /// Format gem amount (e.g., 10000 -> 10K)
  String _formatGemAmount(int amount) {
    if (amount >= 1000) {
      final k = amount / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
    }
    return amount.toString();
  }
  
  /// Build the purchase button with selected pack summary
  Widget _buildPurchaseButton(ColorScheme cs, GemPackConfig pack, ProductDetails product) {
    final isSignedIn = _authService.isSignedIn;
    
    // Determine tier colors based on pack
    final List<Color> tierColors = pack.isPopular
        ? KalaColors.brandGradient
        : pack.isBestValue
            ? [Colors.amber.shade600, Colors.orange.shade700]
            : pack.gems >= 5000
                ? [Colors.purple.shade500, Colors.purple.shade700]
                : pack.gems >= 1000
                    ? [Colors.blue.shade500, Colors.blue.shade700]
                    : [Colors.teal.shade500, Colors.teal.shade700];
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tierColors[0].withOpacity(0.15),
            tierColors[1].withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tierColors[0].withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Selected pack summary header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColors[0].withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                // Gem icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: tierColors),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: tierColors[0].withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(LucideIcons.gem, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                // Pack details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pack name row
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${pack.label} Pack',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pack.isPopular || pack.isBestValue) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: tierColors),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                pack.isPopular ? '🔥POPULAR' : '⭐BEST',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Gems row
                      Row(
                        children: [
                          Icon(LucideIcons.gem, size: 12, color: tierColors[0]),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatGemAmount(pack.gems)} gems',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Price tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tierColors[0].withOpacity(0.3)),
                  ),
                  child: Text(
                    product.price,
                    style: TextStyle(
                      color: tierColors[0],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Buy button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: _isPurchasing
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tierColors),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: tierColors[0].withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Processing...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: isSignedIn ? () => _purchaseGemPack(pack.productId) : _showSignInPrompt,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tierColors),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: tierColors[0].withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSignedIn ? LucideIcons.shoppingCart : LucideIcons.logIn,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSignedIn ? 'Buy Now' : 'Sign in to Buy',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Purchase a gem pack
  Future<void> _purchaseGemPack(String productId) async {
    if (!_authService.isSignedIn) {
      _showSignInPrompt();
      return;
    }
    
    HapticFeedback.mediumImpact();
    
    // Set up completion callback
    _purchaseService.onPurchaseComplete = (purchasedProductId, success, error) {
      if (purchasedProductId == productId) {
        _purchaseService.onPurchaseComplete = null;
        if (success) {
          // Refresh credits to show updated balance
          _refreshCredits();
        }
      }
    };
    
    await _purchaseService.purchaseCreditPack(productId);
  }
  
  /// Restore purchases
  Future<void> _restorePurchases() async {
    if (!_authService.isSignedIn) {
      _showSignInPrompt();
      return;
    }
    
    HapticFeedback.mediumImpact();
    
    // Show loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text('Restoring purchases...'),
          ],
        ),
        duration: Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    final restored = await _purchaseService.restorePurchases();
    
    if (!mounted) return;
    
    // Clear the loading snackbar
    ScaffoldMessenger.of(context).clearSnackBars();
    
    if (restored) {
      // Ad-free was restored successfully
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Ad-free restored successfully!'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Refresh UI
      setState(() {});
    } else {
      // No purchases found or restore failed
      final error = _purchaseService.errorNotifier.value ?? 'No purchases to restore';
      
      // Check if the error is about purchase being linked to another account
      if (error.contains('another account')) {
        // Show a more detailed dialog for this case
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(LucideIcons.alertCircle, color: Colors.orange, size: 24),
                SizedBox(width: 10),
                Text('Purchase Linked'),
              ],
            ),
            content: const Text(
              'This ad-free purchase is already linked to a different account.\n\n'
              'Please sign in with the account you originally used to make the purchase.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        // Show regular snackbar for other errors
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.info, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(error),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  void _showSignInPrompt() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignInRequiredScreen(
          feature: 'Store',
          onSignInSuccess: () {
            _refreshCredits();
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }
  
  /// Show legal document (Privacy Policy or Terms of Service) in-app
  /// Fetches content from Pastebin raw URL and displays in a bottom sheet
  Future<void> _showLegalDocument({
    required String title,
    required String rawUrl,
  }) async {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    title.contains('Privacy') ? LucideIcons.shield : LucideIcons.fileText,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(LucideIcons.x, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            
            Divider(color: cs.outlineVariant.withOpacity(0.3), height: 1),
            
            // Content
            Expanded(
              child: FutureBuilder<String>(
                future: _fetchLegalContent(rawUrl),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: cs.primary),
                          const SizedBox(height: 16),
                          Text(
                            'Loading...',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.alertCircle, color: cs.error, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Could not load content',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please check your internet connection',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showLegalDocument(title: title, rawUrl: rawUrl);
                              },
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  return SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      snapshot.data!,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        height: 1.6,
                      ),
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
  
  /// Fetch legal content from Pastebin raw URL
  Future<String> _fetchLegalContent(String rawUrl) async {
    try {
      final response = await http.get(Uri.parse(rawUrl));
      if (response.statusCode == 200) {
        return response.body;
      }
      throw Exception('Failed to load content');
    } catch (e) {
      debugPrint('Error fetching legal content: $e');
      rethrow;
    }
  }

  void _purchaseRemoveAds() {
    if (!_authService.isSignedIn) {
      _showSignInPrompt();
      return;
    }
    
    final cs = Theme.of(context).colorScheme;
    final removeAdsProduct = _purchaseService.removeAdsProduct;
    final price = removeAdsProduct?.price ?? '\$2.99';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: KalaColors.brandGradient),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.bellOff,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Remove Ads',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enjoy an ad-free experience with a one-time purchase',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  
                  // Benefits
                  _buildAdFreeBenefit(cs, LucideIcons.bellOff, 'No ads anywhere in the app'),
                  const SizedBox(height: 10),
                  _buildAdFreeBenefit(cs, LucideIcons.download, 'Unlimited downloads without ads'),
                  const SizedBox(height: 10),
                  _buildAdFreeBenefit(cs, LucideIcons.zap, 'Faster, smoother experience'),
                  const SizedBox(height: 10),
                  _buildAdFreeBenefit(cs, LucideIcons.infinity, 'One-time purchase, forever'),
                  
                  const SizedBox(height: 24),
                  
                  ValueListenableBuilder<IAPState>(
                    valueListenable: _purchaseService.statusNotifier,
                    builder: (context, status, _) {
                      final isPurchasing = status == IAPState.purchasing || 
                                          status == IAPState.verifying;
                      
                      if (removeAdsProduct == null) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Product unavailable',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        );
                      }
                      
                      return GradientButton(
                        label: isPurchasing ? 'Processing...' : 'Purchase for $price',
                        icon: isPurchasing ? null : LucideIcons.shoppingBag,
                        onPressed: isPurchasing ? null : () async {
                          HapticFeedback.mediumImpact();
                          
                          // Set up completion callback
                          _purchaseService.onPurchaseComplete = (purchasedProductId, success, error) {
                            if (purchasedProductId == kRemoveAdsProductId) {
                              _purchaseService.onPurchaseComplete = null;
                              Navigator.pop(context);
                              if (success) {
                                _showPurchaseSuccessSnackBar(productId: purchasedProductId);
                              } else if (error != null && error != 'Cancelled') {
                                _showPurchaseErrorSnackBar(error, productId: purchasedProductId);
                              }
                            }
                          };
                          
                          await _purchaseService.purchaseRemoveAds();
                        },
                        variant: ButtonVariant.primary,
                        expanded: true,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Maybe later',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildAdFreeBenefit(ColorScheme cs, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.green),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
  
  // ============================================================
  // VIP MEMBERSHIP SECTION
  // ============================================================
  
  /// Build VIP membership section with status and purchase options
  Widget _buildVipSection(ColorScheme cs) {
    return ValueListenableBuilder<VipStatus>(
      valueListenable: vipStatusNotifier,
      builder: (context, vipStatus, _) {
        if (vipStatus.isVip) {
          return _buildActiveVipCard(cs, vipStatus);
        }
        return _buildVipPurchaseCard(cs);
      },
    );
  }

  /// Build card showing active VIP status - premium design
  Widget _buildActiveVipCard(ColorScheme cs, VipStatus status) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade700.withOpacity(0.15),
            Colors.orange.shade800.withOpacity(0.08),
            Colors.amber.shade600.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.shade600.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header section with gradient overlay
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.shade600.withOpacity(0.1),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First row: Icon + Title + Extend button
                Row(
                  children: [
                    // Crown icon with glow
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade500, Colors.orange.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(LucideIcons.crown, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // Title and status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [Colors.amber.shade600, Colors.orange.shade700],
                            ).createShader(bounds),
                            child: const Text(
                              'VIP Member',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(LucideIcons.timer, size: 11, color: Colors.amber.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '${status.daysRemaining} days left',
                                style: TextStyle(
                                  color: Colors.amber.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // ACTIVE badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade500, Colors.green.shade700],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.checkCircle2, size: 9, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            'ACTIVE',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    // Extend button
                    GestureDetector(
                      onTap: () => _showVipPurchaseSheet(cs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.amber.shade600, Colors.orange.shade700],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.plus, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Extend',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Benefits section
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildVipActiveBenefit(LucideIcons.layers, 'Bulk Edit'),
                _buildVipActiveBenefit(LucideIcons.copy, '4 Variants'),
                _buildVipActiveBenefit(LucideIcons.maximize2, 'Free Upscale'),
                _buildVipActiveBenefit(LucideIcons.zap, '25 Concurrent Jobs'),
                _buildVipActiveBenefit(LucideIcons.eyeOff, 'Ad-Free'),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVipActiveBenefit(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.amber.shade700),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.amber.shade800,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  

  Widget _buildVipBenefitRow(ColorScheme cs, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(color: cs.onSurface, fontSize: 13),
          ),
        ],
      ),
    );
  }


  /// Build card with VIP purchase options - premium design
  Widget _buildVipPurchaseCard(ColorScheme cs) {
    return ValueListenableBuilder<List<ProductDetails>>(
      valueListenable: _purchaseService.productsNotifier,
      builder: (context, products, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.amber.shade700.withOpacity(0.08),
                Colors.orange.shade800.withOpacity(0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.amber.shade600.withOpacity(0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Premium header with subtle gradient overlay
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade600.withOpacity(0.08),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    // Crown icon with glow effect
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade500, Colors.orange.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(LucideIcons.crown, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [Colors.amber.shade600, Colors.orange.shade700],
                            ).createShader(bounds),
                            child: const Text(
                              'VIP Membership',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Unlock premium features',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Benefits preview
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _buildVipBenefitTag(cs, LucideIcons.layers, 'Bulk Edit up to 10 images'),
                    _buildVipBenefitTag(cs, LucideIcons.copy, 'Up to 4 Variants'),
                    _buildVipBenefitTag(cs, LucideIcons.maximize2, 'Free Upscale'),
                    _buildVipBenefitTag(cs, LucideIcons.zap, 'Upto 25 jobs at once'),
                    _buildVipBenefitTag(cs, LucideIcons.eyeOff, 'Ad Free'),
                  ],
                ),
              ),
              
              const SizedBox(height: 14),
              
              // Purchase options
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: kVipPacks.map((pack) => Padding(
                    padding: EdgeInsets.only(bottom: pack != kVipPacks.last ? 8 : 0),
                    child: _buildVipPackOptionCard(cs, pack, products),
                  )).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildVipBenefitTag(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.amber.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.amber.shade800,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVipPackOptionCard(ColorScheme cs, VipPackConfig pack, List<ProductDetails> products) {
    final hasProduct = products.any((p) => p.id == pack.productId);
    final product = hasProduct ? products.firstWhere((p) => p.id == pack.productId) : null;
    final price = hasProduct ? product!.price : '...';
    final bool isPopular = pack.productId == kVipMonthlyProductId;
    final bool hasBadge = isPopular || pack.savings != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // VIP tier colors - amber/gold theme
    final List<Color> vipColors = [Colors.amber.shade600, Colors.orange.shade700];
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasProduct ? () => _purchaseVipPack(pack.productId) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isPopular 
                  ? [vipColors[0].withOpacity(0.15), vipColors[1].withOpacity(0.08)]
                  : isDark
                      ? [vipColors[0].withOpacity(0.08), vipColors[1].withOpacity(0.04)]
                      : [vipColors[0].withOpacity(0.06), vipColors[1].withOpacity(0.03)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPopular 
                  ? vipColors[0].withOpacity(0.5)
                  : vipColors[0].withOpacity(0.25),
              width: isPopular ? 1.5 : 1,
            ),
            boxShadow: isPopular ? [
              BoxShadow(
                color: vipColors[0].withOpacity(0.15),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            children: [
              // Duration icon with gradient
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isPopular 
                        ? vipColors
                        : [vipColors[0].withOpacity(0.8), vipColors[1].withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: vipColors[0].withOpacity(isPopular ? 0.4 : 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  pack.days <= 7 ? LucideIcons.calendar : 
                  pack.days <= 30 ? LucideIcons.calendarDays : 
                  LucideIcons.calendarRange,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              // Label and badge column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // First row: label and days
                    Row(
                      children: [
                        Text(
                          pack.label,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${pack.days}d',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    // Second row: badge (if any)
                    if (hasBadge) ...[
                      const SizedBox(height: 3),
                      if (isPopular)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: vipColors),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '⭐ POPULAR',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (pack.savings != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            pack.savings!,
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Price button - styled consistently with gem packs
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: vipColors),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: vipColors[0].withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  
  /// Purchase VIP pack
  void _purchaseVipPack(String productId) {
    if (!_authService.isSignedIn) {
      _showSignInPrompt();
      return;
    }
    
    final cs = Theme.of(context).colorScheme;
    final product = _purchaseService.getProduct(productId);
    final pack = kVipPacks.firstWhere((p) => p.productId == productId);
    
    // Show confirmation bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewPadding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(LucideIcons.crown, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'VIP ${pack.label}',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${pack.days} days of premium features',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            
            // Benefits
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildVipBenefitRow(cs, LucideIcons.layers, 'Bulk edit up to 10 images'),
                  _buildVipBenefitRow(cs, LucideIcons.copy, 'Up to 4 variations per job'),
                  _buildVipBenefitRow(cs, LucideIcons.maximize2, 'Free upscaling'),
                  _buildVipBenefitRow(cs, LucideIcons.zap, '25 concurrent jobs (vs 5 for free)'),
                  _buildVipBenefitRow(cs, LucideIcons.eyeOff, 'Ad-free experience'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Purchase button
            ValueListenableBuilder<IAPState>(
              valueListenable: _purchaseService.statusNotifier,
              builder: (context, status, _) {
                final isPurchasing = status == IAPState.purchasing || 
                                    status == IAPState.verifying;
                final price = product?.price ?? '...';
                
                if (product == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Product unavailable',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                
                return GradientButton(
                  label: isPurchasing ? 'Processing...' : 'Purchase for $price',
                  icon: isPurchasing ? null : LucideIcons.crown,
                  onPressed: isPurchasing ? null : () async {
                    HapticFeedback.mediumImpact();
                    
                    // Set up completion callback
                    _purchaseService.onPurchaseComplete = (purchasedProductId, success, error) {
                      if (purchasedProductId == productId) {
                        _purchaseService.onPurchaseComplete = null;
                        Navigator.pop(context);
                        if (success) {
                          _showVipPurchaseSuccessSnackBar();
                        } else if (error != null && error != 'Cancelled') {
                          _showPurchaseErrorSnackBar(error, productId: purchasedProductId);
                        }
                      }
                    };
                    
                    await _purchaseService.purchaseVipPack(productId);
                  },
                  variant: ButtonVariant.primary,
                  expanded: true,
                );
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Maybe later',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVipPurchaseSheet(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewPadding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Extend VIP Membership',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<List<ProductDetails>>(
              valueListenable: _purchaseService.productsNotifier,
              builder: (context, products, _) {
                return Column(
                  children: [
                    for (final pack in kVipPacks) ...[
                      _buildVipPackOptionForExtend(cs, pack, products, sheetContext),
                      if (pack != kVipPacks.last) const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// VIP pack option specifically for extend sheet - closes extend sheet before purchase
  Widget _buildVipPackOptionForExtend(
    ColorScheme cs, 
    VipPackConfig pack,
    List<ProductDetails> products,
    BuildContext sheetContext,
  ) {
    // Get price from store (dynamic, localized) - safely handle empty/missing products
    final hasProduct = products.any((p) => p.id == pack.productId);
    final product = hasProduct 
        ? products.firstWhere((p) => p.id == pack.productId) 
        : null;
    final price = hasProduct ? product!.price : '...';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // VIP tier colors - amber/gold theme
    final List<Color> vipColors = [Colors.amber.shade600, Colors.orange.shade700];
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasProduct ? () {
          // Close the extend sheet first, then open purchase sheet
          Navigator.pop(sheetContext);
          _purchaseVipPack(pack.productId);
        } : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [vipColors[0].withOpacity(0.1), vipColors[1].withOpacity(0.05)]
                  : [vipColors[0].withOpacity(0.08), vipColors[1].withOpacity(0.04)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: vipColors[0].withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Duration icon with gradient
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: vipColors),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: vipColors[0].withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  pack.days <= 7 ? LucideIcons.calendar : 
                  pack.days <= 30 ? LucideIcons.calendarDays : 
                  LucideIcons.calendarRange,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.label,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (pack.savings != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              pack.savings!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pack.days} days of VIP access',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Price button - styled consistently
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: vipColors),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: vipColors[0].withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVipPurchaseSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(LucideIcons.crown, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('VIP activated! Enjoy premium features.'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

// Confirm Exit App Dialog (for base pages)
class _ConfirmExitAppDialog extends StatelessWidget {
  const _ConfirmExitAppDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.logOut,
              size: 40,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exit App?',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Exit',
                icon: LucideIcons.logOut,
                onPressed: () => Navigator.pop(context, true),
                variant: ButtonVariant.danger,
                size: ButtonSize.medium,
                expanded: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// DAILY SPINNER PAGE
// ============================================================

/// Spinner reward segments with realistic probabilities
/// Total probability = 100%
class SpinnerReward {
  final int credits;
  final double probability; // 0.0 to 1.0
  final Color color;
  final String label;

  const SpinnerReward({
    required this.credits,
    required this.probability,
    required this.color,
    required this.label,
  });
}

class DailySpinnerPage extends StatefulWidget {
  final Function(int credits)? onCreditsWon;

  const DailySpinnerPage({super.key, this.onCreditsWon});

  @override
  State<DailySpinnerPage> createState() => _DailySpinnerPageState();
}

class _DailySpinnerPageState extends State<DailySpinnerPage>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  
  late AnimationController _controller;
  double _baseRotation = 0;  // Rotation before current spin
  double _targetRotation = 0; // Target rotation for current spin
  
  bool _isSpinning = false;
  bool _canSpin = true;
  bool _isCheckingEligibility = true;
  DateTime? _nextSpinDateTime;
  Timer? _countdownTimer;
  Duration _countdownDuration = Duration.zero;
  
  // Spinner segments - realistic probability distribution
  // Order matters: segments are drawn clockwise starting from top
  static const List<SpinnerReward> _rewards = [
    SpinnerReward(credits: 1, probability: 0.35, color: Color(0xFF6B7280), label: '1'),
    SpinnerReward(credits: 2, probability: 0.30, color: Color(0xFF3B82F6), label: '2'),
    SpinnerReward(credits: 5, probability: 0.20, color: Color(0xFF10B981), label: '5'),
    SpinnerReward(credits: 10, probability: 0.07, color: Color(0xFF8B5CF6), label: '10'),
    SpinnerReward(credits: 20, probability: 0.06, color: Color(0xFFF59E0B), label: '20'),
    SpinnerReward(credits: 30, probability: 0.02, color: Color(0xFFEF4444), label: '30'),
  ];
  
  // Get current wheel rotation angle
  double get _currentRotation {
    if (!_isSpinning) return _baseRotation;
    // Interpolate between base and target based on animation progress
    final progress = Curves.easeOutCubic.transform(_controller.value);
    return _baseRotation + (_targetRotation - _baseRotation) * progress;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    
    _controller.addListener(() {
      setState(() {});
    });
    
    _checkSpinEligibility();
  }

  @override
  void dispose() {
    _controller.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (_nextSpinDateTime == null) return;
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final remaining = _nextSpinDateTime!.difference(now);
      
      if (remaining.isNegative) {
        timer.cancel();
        setState(() {
          _canSpin = true;
          _countdownDuration = Duration.zero;
        });
      } else {
        setState(() {
          _countdownDuration = remaining;
        });
      }
    });
    
    // Initial update
    final now = DateTime.now();
    final remaining = _nextSpinDateTime!.difference(now);
    setState(() {
      _countdownDuration = remaining.isNegative ? Duration.zero : remaining;
    });
  }

  String _formatCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Future<void> _checkSpinEligibility() async {
    setState(() => _isCheckingEligibility = true);
    
    try {
      final result = await _userService.checkDailySpinEligibility();
      
      if (mounted) {
        final nextSpinStr = result['next_spin_time'] as String?;
        DateTime? nextSpinDt;
        
        // Try to parse server timestamp
        if (nextSpinStr != null && nextSpinStr != 'Tomorrow') {
          try {
            nextSpinDt = DateTime.parse(nextSpinStr);
          } catch (_) {
            // Fallback: assume next day at midnight UTC
            nextSpinDt = DateTime.now().toUtc().add(const Duration(days: 1));
            nextSpinDt = DateTime.utc(nextSpinDt.year, nextSpinDt.month, nextSpinDt.day);
          }
        }
        
        setState(() {
          _canSpin = result['can_spin'] ?? true;
          _nextSpinDateTime = nextSpinDt;
          _isCheckingEligibility = false;
        });
        
        if (!_canSpin && _nextSpinDateTime != null) {
          _startCountdownTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _canSpin = false;
          _isCheckingEligibility = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking spin eligibility: $e')),
        );
      }
    }
  }

  Future<void> _spin() async {
    if (_isSpinning || !_canSpin) return;
    
    setState(() {
      _isSpinning = true;
    });
    
    try {
      // Call server to perform spin
      // Server determines the reward (tamper-proof) and grants credits
      final result = await _userService.performDailySpin();
      final wonCredits = result['credits_won'] as int? ?? 0;
      
      // Calculate which segment to land on
      final segmentIndex = _rewards.indexWhere((r) => r.credits == wonCredits);
      final targetSegment = segmentIndex >= 0 ? segmentIndex : 0;
      
      // Calculate rotation to land on target segment
      // Wheel segments are drawn starting from TOP (-pi/2) going clockwise
      // Pointer is fixed at TOP
      // Formula: to land on center of segment T, rotate by (n - T - 0.5) * segmentAngle
      // where n = number of segments
      final segmentCount = _rewards.length;
      final segmentAngle = (2 * pi) / segmentCount;
      
      // Landing offset from rotation 0 to center of target segment
      final landingOffset = (segmentCount - targetSegment - 0.5) * segmentAngle;
      
      // Normalize current rotation to find where we are now
      final currentAngle = _baseRotation % (2 * pi);
      
      // Calculate additional rotation needed from current position
      var additionalRotation = landingOffset - currentAngle;
      if (additionalRotation < 0) additionalRotation += 2 * pi;
      
      // Add full rotations for visual effect (5-7 full spins)
      final fullRotations = 5 + Random().nextInt(3);
      final totalRotation = (fullRotations * 2 * pi) + additionalRotation;
      
      debugPrint('🎰 Spin calculation:');
      debugPrint('   Won: $wonCredits gems (segment $targetSegment)');
      debugPrint('   Segment angle: ${(segmentAngle * 180 / pi).toStringAsFixed(1)}°');
      debugPrint('   Landing offset: ${(landingOffset * 180 / pi).toStringAsFixed(1)}°');
      debugPrint('   Current angle: ${(currentAngle * 180 / pi).toStringAsFixed(1)}°');
      debugPrint('   Additional rotation: ${(additionalRotation * 180 / pi).toStringAsFixed(1)}°');
      debugPrint('   Total rotation: ${(totalRotation * 180 / pi).toStringAsFixed(1)}° ($fullRotations full spins)');
      
      // Set animation targets
      _targetRotation = _baseRotation + totalRotation;
      
      _controller.reset();
      await _controller.forward();
      
      // Update base rotation for next spin (keep within reasonable range)
      _baseRotation = _targetRotation % (2 * pi * 100); // Prevent overflow over many spins
      
      // Parse next spin time from response
      final nextSpinStr = result['next_spin_time'] as String?;
      DateTime? nextSpinDt;
      if (nextSpinStr != null && nextSpinStr != 'Tomorrow') {
        try {
          nextSpinDt = DateTime.parse(nextSpinStr);
        } catch (_) {
          nextSpinDt = DateTime.now().add(const Duration(hours: 24));
        }
      } else {
        // Fallback: 24 hours from now
        nextSpinDt = DateTime.now().add(const Duration(hours: 24));
      }
      
      if (mounted) {
        setState(() {
          _isSpinning = false;
          _canSpin = false;
          _nextSpinDateTime = nextSpinDt;
        });
        
        // Start countdown timer
        _startCountdownTimer();
        
        // Show win dialog
        _showWinDialog(wonCredits);
        
        // Notify parent
        widget.onCreditsWon?.call(wonCredits);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSpinning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showWinDialog(int credits) {
    final cs = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebration icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: KalaColors.brandGradient),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.partyPopper,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            
            Text(
              'Congratulations!',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            Text(
              'You won',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.gem, size: 32, color: KalaColors.gold),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: KalaColors.brandGradient,
                  ).createShader(bounds),
                  child: Text(
                    '$credits',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              credits == 1 ? 'Gem' : 'Gems',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: GradientButton(
              label: 'Awesome!',
              icon: LucideIcons.sparkles,
              onPressed: () => Navigator.pop(context),
              variant: ButtonVariant.primary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(
          'Lucky Spin',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isCheckingEligibility
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Spinner wheel
                          SizedBox(
                            width: 300,
                            height: 300,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Wheel
                                Transform.rotate(
                                  angle: _currentRotation,
                                  child: CustomPaint(
                                    size: const Size(280, 280),
                                    painter: SpinnerWheelPainter(rewards: _rewards),
                                  ),
                                ),
                                
                                // Center button
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: KalaColors.brandGradient,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: KalaColors.purple.withOpacity(0.4),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    LucideIcons.gem,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                                
                                // Pointer at top
                                Positioned(
                                  top: 0,
                                  child: CustomPaint(
                                    size: const Size(30, 30),
                                    painter: PointerPainter(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          
                          // Spin button or cooldown message
                          if (_canSpin) ...[
                            GradientButton(
                              label: _isSpinning ? 'Spinning...' : 'SPIN NOW',
                              icon: LucideIcons.rotateCw,
                              onPressed: _isSpinning ? null : _spin,
                              variant: ButtonVariant.primary,
                              size: ButtonSize.large,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '1 free spin per day',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: cs.outline.withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.lock,
                                        color: cs.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Next spin in',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Countdown timer
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          cs.primary.withOpacity(0.1),
                                          cs.secondary.withOpacity(0.1),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.timer,
                                          color: cs.primary,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          _formatCountdown(_countdownDuration),
                                          style: TextStyle(
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 22,
                                            fontFamily: 'monospace',
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // (Removed "Server time locked" label as instructed)
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  // Rewards legend
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Possible Rewards',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _rewards.map((r) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: r.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: r.color.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.gem, size: 14, color: r.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${r.credits}',
                                    style: TextStyle(
                                      color: r.color,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ============================================================
// SPINNER WHEEL PAINTER
// ============================================================

class SpinnerWheelPainter extends CustomPainter {
  final List<SpinnerReward> rewards;

  SpinnerWheelPainter({required this.rewards});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = (2 * pi) / rewards.length;
    
    // Draw segments
    for (int i = 0; i < rewards.length; i++) {
      final startAngle = i * segmentAngle - pi / 2;
      
      // Segment paint
      final paint = Paint()
        ..color = rewards[i].color
        ..style = PaintingStyle.fill;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );
      
      // Segment border
      final borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        borderPaint,
      );
      
      // Draw text
      final textAngle = startAngle + segmentAngle / 2;
      final textRadius = radius * 0.65;
      final textX = center.dx + textRadius * cos(textAngle);
      final textY = center.dy + textRadius * sin(textAngle);
      
      // Save canvas state
      canvas.save();
      canvas.translate(textX, textY);
      canvas.rotate(textAngle + pi / 2);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: rewards[i].label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      
      canvas.restore();
    }
    
    // Draw outer border
    final outerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    
    canvas.drawCircle(center, radius, outerBorderPaint);
    
    // Draw inner circle
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius * 0.2, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// POINTER PAINTER
// ============================================================

class PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: KalaColors.brandGradient,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final path = Path();
    path.moveTo(size.width / 2, size.height);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.close();
    
    canvas.drawPath(path, paint);
    
    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
