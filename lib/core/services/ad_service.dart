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
  final String? message;

  RewardedAdStatus({
    required this.canWatch,
    required this.creditsEarnedToday,
    required this.dailyLimit,
    required this.creditsPerAd,
    this.nextResetTime,
    this.message,
  });

  factory RewardedAdStatus.fromJson(Map<String, dynamic> json) {
    return RewardedAdStatus(
      canWatch: json['can_watch'] ?? false,
      creditsEarnedToday: json['credits_earned_today'] ?? 0,
      dailyLimit: json['daily_limit'] ?? 30,
      creditsPerAd: json['credits_per_ad'] ?? 1,
      nextResetTime: json['next_reset_time'] != null
          ? DateTime.tryParse(json['next_reset_time'])
          : null,
      message: json['message'],
    );
  }

  /// Create default status for when server is unavailable
  factory RewardedAdStatus.defaultStatus() {
    return RewardedAdStatus(
      canWatch: true,
      creditsEarnedToday: 0,
      dailyLimit: 30,
      creditsPerAd: 1,
    );
  }

  int get remainingAdsToday => (dailyLimit - creditsEarnedToday).clamp(0, dailyLimit);
  bool get hasReachedLimit => creditsEarnedToday >= dailyLimit;
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
  
  /// Notifiers for UI updates
  final ValueNotifier<RewardedAdStatus?> statusNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isAdReadyNotifier = ValueNotifier(false);
  
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
        final status = RewardedAdStatus.fromJson(data);
        statusNotifier.value = status;
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
    const dailyLimit = 30;
    const creditsPerAd = 1;
    
    final status = RewardedAdStatus(
      canWatch: adsWatched < dailyLimit,
      creditsEarnedToday: adsWatched * creditsPerAd,
      dailyLimit: dailyLimit,
      creditsPerAd: creditsPerAd,
      nextResetTime: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day + 1,
      ),
    );
    
    statusNotifier.value = status;
    return status;
  }

  /// Load a rewarded ad
  Future<void> loadRewardedAd() async {
    if (_isLoadingAd || _isAdReady) return;
    
    _isLoadingAd = true;
    isLoadingNotifier.value = true;
    
    try {
      await RewardedAd.load(
        adUnitId: AdUnitIds.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            debugPrint("✅ Rewarded ad loaded");
            _rewardedAd = ad;
            _isAdReady = true;
            _isLoadingAd = false;
            isAdReadyNotifier.value = true;
            isLoadingNotifier.value = false;
            
            // Set up ad event callbacks
            _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (Ad ad) {
                debugPrint("📱 Ad dismissed");
                ad.dispose();
                _rewardedAd = null;
                _isAdReady = false;
                isAdReadyNotifier.value = false;
                // Preload next ad
                loadRewardedAd();
              },
              onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
                debugPrint("❌ Ad failed to show: ${error.message}");
                ad.dispose();
                _rewardedAd = null;
                _isAdReady = false;
                isAdReadyNotifier.value = false;
              },
            );
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint("❌ Rewarded ad failed to load: ${error.message}");
            _isLoadingAd = false;
            _isAdReady = false;
            isLoadingNotifier.value = false;
            isAdReadyNotifier.value = false;
          },
        ),
      );
    } catch (e) {
      debugPrint("❌ Error loading rewarded ad: $e");
      _isLoadingAd = false;
      isLoadingNotifier.value = false;
    }
  }

  /// Show rewarded ad with SSV (Server-Side Verification)
  /// Returns the number of credits earned, or null if ad was not completed
  /// Returns -1 if rate limited (user should wait before watching another ad)
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

    final completer = Completer<int?>();
    
    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
          debugPrint("🎉 User earned reward: ${reward.amount} ${reward.type}");
          
          // Complete the reward via API since SSV requires backend webhook setup
          // The backend will verify and grant credits
          final result = await completeRewardViaApi();
          
          if (result != null && result > 0) {
            // Success - return actual credits from server (not AdMob reward amount)
            await _incrementLocalAdCount();
            await checkEligibility();
            completer.complete(result);
          } else if (result == -1) {
            // Rate limited - return -1 to indicate user should wait
            await checkEligibility();
            completer.complete(-1);
          } else {
            // Failed but ad was watched - refresh credits anyway
            await Future.delayed(const Duration(seconds: 1));
            await _userService.refreshCredits();
            await checkEligibility();
            completer.complete(null);
          }
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
  }

  /// Fallback: Complete ad reward via API (use if SSV is not configured)
  /// Returns the number of credits earned, null on failure, or -1 if rate limited
  Future<int?> completeRewardViaApi() async {
    if (!_authService.isSignedIn) return null;

    try {
      final token = await _authService.getIdToken();
      if (token == null) return null;

      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id') ?? '';

      final response = await http.post(
        Uri.parse('$_backendUrl/ads/rewarded/complete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final creditsAdded = (data['credits_added'] as num?)?.toInt() ?? 1;
        debugPrint("✅ Ad reward completed via API: $creditsAdded credits");
        await _userService.refreshCredits();
        return creditsAdded;
      } else if (response.statusCode == 429) {
        // Rate limited - user is watching ads too quickly
        debugPrint("⚠️ Ad reward rate limited (429) - user should wait");
        return -1;
      } else {
        debugPrint("❌ Ad reward API failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Ad reward API error: $e");
      return null;
    }
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
    
    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint("🎉 Feature gate ad completed");
          completer.complete(true);
        },
      );
    } catch (e) {
      debugPrint("❌ Feature gate ad error: $e");
      completer.complete(false);
    }

    return completer.future;
  }

  /// Dispose of loaded ads
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    isAdReadyNotifier.value = false;
  }
}

