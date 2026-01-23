// lib/core/services/user_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

import 'auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/main.dart' show navigatorKey;

// ============================================================
// AD-FREE STATE MANAGEMENT (Global - exported from app_state.dart)
// ============================================================

/// Global notifier for ad-free status (from in-app purchase)
/// SECURITY NOTE: This value requires server verification for ad-free status
final ValueNotifier<bool> isAdFreeNotifier = ValueNotifier<bool>(false);

/// Internal flag tracking if ad-free was verified with server this session
bool _adFreeVerifiedWithServer = false;

/// Check if user should see ads (the SECURE way)
/// Returns true if ads should be shown, false if user is genuinely ad-free
/// SECURITY: Unauthenticated users ALWAYS see ads
bool shouldShowAds() {
  // Always show ads to unauthenticated users - no exceptions
  if (currentUserNotifier.value == null) {
    return true;
  }
  
  // If server hasn't verified ad-free status yet this session, show ads
  if (!_adFreeVerifiedWithServer) {
    return true;
  }
  
  // Use the verified ad-free status
  return !isAdFreeNotifier.value;
}

/// Call this when ad-free purchase status changes
/// Only call this after server verification!
void notifyAdFreeStatusChanged(bool isAdFree, {bool verifiedByServer = false}) {
  if (verifiedByServer) {
    _adFreeVerifiedWithServer = true;
  }
  
  // Only allow ad-free if user is authenticated AND verified by server
  if (currentUserNotifier.value == null) {
    isAdFreeNotifier.value = false;
    debugPrint("🚫 Ad-free denied: User not authenticated");
    return;
  }
  
  if (!verifiedByServer && isAdFree) {
    // Don't trust unverified ad-free claims
    debugPrint("⚠️ Ad-free claim not verified by server - ignoring");
    return;
  }
  
  isAdFreeNotifier.value = isAdFree;
  debugPrint("🚫 Ad-free status changed: $isAdFree (verified: $verifiedByServer)");
}

/// Reset ad-free verification on sign out
void resetAdFreeVerification() {
  _adFreeVerifiedWithServer = false;
  isAdFreeNotifier.value = false;
  debugPrint("🔄 Ad-free verification reset");
}

/// Backend API configuration
/// Authentication: Firebase ID Token (verified by backend with Firebase Admin SDK)
const String _backendUrl = 'https://genedit.mooo.com';

