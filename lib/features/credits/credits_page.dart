import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
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
  bool _isRefreshing = false;
  
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
    
    // Refresh credits on page load if signed in
    if (_authService.isSignedIn) {
      _refreshCredits();
      _checkSpinEligibility();
      _checkAdEligibility();
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
      final signedIn = await requireSignIn(context, feature: 'earning credits');
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
    
    // credits = 0 means this was an odd ad (1st, 3rd, 5th...) - no credit earned yet
    // credits > 0 means this was an even ad (2nd, 4th, 6th...) - credit was earned
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
                  Icon(LucideIcons.gem, size: 28, color: KalaColors.gold),
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
                credits == 1 ? 'Credit' : 'Credits',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ] else ...[
              // Progress message - watched 1 ad, need 1 more
              Text(
                'Ad watched!',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Visual progress: 1 filled, 1 empty
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                    child: Icon(LucideIcons.check, size: 14, color: cs.onPrimary),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outline, width: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1 more ad for 1 credit',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
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
                'You\'ve watched ${_adStatus?.dailyLimit ?? 30} ads today.\nCome back tomorrow for more free credits!',
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
                'Please verify your email address to unlock free credits features like Lucky Spin and Watch Ads.',
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
                                content: Row(
                                  children: [
                                    const Icon(LucideIcons.mailCheck, color: Colors.white, size: 18),
                                    const SizedBox(width: 10),
                                    const Expanded(child: Text('Verification email sent!')),
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
                                content: Row(
                                  children: [
                                    const Icon(LucideIcons.checkCircle, color: Colors.white, size: 18),
                                    const SizedBox(width: 10),
                                    const Expanded(child: Text('Email verified! Features unlocked.')),
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
                                content: Row(
                                  children: [
                                    const Icon(LucideIcons.alertCircle, color: Colors.white, size: 18),
                                    const SizedBox(width: 10),
                                    const Expanded(child: Text('Email not verified yet. Check your inbox.')),
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
                        'You can still purchase credits without verification.',
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

  void _buyCredits() {
    // TODO: Implement in-app purchase
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon!')),
    );
  }

  void _showAuthSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignInRequiredScreen(
          feature: 'Credits',
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSignedIn = _authService.isSignedIn;
    
    return Scaffold(
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
              tooltip: 'Refresh credits',
            ),
        ],
      ),
      body: isSignedIn 
          ? _buildCreditsContent(cs)
          : _buildSignInPrompt(cs),
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
            'Sign in to manage credits',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an account to earn and use credits for AI tools',
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.gift, size: 20, color: KalaColors.gold),
                const SizedBox(width: 8),
                Text(
                  '50 free credits on signup!',
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
            description: 'Earn free credits by watching ads',
          ),
          const SizedBox(height: 16),
          _buildBenefit(
            cs,
            icon: LucideIcons.cloud,
            title: 'Sync Everywhere',
            description: 'Your credits sync across all devices',
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
      padding: const EdgeInsets.all(AppStyles.spacing24),
      child: Column(
        children: [
          // Credits display card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppStyles.spacing24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KalaColors.purple.withOpacity(0.15),
                  KalaColors.cyan.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppStyles.radiusLg),
              border: Border.all(
                color: KalaColors.purple.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                // Icon with gradient
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: KalaColors.brandGradient),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.gem,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppStyles.spacing16),
                Text(
                  'Your Credits',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: AppStyles.spacing8),
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
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppStyles.spacing8),
                Text(
                  'Use credits to generate AI content',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppStyles.spacing32),
          
          // Daily Spinner Section
          _buildSectionHeader(cs, 'Daily Bonus', LucideIcons.sparkles),
          const SizedBox(height: AppStyles.spacing12),
          
          // Daily Spinner Card
          _buildDailySpinnerCard(cs),
          const SizedBox(height: AppStyles.spacing24),
          
          // Earn Credits Section
          _buildSectionHeader(cs, 'Earn Credits', LucideIcons.gift),
          const SizedBox(height: AppStyles.spacing12),
          
          // Watch Ad Card
          _buildWatchAdCard(cs),
          const SizedBox(height: AppStyles.spacing24),
          
          // Buy Credits Section
          _buildSectionHeader(cs, 'Buy Credits', LucideIcons.creditCard),
          const SizedBox(height: AppStyles.spacing12),
          
          // Credit Packs
          _buildCreditPack(cs, amount: 100, price: '\$0.99', popular: false),
          const SizedBox(height: AppStyles.spacing12),
          _buildCreditPack(cs, amount: 500, price: '\$3.99', popular: true),
          const SizedBox(height: AppStyles.spacing12),
          _buildCreditPack(cs, amount: 1000, price: '\$6.99', popular: false),
          
          const SizedBox(height: AppStyles.spacing32),
          
          // Info text
          Text(
            'Credits never expire. Use them anytime for AI generation.',
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

  Widget _buildWatchAdCard(ColorScheme cs) {
    final bool hasReachedLimit = _adStatus?.hasReachedLimit ?? false;
    final bool isLoading = _isCheckingAdEligibility || _isShowingAd;
    final int earnedToday = _adStatus?.creditsEarnedToday ?? 0;
    final int dailyLimit = _adStatus?.dailyLimit ?? 30;
    final bool isDisabled = _needsEmailVerification;
    final bool isInCooldown = _adCooldownDuration.inSeconds > 0;
    final adAvailability = _adService.availabilityNotifier.value;
    final bool isAdUnavailable = adAvailability == AdAvailability.unavailable;
    final bool isAdLoading = adAvailability == AdAvailability.loading;
    
    return GestureDetector(
      onTap: isDisabled ? _showVerificationRequiredSheet : null,
      child: Container(
        padding: const EdgeInsets.all(AppStyles.spacing16),
        decoration: BoxDecoration(
          color: (hasReachedLimit || isDisabled)
              ? cs.surfaceContainerHighest.withOpacity(0.3)
              : null,
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          border: Border.all(
            color: (hasReachedLimit || isDisabled)
                ? cs.outline.withOpacity(0.2)
                : cs.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (hasReachedLimit || isDisabled)
                        ? cs.surfaceContainerHighest
                        : cs.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isDisabled ? LucideIcons.mailWarning : LucideIcons.playCircle, 
                    color: (hasReachedLimit || isDisabled) ? cs.onSurfaceVariant : cs.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch Ad',
                        style: TextStyle(
                          color: isDisabled ? cs.onSurfaceVariant : cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isDisabled)
                        Row(
                          children: [
                            Icon(LucideIcons.shieldAlert, size: 12, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Verify email to unlock',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (hasReachedLimit)
                        Row(
                          children: [
                            Icon(LucideIcons.timer, size: 12, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Resets in ${_formatAdResetCountdown(_adResetCountdownDuration)}',
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      else if (isInCooldown && _adStatus != null)
                        // Show progress indicator during cooldown (timer is on button)
                        _buildAdProgressIndicator(cs, _adStatus!)
                      else if (isAdUnavailable)
                        Row(
                          children: [
                            Icon(LucideIcons.alertCircle, size: 12, color: cs.error),
                            const SizedBox(width: 4),
                            Text(
                              'No ads available',
                              style: TextStyle(
                                color: cs.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        // Show progress toward next credit with visual indicator
                        if (_adStatus != null && _adStatus!.adsRequiredForCredit == 2) ...[
                          _buildAdProgressIndicator(cs, _adStatus!),
                        ] else ...[
                          Text(
                            '$earnedToday/$dailyLimit credits earned today',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (isDisabled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.mail, size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Verify',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isLoading)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                else if (hasReachedLimit)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.lock, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Limit',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                // Show cooldown timer between ads
                else if (isInCooldown)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.clock, size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '${_adCooldownDuration.inSeconds}s',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                // Show when no ads available (low fill rate)
                else if (isAdUnavailable)
                  GestureDetector(
                    onTap: () => _adService.forceRefreshAd(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.refreshCw, size: 14, color: cs.error),
                          const SizedBox(width: 4),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // Show when ad is loading in background
                else if (isAdLoading && !_adService.isAdReadyNotifier.value)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GradientButton(
                    label: 'Watch',
                    icon: LucideIcons.play,
                    onPressed: _watchAdForCredits,
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                  ),
              ],
            ),
            // Progress bar showing daily limit
            if (!_isCheckingAdEligibility && earnedToday > 0 && !isDisabled) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: earnedToday / dailyLimit,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    hasReachedLimit ? cs.outline : cs.primary,
                  ),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Build progress indicator showing ads watched toward next credit
  Widget _buildAdProgressIndicator(ColorScheme cs, RewardedAdStatus status) {
    final adsWatched = status.adsWatchedToday;
    final adsRequired = status.adsRequiredForCredit;
    final adsInCurrentCycle = adsWatched % adsRequired; // 0 or 1
    final willEarnNext = adsInCurrentCycle == 1; // Next ad (2nd) will earn credit
    final creditsEarned = status.creditsEarnedToday;
    final dailyLimit = status.dailyLimit;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress dots showing current cycle progress
        Row(
          children: [
            // Circle 1 - filled if we've watched at least 1 ad in this cycle
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: adsInCurrentCycle >= 1 ? cs.primary : cs.surfaceContainerHighest,
                border: Border.all(
                  color: adsInCurrentCycle >= 1 ? cs.primary : cs.outline.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: adsInCurrentCycle >= 1
                  ? Icon(LucideIcons.check, size: 8, color: cs.onPrimary)
                  : null,
            ),
            const SizedBox(width: 4),
            // Circle 2 - always empty (resets after earning credit)
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest,
                border: Border.all(
                  color: cs.outline.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Status text
            Expanded(
              child: Text(
                willEarnNext
                    ? 'Next ad = +1 credit!'
                    : '2 ads = 1 credit',
                style: TextStyle(
                  color: willEarnNext ? Colors.amber.shade700 : cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: willEarnNext ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Credits earned today
        Text(
          '$creditsEarned/$dailyLimit credits today',
          style: TextStyle(
            color: cs.onSurfaceVariant.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDailySpinnerCard(ColorScheme cs) {
    final bool showCountdown = !_canSpin && !_isCheckingSpinEligibility && !_needsEmailVerification;
    final bool isDisabled = _needsEmailVerification;
    
    return GestureDetector(
      onTap: isDisabled ? _showVerificationRequiredSheet : _openDailySpinner,
      child: Container(
        padding: const EdgeInsets.all(AppStyles.spacing16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDisabled || showCountdown
                ? [cs.surfaceContainerHighest.withOpacity(0.5), cs.surfaceContainerHighest.withOpacity(0.3)]
                : [KalaColors.gold.withOpacity(0.15), Colors.orange.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          border: Border.all(
            color: isDisabled || showCountdown 
                ? cs.outline.withOpacity(0.2)
                : KalaColors.gold.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Spinner icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: (isDisabled || showCountdown)
                    ? null
                    : LinearGradient(colors: [KalaColors.gold, Colors.orange.shade600]),
                color: (isDisabled || showCountdown) ? cs.surfaceContainerHighest : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isDisabled ? LucideIcons.mailWarning : LucideIcons.gift,
                color: (isDisabled || showCountdown) ? cs.onSurfaceVariant : Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Lucky Spin',
                        style: TextStyle(
                          color: isDisabled ? cs.onSurfaceVariant : cs.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isCheckingSpinEligibility && !isDisabled)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KalaColors.gold,
                          ),
                        )
                      else if (_canSpin && !isDisabled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: KalaColors.gold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'FREE',
                            style: TextStyle(
                              color: KalaColors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (isDisabled)
                    Row(
                      children: [
                        Icon(LucideIcons.shieldAlert, size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Verify email to unlock',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (showCountdown)
                    Row(
                      children: [
                        Icon(LucideIcons.timer, size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          _formatSpinCountdown(_spinCountdownDuration),
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Win up to 30 credits daily!',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            if (isDisabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.mail, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Verify',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (_canSpin && !_isCheckingSpinEligibility)
              GradientButton(
                label: 'Spin',
                icon: LucideIcons.sparkles,
                onPressed: _openDailySpinner,
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
              )
            else if (showCountdown)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.lock, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Wait',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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

  Widget _buildCreditPack(ColorScheme cs, {
    required int amount,
    required String price,
    required bool popular,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppStyles.spacing16),
      decoration: BoxDecoration(
        color: popular ? cs.primaryContainer.withOpacity(0.2) : null,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        border: Border.all(
          color: popular ? cs.primary.withOpacity(0.4) : cs.outlineVariant.withOpacity(0.3),
          width: popular ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Coin icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: popular 
                  ? const LinearGradient(colors: KalaColors.brandGradient)
                  : null,
              color: popular ? null : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              LucideIcons.gem,
              color: popular ? Colors.white : cs.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Use Wrap instead of Row to handle overflow gracefully
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      '$amount Credits',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (popular)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: KalaColors.brandGradient),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'POPULAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  price,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GradientButton(
            label: 'Buy',
            icon: LucideIcons.shoppingCart,
            onPressed: _buyCredits,
            variant: popular ? ButtonVariant.primary : ButtonVariant.secondary,
            size: ButtonSize.small,
          ),
        ],
      ),
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
      debugPrint('   Won: $wonCredits credits (segment $targetSegment)');
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
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: KalaColors.brandGradient),
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
                Icon(LucideIcons.gem, size: 32, color: KalaColors.gold),
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
              credits == 1 ? 'Credit' : 'Credits',
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
                                  child: Icon(
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
