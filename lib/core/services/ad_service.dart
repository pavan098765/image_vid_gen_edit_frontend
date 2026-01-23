// lib/core/services/ad_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'user_service.dart';

/// Backend API URL
const String _backendUrl = 'https://genedit.mooo.com';

/// Ad Unit IDs
class AdUnitIds {
  // Production ad unit ID for rewarded credits
  static const String rewardedCredit = 'ca-app-pub-3818647471101496/6049465577';
  
  // Production ad unit ID for native banner
  static const String nativeBanner = 'ca-app-pub-3818647471101496/7641231928';
  
  // Test ad unit IDs (use in debug mode)
  static const String testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String testNative = 'ca-app-pub-3940256099942544/2247696110';
  
  /// Get the appropriate ad unit ID based on build mode
  static String get rewarded {
    // Use test ads in debug mode to avoid policy violations
    return kDebugMode ? testRewarded : rewardedCredit;
  }
  
  /// Get the native ad unit ID based on build mode
  static String get native {
    return kDebugMode ? testNative : nativeBanner;
  }
}

/// Rewarded ad status from server
class RewardedAdStatus {
  final bool canWatch;
  final int creditsEarnedToday;
  final int dailyLimit;
  final int creditsPerAd;
  final DateTime? nextResetTime;
  final DateTime? cooldownEndsAt;  // When the ad cooldown expires
  final String? message;
  
  // New fields for "1 credit per 2 ads" system
  final int adsWatchedToday;  // Total ads watched today
  final int adsRequiredForCredit;  // How many ads needed for 1 credit (default: 2)

  RewardedAdStatus({
    required this.canWatch,
    required this.creditsEarnedToday,
    required this.dailyLimit,
    required this.creditsPerAd,
    this.nextResetTime,
    this.cooldownEndsAt,
    this.message,
    this.adsWatchedToday = 0,
    this.adsRequiredForCredit = 2,  // Default: 2 ads = 1 credit
  });

  factory RewardedAdStatus.fromJson(Map<String, dynamic> json) {
    return RewardedAdStatus(
      canWatch: json['can_watch'] ?? false,
      creditsEarnedToday: json['credits_earned_today'] ?? 0,
      dailyLimit: json['daily_limit'] ?? 30,
      creditsPerAd: json['credits_per_ad'] ?? 0,  // Now 0 since credits come every 2 ads
      nextResetTime: json['next_reset_time'] != null
          ? DateTime.tryParse(json['next_reset_time'])
          : null,
      cooldownEndsAt: json['cooldown_ends_at'] != null
          ? DateTime.tryParse(json['cooldown_ends_at'])
          : null,
      message: json['message'],
      adsWatchedToday: json['ads_watched_today'] ?? 0,
      adsRequiredForCredit: json['ads_required_for_credit'] ?? 2,
    );
  }

  /// Create default status for when server is unavailable
  factory RewardedAdStatus.defaultStatus() {
    return RewardedAdStatus(
      canWatch: true,
      creditsEarnedToday: 0,
      dailyLimit: 30,
      creditsPerAd: 0,  // Credits come every 2 ads, not per ad
      adsWatchedToday: 0,
      adsRequiredForCredit: 2,
    );
  }

  /// Calculate how many ads until next credit (0-2)
  int get adsUntilNextCredit {
    final remainder = adsWatchedToday % adsRequiredForCredit;
    return adsRequiredForCredit - remainder;
  }
  
  /// Progress toward next credit (0.0 to 1.0)
  double get progressToNextCredit {
    final remainder = adsWatchedToday % adsRequiredForCredit;
    return remainder / adsRequiredForCredit;
  }
  
  /// Check if next ad will grant a credit
  bool get willEarnCreditOnNextAd => adsUntilNextCredit == 1;
  
  int get remainingAdsToday => (dailyLimit - creditsEarnedToday).clamp(0, dailyLimit);
  bool get hasReachedLimit => creditsEarnedToday >= dailyLimit;
  
  /// Check if currently in cooldown period
  bool get isInCooldown {
    if (cooldownEndsAt == null) return false;
    return DateTime.now().isBefore(cooldownEndsAt!);
  }
  