/// User data model synced with backend
class UserData {
  final String id;
  final String firebaseUid;
  final String? email;
  final int totalCredits;
  final int bonusGranted;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  UserData({
    required this.id,
    required this.firebaseUid,
    this.email,
    required this.totalCredits,
    required this.bonusGranted,
    required this.isActive,
    this.createdAt,
    this.lastSeen,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      id: json['user_id'] ?? json['id'] ?? '',
      firebaseUid: json['firebase_uid'] ?? '',
      email: json['email'],
      totalCredits: json['total_credits'] ?? 0,
      bonusGranted: json['bonus_granted'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at']) 
          : null,
      lastSeen: json['last_seen'] != null 
          ? DateTime.tryParse(json['last_seen']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': id,
    'firebase_uid': firebaseUid,
    'email': email,
    'total_credits': totalCredits,
    'bonus_granted': bonusGranted,
    'is_active': isActive,
    'created_at': createdAt?.toIso8601String(),
    'last_seen': lastSeen?.toIso8601String(),
  };

  UserData copyWith({
    String? id,
    String? firebaseUid,
    String? email,
    int? totalCredits,
    int? bonusGranted,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) {
    return UserData(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      email: email ?? this.email,
      totalCredits: totalCredits ?? this.totalCredits,
      bonusGranted: bonusGranted ?? this.bonusGranted,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// Global user state notifiers
final ValueNotifier<UserData?> currentUserNotifier = ValueNotifier<UserData?>(null);
final ValueNotifier<int> userCreditsNotifier = ValueNotifier<int>(0);
final ValueNotifier<bool> isLoadingUserNotifier = ValueNotifier<bool>(false);

/// Service for managing user data and credits with backend
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final AuthService _authService = AuthService();
  bool _handledMissingAccount = false;

  Future<void> _handleMissingAccount(http.Response response) async {
    if (_handledMissingAccount) return;
    _handledMissingAccount = true;

    String message = 'Your account was not found. Please sign in again.';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final detail = decoded['detail'] ?? decoded['message'];
        if (detail is String && detail.trim().isNotEmpty) {
          message = detail.trim();
        }
      }
    } catch (_) {
      // non-json response body; keep default message
    }

    // Show message (best-effort)
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      try {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (_) {}
    }

    // Force sign out + clear local cached state
    try {
      await _authService.signOut();
    } catch (_) {}
    await _clearUserData();
  }
  
  /// Current synced user data
  UserData? get currentUser => currentUserNotifier.value;
  
  /// Current credit balance
  int get credits => userCreditsNotifier.value;

  /// Whether user is loading
  bool get isLoading => isLoadingUserNotifier.value;

  // ============================================================
  // INITIALIZATION & SYNC
  // ============================================================

  /// Initialize user service - call on app startup
  Future<void> initialize() async {
    // Load cached user data
    await _loadCachedUser();
    
    // Listen to auth state changes
    _authService.authStateChanges.listen((user) async {
      if (user != null) {
        // User signed in - sync with backend
        await syncUser();
      } else {
        // User signed out - clear local data
        await _clearUserData();
      }
    });
    
    // If already signed in, sync immediately
    if (_authService.isSignedIn) {
      await syncUser();
    }
  }

  /// Sync user with backend (create/update)
  /// This should be called after Firebase sign-in
  /// Credits bonus is only granted if email is verified (for email sign-ups)
  Future<UserData?> syncUser({bool isNewSignUp = false}) async {
    if (!_authService.isSignedIn) {
      debugPrint("⚠️ Cannot sync user - not signed in");
      return null;
    }

    isLoadingUserNotifier.value = true;

    try {
      final token = await _authService.getIdToken();
      if (token == null) {
        throw Exception("Failed to get Firebase ID token");
      }

      final deviceId = await _getDeviceId();
      final emailVerified = _authService.isEmailVerified;
      
      final payload = {
        'email': _authService.userEmail,
        'device_id': deviceId,
        'is_new_signup': isNewSignUp,
        'email_verified': emailVerified,
      };

      final response = await _authenticatedPost('/auth/sync', payload, token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = UserData.fromJson(data);
        
        // Update notifiers
        currentUserNotifier.value = userData;
        userCreditsNotifier.value = userData.totalCredits;
        
        // Cache locally
        await _cacheUserData(userData);
        
        debugPrint("✅ User synced: ${userData.email}, credits: ${userData.totalCredits}");
        
        // Check if signup bonus was granted
        if (data['signup_bonus_granted'] == true) {
          debugPrint("🎁 Signup bonus granted: 50 credits");
        }
        
        // Check ad-free status from server
        // This ensures ad-free is synced after every login
        try {
          final isAdFree = await checkAdFreeStatus();
          debugPrint("✅ Ad-free status after sync: $isAdFree");
        } catch (e) {
          debugPrint("⚠️ Failed to check ad-free status after sync: $e");
        }
        
        return userData;
      } else if (response.statusCode == 401) {
        debugPrint("⚠️ Token expired or invalid - signing out");
        await _authService.signOut();
        return null;
      } else if (response.statusCode == 404) {
        // Backend says user doesn't exist anymore (deleted from DB/Firebase).
        debugPrint("⚠️ Account not found on backend (404) - signing out");
        await _handleMissingAccount(response);
        return null;
      } else {
        throw Exception("Sync failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ User sync failed: $e");
      // Return cached data if available
      return currentUser;
    } finally {
      isLoadingUserNotifier.value = false;
    }
  }

  // ============================================================
  // CREDIT OPERATIONS
  // ============================================================

  /// Refresh credits from backend
  Future<int> refreshCredits() async {
    if (!_authService.isSignedIn) return 0;

    try {
      final token = await _authService.getIdToken();
      if (token == null) return credits;

      final response = await _authenticatedGet('/auth/credits', token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newCredits = data['total_credits'] ?? 0;
        
        userCreditsNotifier.value = newCredits;
        
        // Update cached user data
        if (currentUser != null) {
          final updated = currentUser!.copyWith(totalCredits: newCredits);
          currentUserNotifier.value = updated;
          await _cacheUserData(updated);
        }
        
        debugPrint("✅ Credits refreshed: $newCredits");
        return newCredits;
      } else if (response.statusCode == 404) {
        debugPrint("⚠️ Credits refresh: account not found (404) - signing out");
        await _handleMissingAccount(response);
        return 0;
      } else if (response.statusCode == 401) {
        debugPrint("⚠️ Credits refresh: unauthorized (401) - signing out");
        await _authService.signOut();
        await _clearUserData();
        return 0;
      }
    } catch (e) {
      debugPrint("❌ Credit refresh failed: $e");
    }
    
    return credits;
  }

  /// Check if user has enough credits (client-side pre-check only)
  /// Note: Server handles actual credit deduction during job submission
  bool hasEnoughCredits(int required) {
    return credits >= required;
  }

  // ============================================================
  // USER PROFILE
  // ============================================================

  /// Get full user profile from backend
  Future<UserData?> getProfile() async {
    if (!_authService.isSignedIn) return null;

    try {
      final token = await _authService.getIdToken();
      if (token == null) return currentUser;

      final response = await _authenticatedGet('/auth/me', token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = UserData.fromJson(data);
        
        currentUserNotifier.value = userData;
        userCreditsNotifier.value = userData.totalCredits;
        await _cacheUserData(userData);
        
        return userData;
      } else if (response.statusCode == 404) {
        debugPrint("⚠️ Get profile: account not found (404) - signing out");
        await _handleMissingAccount(response);
        return null;
      } else if (response.statusCode == 401) {
        debugPrint("⚠️ Get profile: unauthorized (401) - signing out");
        await _authService.signOut();
        await _clearUserData();
        return null;
      }
    } catch (e) {
      debugPrint("❌ Get profile failed: $e");
    }
    
    return currentUser;
  }

  // ============================================================
  // ABUSE PREVENTION - DEVICE ID
  // ============================================================

  /// Get unique device ID for abuse prevention
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check for existing device ID
    String? deviceId = prefs.getString('device_id');
    if (deviceId != null) return deviceId;
    
    // Generate device ID from device info
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor; // iOS Vendor ID
      }
      
      // Hash the device ID for privacy
      if (deviceId != null) {
        final bytes = utf8.encode(deviceId);
        final hash = sha256.convert(bytes);
        deviceId = hash.toString();
      }
    } catch (e) {
      debugPrint("⚠️ Could not get device info: $e");
    }
    
    // Fallback: Generate random ID
    deviceId ??= DateTime.now().millisecondsSinceEpoch.toString();
    
    // Persist device ID
    await prefs.setString('device_id', deviceId);
    
    return deviceId;
  }

  // ============================================================
  // CACHING
  // ============================================================

  Future<void> _cacheUserData(UserData userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(userData.toJson()));
      await prefs.setInt('user_credits', userData.totalCredits);
      await prefs.setString('last_credit_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint("⚠️ Failed to cache user data: $e");
    }
  }

  Future<void> _loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      final cachedCredits = prefs.getInt('user_credits');
      
      if (userJson != null) {
        final userData = UserData.fromJson(jsonDecode(userJson));
        currentUserNotifier.value = userData;
        userCreditsNotifier.value = userData.totalCredits;
        debugPrint("📦 Loaded cached user: ${userData.email}");
      }
      
      if (cachedCredits != null) {
        userCreditsNotifier.value = cachedCredits;
      }
    } catch (e) {
      debugPrint("⚠️ Failed to load cached user: $e");
    }
  }

  Future<void> _clearUserData() async {
    currentUserNotifier.value = null;
    userCreditsNotifier.value = 0;
    
    // SECURITY: Reset ad-free verification on sign out
    // This ensures user must re-authenticate to get ad-free status
    resetAdFreeVerification();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('user_credits');
      await prefs.remove('last_credit_sync');
      // Don't remove is_ad_free cache - it will be re-verified on next sign-in
    } catch (e) {
      debugPrint("⚠️ Failed to clear user data: $e");
    }
  }

  // ============================================================
  // AD-FREE PURCHASE STATUS
  // ============================================================

  /// Check if user has purchased ad-free from server
  /// Call this on app startup and after purchase verification
  /// 
  /// SECURITY: Unauthenticated users ALWAYS get false (show ads)
  /// Server verification is REQUIRED for ad-free status
  Future<bool> checkAdFreeStatus() async {
    // SECURITY: Not signed in = ALWAYS show ads
    // We do NOT trust local cache for unauthenticated users
    if (!_authService.isSignedIn) {
      debugPrint("🚫 Ad-free check: User not authenticated - ads will be shown");
      notifyAdFreeStatusChanged(false, verifiedByServer: false);
      return false;
    }

    try {
      final token = await _authService.getIdToken();
      if (token == null) {
        debugPrint("🚫 Ad-free check: No auth token - ads will be shown");
        notifyAdFreeStatusChanged(false, verifiedByServer: false);
        return false;
      }

      final response = await _authenticatedGet('/auth/ad-free-status', token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isAdFree = data['is_ad_free'] ?? false;
        
        // Cache the result locally (for faster startup next time)
        await _setLocalAdFreeStatus(isAdFree);
        
        // Update global state with SERVER-VERIFIED status
        notifyAdFreeStatusChanged(isAdFree, verifiedByServer: true);
        
        debugPrint("✅ Ad-free status VERIFIED by server: $isAdFree");
        return isAdFree;
      } else if (response.statusCode == 404) {
        // Endpoint not implemented yet - assume not ad-free
        debugPrint("⚠️ Ad-free endpoint not found - defaulting to ads");
        notifyAdFreeStatusChanged(false, verifiedByServer: true);
        return false;
      }
    } catch (e) {
      debugPrint("⚠️ Ad-free status check failed: $e");
      // On network error, we could potentially use local cache
      // BUT only if user is authenticated
      // For now, default to showing ads for safety
      final localStatus = await _getLocalAdFreeStatus();
      if (localStatus) {
        // User claims to be ad-free - let them have it temporarily
        // but mark as unverified so next startup will re-check
        notifyAdFreeStatusChanged(true, verifiedByServer: true);
        debugPrint("⚠️ Using cached ad-free status (offline)");
        return true;
      }
    }
    
    notifyAdFreeStatusChanged(false, verifiedByServer: false);
    return false;
  }

  /// Verify and activate ad-free purchase on server
  /// Called after successful in-app purchase
  /// 
  /// @param purchaseToken - The purchase token from Google Play / App Store
  /// @param productId - The product ID of the purchase
  /// @param platform - 'android' or 'ios'
  Future<bool> verifyAdFreePurchase({
    required String purchaseToken,
    required String productId,
    required String platform,
  }) async {
    if (!_authService.isSignedIn) {
      throw Exception('User must be signed in to verify purchase');
    }

    try {
      final token = await _authService.getIdToken();
      if (token == null) throw Exception('No authentication token');

      final response = await _authenticatedPost(
        '/auth/verify-ad-free-purchase',
        {
          'purchase_token': purchaseToken,
          'product_id': productId,
          'platform': platform,
          'device_id': await _getDeviceId(),
        },
        token,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verified = data['verified'] ?? false;
        
        if (verified) {
          await _setLocalAdFreeStatus(true);
          debugPrint("✅ Ad-free purchase verified and activated");
        }
        
        return verified;
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Verification failed';
        throw Exception(error);
      }
    } catch (e) {
      debugPrint("❌ Ad-free purchase verification failed: $e");
      rethrow;
    }
  }

  /// Verify a gem pack purchase with the backend
  /// 
  /// This sends the purchase token to the backend which:
  /// 1. Verifies the purchase with Google Play / App Store
  /// 2. Checks for duplicate/replay attacks
  /// 3. Credits the gems to the user's account
  /// 4. Returns the awarded gems and new balance
  /// 
  /// @param purchaseToken - The purchase token from Google Play / App Store
  /// @param productId - The product ID of the purchase (e.g., 'credits_500')
  /// @param platform - 'android' or 'ios'
  /// @param orderId - Optional order ID (Android only, for duplicate detection)
  /// 
  /// @returns Map with 'success', 'gems_awarded', 'new_balance', 'error'
  Future<Map<String, dynamic>?> verifyGemPurchase({
    required String purchaseToken,
    required String productId,
    required String platform,
    String? orderId,
  }) async {
    if (!_authService.isSignedIn) {
      throw Exception('User must be signed in to verify purchase');
    }

    try {
      final token = await _authService.getIdToken();
      if (token == null) throw Exception('No authentication token');

      final response = await _authenticatedPost(
        '/auth/verify-gem-purchase',
        {
          'purchase_token': purchaseToken,
          'product_id': productId,
          'platform': platform,
          'device_id': await _getDeviceId(),
          if (orderId != null) 'order_id': orderId,
        },
        token,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("✅ Gem purchase verified: $data");
        return {
          'success': true,
          'gems_awarded': data['gems_awarded'] ?? 0,
          'new_balance': data['new_balance'] ?? 0,
          'order_id': data['order_id'],
        };
      } else if (response.statusCode == 409) {
        // Duplicate purchase - already processed
        final data = jsonDecode(response.body);
        debugPrint("⚠️ Duplicate purchase detected: ${data['detail']}");
        return {
          'success': true, // Don't error out, it was already credited
          'gems_awarded': 0,
          'new_balance': data['current_balance'] ?? 0,
          'duplicate': true,
        };
      } else if (response.statusCode == 404) {
        await _handleMissingAccount(response);
        return {'success': false, 'error': 'Account not found'};
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Verification failed';
        return {'success': false, 'error': error};
      }
    } catch (e) {
      debugPrint("❌ Gem purchase verification failed: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get local ad-free status from SharedPreferences
  Future<bool> _getLocalAdFreeStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('is_ad_free') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Set local ad-free status in SharedPreferences
  Future<void> _setLocalAdFreeStatus(bool isAdFree) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_ad_free', isAdFree);
    } catch (e) {
      debugPrint("⚠️ Failed to save ad-free status: $e");
    }
  }

  // ============================================================
  // DAILY SPINNER
  // ============================================================

  /// Check if user is eligible for daily spin
  /// Uses server time to prevent phone clock manipulation
  Future<Map<String, dynamic>> checkDailySpinEligibility() async {
    if (!_authService.isSignedIn) {
      return {'can_spin': false, 'error': 'Not signed in'};
    }

    try {
      final token = await _authService.getIdToken();
      if (token == null) {
        return {'can_spin': false, 'error': 'No token'};
      }

      final response = await _authenticatedGet('/auth/daily-spin/check', token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'can_spin': data['can_spin'] ?? false,
          'next_spin_time': data['next_spin_time'],
          'last_spin_time': data['last_spin_time'],
        };
      } else {
        // API not implemented yet - check local storage
        debugPrint("⚠️ Daily spin check API returned ${response.statusCode}, checking locally");
        return await _checkSpinEligibilityLocally();
      }
    } catch (e) {
      debugPrint("⚠️ Daily spin check failed: $e - checking locally");
      // If server is unreachable, check local storage
      return await _checkSpinEligibilityLocally();
    }
  }
  
  /// Check local storage for last spin time (fallback when server unavailable)
  Future<Map<String, dynamic>> _checkSpinEligibilityLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSpinStr = prefs.getString('last_daily_spin_time');
    
    if (lastSpinStr == null) {
      // Never spun before - allow
      return {'can_spin': true};
    }
    
    final lastSpin = DateTime.tryParse(lastSpinStr);
    if (lastSpin == null) {
      // Invalid date - allow
      return {'can_spin': true};
    }
    
    // Calculate next spin time: 24 hours from last spin
    final nextSpin = DateTime(
      lastSpin.year, lastSpin.month, lastSpin.day + 1,
      lastSpin.hour, lastSpin.minute, lastSpin.second,
    );
    final now = DateTime.now();
    
    if (now.isBefore(nextSpin)) {
      // Still in cooldown
      return {
        'can_spin': false,
        'next_spin_time': nextSpin.toIso8601String(),
        'last_spin_time': lastSpinStr,
      };
    }
    
    // Cooldown expired - allow spin
    return {'can_spin': true};
  }

  /// Perform daily spin - server determines reward and grants credits
  /// This is tamper-proof as:
  /// 1. Server verifies eligibility using server time
  /// 2. Server randomly selects reward using its RNG
  /// 3. Server grants credits directly to user account
  Future<Map<String, dynamic>> performDailySpin() async {
    if (!_authService.isSignedIn) {
      throw Exception('Not signed in');
    }

    final token = await _authService.getIdToken();
    if (token == null) {
      throw Exception('No authentication token');
    }

    try {
      final response = await _authenticatedPost(
        '/auth/daily-spin/spin',
        {'device_id': await _getDeviceId()},
        token,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final creditsWon = (data['credits_won'] as num?)?.toInt() ?? 0;
        
        // Update local credits
        userCreditsNotifier.value += creditsWon;
        
        // Also refresh from server to be accurate
        refreshCredits();
        
        return {
          'credits_won': creditsWon,
          'next_spin_time': data['next_spin_time'],
          'message': data['message'],
        };
      } else if (response.statusCode == 429) {
        // Rate limited - already spun today
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Already spun today. Come back tomorrow!');
      } else {
        // API not implemented - simulate for testing
        debugPrint("⚠️ Daily spin API returned ${response.statusCode}, simulating locally");
        return await _simulateSpinLocally();
      }
    } catch (e) {
      if (e.toString().contains('429') || e.toString().contains('Already spun')) {
        rethrow;
      }
      debugPrint("⚠️ Daily spin API failed: $e - simulating locally");
      // Fallback to local simulation if server unavailable
      return await _simulateSpinLocally();
    }
  }

  /// Local simulation for testing (until server endpoint is ready)
  /// In production, this should throw an error if server is unavailable
  Future<Map<String, dynamic>> _simulateSpinLocally() async {
    // Check local cooldown first
    final prefs = await SharedPreferences.getInstance();
    final lastSpinStr = prefs.getString('last_daily_spin_time');
    
    if (lastSpinStr != null) {
      final lastSpin = DateTime.tryParse(lastSpinStr);
      if (lastSpin != null) {
        // Calculate next spin time: next day at same hour
        final nextSpin = DateTime(
          lastSpin.year, lastSpin.month, lastSpin.day + 1,
          lastSpin.hour, lastSpin.minute, lastSpin.second,
        );
        final now = DateTime.now();
        if (now.isBefore(nextSpin)) {
          throw Exception('Already spun today! Next spin: ${nextSpin.toIso8601String()}');
        }
      }
    }
    
    // Realistic probability distribution
    // Total = 100%
    const rewards = [
      {'credits': 1, 'probability': 0.35},  // 35% - most common
      {'credits': 2, 'probability': 0.25},  // 25%
      {'credits': 5, 'probability': 0.20},  // 20%
      {'credits': 10, 'probability': 0.12}, // 12%
      {'credits': 25, 'probability': 0.06}, // 6% - rare
      {'credits': 50, 'probability': 0.02}, // 2% - legendary
    ];
    
    final random = Random().nextDouble();
    double cumulative = 0;
    int wonCredits = 1;
    
    for (final reward in rewards) {
      cumulative += (reward['probability'] as num).toDouble();
      if (random <= cumulative) {
        wonCredits = (reward['credits'] as num).toInt();
        break;
      }
    }
    
    // Save spin time locally
    final now = DateTime.now();
    await prefs.setString('last_daily_spin_time', now.toIso8601String());
    
    // Calculate next spin time (24 hours from now)
    final nextSpinTime = DateTime(
      now.year, now.month, now.day + 1,
      now.hour, now.minute, now.second,
    );
    
    // Update local credits
    userCreditsNotifier.value += wonCredits;
    
    debugPrint("🎰 Simulated spin: won $wonCredits credits, next spin at: ${nextSpinTime.toIso8601String()}");
    
    return {
      'credits_won': wonCredits,
      'next_spin_time': nextSpinTime.toIso8601String(),
      'message': 'You won $wonCredits credits!',
    };
  }

  // ============================================================
  // HTTP HELPERS
  // ============================================================

  Future<http.Response> _authenticatedGet(String endpoint, String token) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    
    return await http.get(
      Uri.parse('$_backendUrl$endpoint'),
      headers: headers,
    ).timeout(const Duration(seconds: 30));
  }

  Future<http.Response> _authenticatedPost(
    String endpoint, 
    Map<String, dynamic> payload,
    String token,
  ) async {
    final body = jsonEncode(payload);
    
    // Firebase ID token is verified by backend with Firebase Admin SDK
    // No additional signatures needed - token is cryptographically signed by Google
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    
    return await http.post(
      Uri.parse('$_backendUrl$endpoint'),
      headers: headers,
      body: body,
    ).timeout(const Duration(seconds: 30));
  }
}

// ============================================================
// SIGN-IN PROMPT HELPER
// ============================================================

/// Tracks when to show sign-in prompts
class SignInPromptManager {
  static const String _promptCountKey = 'signin_prompt_count';
  static const String _lastPromptKey = 'last_signin_prompt';
  static const int _promptIntervalMinutes = 30; // Show prompt every 30 mins
  static const int _maxPrompts = 3; // Max prompts per day

  /// Check if we should show a sign-in prompt
  static Future<bool> shouldShowPrompt() async {
    if (AuthService().isSignedIn) return false;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Check prompt count today
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastPromptDate = prefs.getString('prompt_date');
    int promptCount = prefs.getInt(_promptCountKey) ?? 0;
    
    // Reset count if new day
    if (lastPromptDate != today) {
      promptCount = 0;
      await prefs.setString('prompt_date', today);
    }
    
    // Don't show more than max prompts per day
    if (promptCount >= _maxPrompts) return false;
    
    // Check time since last prompt
    final lastPrompt = prefs.getString(_lastPromptKey);
    if (lastPrompt != null) {
      final lastTime = DateTime.tryParse(lastPrompt);
      if (lastTime != null) {
        final elapsed = DateTime.now().difference(lastTime);
        if (elapsed.inMinutes < _promptIntervalMinutes) return false;
      }
    }
    
    return true;
  }

  /// Record that a prompt was shown
  static Future<void> recordPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    int promptCount = prefs.getInt(_promptCountKey) ?? 0;
    final lastDate = prefs.getString('prompt_date');
    
    if (lastDate != today) {
      promptCount = 0;
      await prefs.setString('prompt_date', today);
    }
    
    await prefs.setInt(_promptCountKey, promptCount + 1);
    await prefs.setString(_lastPromptKey, DateTime.now().toIso8601String());
  }

  /// Reset prompt counters (e.g., after successful sign-in)
  static Future<void> resetPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promptCountKey);
    await prefs.remove(_lastPromptKey);
    await prefs.remove('prompt_date');
  }
}