  /// Get remaining cooldown duration
  Duration get remainingCooldown {
    if (cooldownEndsAt == null) return Duration.zero;
    final remaining = cooldownEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  /// Can actually watch an ad right now (not in cooldown and hasn't reached limit)
  bool get canWatchNow => canWatch && !isInCooldown && !hasReachedLimit;
}

/// Ad availability state for UI
enum AdAvailability {
  unknown,      // Not yet checked
  loading,      // Currently loading
  available,    // Ad is ready to show
  unavailable,  // No ad available (low fill rate)
  error,        // Failed to load
}

/// Service for managing rewarded ads with Server-Side Verification (SSV)
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  
  RewardedAd? _rewardedAd;
  bool _isLoadingAd = false;
  bool _isAdReady = false;
  
  /// Local cooldown tracking (prevents showing ads during cooldown)
  static const Duration _adCooldownDuration = Duration(seconds: 30);
  DateTime? _localCooldownEndsAt;
  
  /// Ad loading retry configuration
  static const int _maxRetryAttempts = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 2);
  int _currentRetryAttempt = 0;
  Timer? _retryTimer;
  
  /// Background pre-fetch timer
  Timer? _prefetchTimer;
  static const Duration _prefetchInterval = Duration(minutes: 2);
  
  /// Notifiers for UI updates
  final ValueNotifier<RewardedAdStatus?> statusNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isAdReadyNotifier = ValueNotifier(false);
  final ValueNotifier<DateTime?> cooldownNotifier = ValueNotifier(null);
  final ValueNotifier<AdAvailability> availabilityNotifier = ValueNotifier(AdAvailability.unknown);
  
  /// Initialize the Mobile Ads SDK
  /// Call this once at app startup
  static Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      debugPrint("✅ Mobile Ads SDK initialized");
    } catch (e) {
      debugPrint("❌ Failed to initialize Mobile Ads SDK: $e");
    }
  }

  /// Check if currently in local cooldown
  bool get isInCooldown {
    if (_localCooldownEndsAt == null) return false;
    return DateTime.now().isBefore(_localCooldownEndsAt!);
  }
  
  /// Get remaining cooldown duration
  Duration get remainingCooldown {
    if (_localCooldownEndsAt == null) return Duration.zero;
    final remaining = _localCooldownEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  /// Start the cooldown timer after watching an ad
  void _startCooldown() {
    _localCooldownEndsAt = DateTime.now().add(_adCooldownDuration);
    cooldownNotifier.value = _localCooldownEndsAt;
    debugPrint("⏳ Ad cooldown started, ends at: $_localCooldownEndsAt");
  }
  
  /// Clear cooldown (for testing or reset)
  void clearCooldown() {
    _localCooldownEndsAt = null;
    cooldownNotifier.value = null;
  }

  /// Check rewarded ad eligibility from server
  Future<RewardedAdStatus> checkEligibility() async {
    if (!_authService.isSignedIn) {
      return RewardedAdStatus(
        canWatch: false,
        creditsEarnedToday: 0,
        dailyLimit: 30,
        creditsPerAd: 1,
        message: 'Sign in to watch ads',
      );
    }

    try {
      final token = await _authService.getIdToken();
      if (token == null) {
        return RewardedAdStatus.defaultStatus();
      }

      final response = await http.get(
        Uri.parse('$_backendUrl/ads/rewarded/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        var status = RewardedAdStatus.fromJson(data);
        
        // Get local ad count (always track locally for accurate progress display)
        final localAdsWatched = await _getLocalAdsWatchedToday();
        
        // Use local ads_watched_today if server doesn't provide it (or returns 0)
        final effectiveAdsWatched = status.adsWatchedToday > 0 
            ? status.adsWatchedToday 
            : localAdsWatched;
        
        // Merge local tracking with server status
        final effectiveCooldown = isInCooldown && 
            (status.cooldownEndsAt == null || _localCooldownEndsAt!.isAfter(status.cooldownEndsAt!))
            ? _localCooldownEndsAt
            : status.cooldownEndsAt;
        
        status = RewardedAdStatus(
          canWatch: status.canWatch,
          creditsEarnedToday: status.creditsEarnedToday,
          dailyLimit: status.dailyLimit,
          creditsPerAd: status.creditsPerAd,
          nextResetTime: status.nextResetTime,
          cooldownEndsAt: effectiveCooldown,
          message: status.message,
          adsWatchedToday: effectiveAdsWatched,
          adsRequiredForCredit: status.adsRequiredForCredit,
        );
        
        statusNotifier.value = status;
        cooldownNotifier.value = status.cooldownEndsAt;
        return status;
      } else {
        debugPrint("⚠️ Ad status check failed: ${response.statusCode}");
        // Return local status if server unavailable
        return await _getLocalStatus();
      }
    } catch (e) {
      debugPrint("⚠️ Ad status check error: $e - using local status");
      return await _getLocalStatus();
    }
  }

  /// Get local ad status (fallback when server unavailable)
  Future<RewardedAdStatus> _getLocalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we need to reset (new day)
    final lastResetStr = prefs.getString('ad_last_reset');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    if (lastResetStr != today) {
      // New day - reset counter
      await prefs.setInt('ads_watched_today', 0);
      await prefs.setString('ad_last_reset', today);
    }
    
    final adsWatched = prefs.getInt('ads_watched_today') ?? 0;
    const dailyLimit = 30;  // Max credits per day
    const adsRequiredForCredit = 2;  // 2 ads = 1 credit
    
    // Calculate credits earned: 1 credit per 2 ads
    final creditsEarned = adsWatched ~/ adsRequiredForCredit;
    
    final status = RewardedAdStatus(
      canWatch: creditsEarned < dailyLimit,
      creditsEarnedToday: creditsEarned,
      dailyLimit: dailyLimit,
      creditsPerAd: 0,  // Credits come every 2 ads, not per ad
      nextResetTime: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day + 1,
      ),
      cooldownEndsAt: _localCooldownEndsAt,
      adsWatchedToday: adsWatched,
      adsRequiredForCredit: adsRequiredForCredit,
    );
    
    statusNotifier.value = status;
    return status;
  }

  /// Start background pre-fetching of ads
  /// Call this when user is likely to want to watch ads soon
  void startPrefetching() {
    _prefetchTimer?.cancel();
    
    // Load immediately if not ready
    if (!_isAdReady && !_isLoadingAd) {
      loadRewardedAd();
    }
    
    // Set up periodic refresh to keep ads ready
    _prefetchTimer = Timer.periodic(_prefetchInterval, (_) {
      if (!_isAdReady && !_isLoadingAd && !isInCooldown) {
        debugPrint("🔄 Background ad prefetch triggered");
        loadRewardedAd();
      }
    });
  }
  
  /// Stop background pre-fetching
  void stopPrefetching() {
    _prefetchTimer?.cancel();
    _prefetchTimer = null;
  }
  
  /// Load a rewarded ad with automatic retry on failure
  /// 
  /// SSV Configuration:
  /// - Configure SSV callback URL in AdMob Console: https://YOUR_SERVER/ads/admob/ssv
  /// - The custom_data parameter contains the user's Firebase UID
  /// - Server receives callback from Google when ad is watched and grants credits
  Future<void> loadRewardedAd({bool isRetry = false}) async {
    if (_isLoadingAd || _isAdReady) return;
    
    // Get current user's Firebase UID for SSV
    final firebaseUid = _authService.currentUser?.uid;
    if (firebaseUid == null) {
      debugPrint("⚠️ Cannot load rewarded ad: User not logged in");
      return;
    }
    
    // Reset retry count if this is a fresh load (not a retry)
    if (!isRetry) {
      _currentRetryAttempt = 0;
      _retryTimer?.cancel();
    }
    
    _isLoadingAd = true;
    isLoadingNotifier.value = true;
    availabilityNotifier.value = AdAvailability.loading;
    
    debugPrint("📱 Loading rewarded ad with SSV customData: $firebaseUid");
    
    try {
      await RewardedAd.load(
        adUnitId: AdUnitIds.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) async {
            debugPrint("✅ Rewarded ad loaded (attempt ${_currentRetryAttempt + 1})");
            
            // Set Server-Side Verification options with Firebase UID
            await ad.setServerSideOptions(
              ServerSideVerificationOptions(customData: firebaseUid),
            );
            debugPrint("✅ SSV options set with customData: $firebaseUid");
            
            _rewardedAd = ad;
            _isAdReady = true;
            _isLoadingAd = false;
            _currentRetryAttempt = 0; // Reset on success
            isAdReadyNotifier.value = true;
            isLoadingNotifier.value = false;
            availabilityNotifier.value = AdAvailability.available;
            
            // Set up ad event callbacks
            _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (Ad ad) {
                debugPrint("📱 Ad dismissed");
                ad.dispose();
                _rewardedAd = null;
                _isAdReady = false;
                isAdReadyNotifier.value = false;
                availabilityNotifier.value = AdAvailability.unknown;
                // Preload next ad after cooldown
                Future.delayed(const Duration(seconds: 5), () {
                  if (!isInCooldown) loadRewardedAd();
                });
              },
              onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
                debugPrint("❌ Ad failed to show: ${error.message}");
                ad.dispose();
                _rewardedAd = null;
                _isAdReady = false;
                isAdReadyNotifier.value = false;
                availabilityNotifier.value = AdAvailability.error;
                // Try to load another ad
                _scheduleRetry();
              },
            );
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint("❌ Rewarded ad failed to load (attempt ${_currentRetryAttempt + 1}): ${error.message}");
            _isLoadingAd = false;
            _isAdReady = false;
            isLoadingNotifier.value = false;
            isAdReadyNotifier.value = false;
            
            // Check if we should retry
            if (_currentRetryAttempt < _maxRetryAttempts) {
              availabilityNotifier.value = AdAvailability.loading; // Still trying
              _scheduleRetry();
            } else {
              // All retries exhausted - no ad available
              debugPrint("⚠️ All retry attempts exhausted - no ad available");
              availabilityNotifier.value = AdAvailability.unavailable;
              _currentRetryAttempt = 0;
              
              // Schedule another attempt in a few minutes
              _retryTimer = Timer(const Duration(minutes: 5), () {
                if (!_isAdReady && !_isLoadingAd) {
                  debugPrint("🔄 Attempting to load ad again after cooloff period");
                  loadRewardedAd();
                }
              });
            }
          },
        ),
      );
    } catch (e) {
      debugPrint("❌ Error loading rewarded ad: $e");
      _isLoadingAd = false;
      isLoadingNotifier.value = false;
      availabilityNotifier.value = AdAvailability.error;
      _scheduleRetry();
    }
  }
  
  /// Schedule a retry with exponential backoff
  void _scheduleRetry() {
    _currentRetryAttempt++;
    
    if (_currentRetryAttempt > _maxRetryAttempts) return;
    
    // Exponential backoff: 2s, 4s, 8s
    final delay = _initialRetryDelay * (1 << (_currentRetryAttempt - 1));
    debugPrint("⏳ Scheduling ad load retry #$_currentRetryAttempt in ${delay.inSeconds}s");
    
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      loadRewardedAd(isRetry: true);
    });
  }
  
  /// Force refresh - cancel current ad and try loading a new one
  Future<void> forceRefreshAd() async {
    _retryTimer?.cancel();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    _isLoadingAd = false;
    _currentRetryAttempt = 0;
    isAdReadyNotifier.value = false;
    availabilityNotifier.value = AdAvailability.unknown;
    
    await loadRewardedAd();
  }

  /// Show rewarded ad with SSV (Server-Side Verification)
  /// 
  /// SSV Flow:
  /// 1. User watches ad → AdMob SDK notifies Google
  /// 2. Google calls server at /ads/admob/ssv with firebase_uid in custom_data
  /// 3. Server verifies signature and grants credits
  /// 4. App polls for updated balance
  /// 
  /// Returns the number of credits earned (from status), or null if ad was not completed
  /// Returns -1 if user is in cooldown (should check isInCooldown before calling)
  Future<int?> showRewardedAd() async {
    if (_rewardedAd == null) {
      debugPrint("⚠️ No ad loaded");
      return null;
    }

    // Check if user is authenticated
    if (!_authService.isSignedIn) {
      debugPrint("⚠️ User not authenticated");
      return null;
    }
    
    // ⚠️ IMPORTANT: Check cooldown BEFORE showing ad to prevent wasted ad views
    if (isInCooldown) {
      debugPrint("⏳ User is in cooldown, cannot show ad. Remaining: ${remainingCooldown.inSeconds}s");
      return -1;  // Return -1 to indicate cooldown (don't show ad)
    }

    // Get credits before watching to calculate difference
    final creditsBefore = await _userService.refreshCredits();
    final completer = Completer<int?>();
    
    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
          debugPrint("🎉 User earned reward: ${reward.amount} ${reward.type}");
          debugPrint("⏳ Waiting for SSV to process...");
          
          // ✅ Start cooldown immediately after ad completion
          _startCooldown();
          
          // SSV: Google will call our server webhook automatically
          // Wait a bit for SSV callback to be processed by server
          await Future.delayed(const Duration(seconds: 2));
          
          // Poll for updated balance (retry a few times if needed)
          int creditsAfter = creditsBefore;
          for (int attempt = 0; attempt < 3; attempt++) {
            creditsAfter = await _userService.refreshCredits();
            if (creditsAfter > creditsBefore) {
              break; // Credits updated
            }
            await Future.delayed(const Duration(seconds: 1));
          }
          
          // Calculate credits earned (server grants 1 credit per 2 ads)
          int creditsEarned = (creditsAfter - creditsBefore).clamp(0, 10);
          // Note: creditsEarned may be 0 if this is the 1st ad (need 2 ads for 1 credit)
          
          debugPrint("✅ SSV processed - earned $creditsEarned credits (may be 0 if this is 1st of 2 ads)");
          
          // Update local tracking and eligibility status
          await _incrementLocalAdCount();
          await checkEligibility();
          
          // Return actual credits earned (0 or 1, depending on if this was the 2nd ad)
          completer.complete(creditsEarned);
        },
      );
    } catch (e) {
      debugPrint("❌ Error showing ad: $e");
      completer.complete(null);
    }

    return completer.future;
  }

  /// Increment local ad count (for UI display when server unavailable)
  Future<void> _incrementLocalAdCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Check if we need to reset
    final lastReset = prefs.getString('ad_last_reset');
    if (lastReset != today) {
      await prefs.setInt('ads_watched_today', 1);
      await prefs.setString('ad_last_reset', today);
    } else {
      final current = prefs.getInt('ads_watched_today') ?? 0;
      await prefs.setInt('ads_watched_today', current + 1);
    }
    debugPrint("📊 Local ads watched today: ${prefs.getInt('ads_watched_today')}");
  }
  
  /// Get local ads watched count for today
  Future<int> _getLocalAdsWatchedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Check if we need to reset (new day)
    final lastReset = prefs.getString('ad_last_reset');
    if (lastReset != today) {
      return 0;
    }
    
    return prefs.getInt('ads_watched_today') ?? 0;
  }

  /// Show a rewarded ad for gating features (like export)
  /// No server call needed - just waits for ad completion
  /// Returns true if user completed watching the ad, false otherwise
  Future<bool> showAdForFeatureGate() async {
    if (_rewardedAd == null) {
      debugPrint("⚠️ No ad loaded for feature gate");
      // Try to load one quickly
      await loadRewardedAd();
      // Wait a bit for it to load
      for (int i = 0; i < 10; i++) {
        if (_rewardedAd != null) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (_rewardedAd == null) return false;
    }

    final completer = Completer<bool>();
    bool hasCompleted = false;
    
    // Set up callbacks for ad lifecycle
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (Ad ad) {
        debugPrint("📺 Feature gate ad dismissed");
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        isAdReadyNotifier.value = false;
        
        // Preload next ad for future use
        loadRewardedAd();
        
        if (!hasCompleted) {
          hasCompleted = true;
          completer.complete(true); // User watched the ad
        }
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        debugPrint("❌ Feature gate ad failed to show: ${error.message}");
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        isAdReadyNotifier.value = false;
        
        if (!hasCompleted) {
          hasCompleted = true;
          completer.complete(false);
        }
      },
    );
    
    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint("🎉 Feature gate ad reward earned");
          // Note: completion is handled in onAdDismissedFullScreenContent
        },
      );
    } catch (e) {
      debugPrint("❌ Feature gate ad error: $e");
      if (!hasCompleted) {
        hasCompleted = true;
        completer.complete(false);
      }
    }

    return completer.future;
  }

  /// Dispose of loaded ads
  void dispose() {
    _retryTimer?.cancel();
    _prefetchTimer?.cancel();
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    isAdReadyNotifier.value = false;
    availabilityNotifier.value = AdAvailability.unknown;
  }
}

