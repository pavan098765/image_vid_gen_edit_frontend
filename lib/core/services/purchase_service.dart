// lib/core/services/purchase_service.dart
//
// In-App Purchase Service for managing purchases (Ad-Free, Credit Packs)
// Uses the official in_app_purchase Flutter package

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'user_service.dart';

// ============================================================
// PRODUCT IDS - Must match App Store Connect / Play Console
// ============================================================

/// Product ID for removing ads (consumable, server-tracked)
/// 
/// NOTE: This is a CONSUMABLE product in Play Console, but treated as
/// a one-time purchase by our backend. This allows:
/// - Different Firebase accounts to purchase independently
/// - Server-side ownership tracking (no Google Play restore needed)
/// - Automatic restore on sign-in via checkAdFreeStatus()
const String kRemoveAdsProductId = 'remove_ads_lifetime_v2';

/// Credit pack product IDs (consumable one-time purchases)
const String kCredits50ProductId = 'credits_50';
const String kCredits100ProductId = 'credits_100';
const String kCredits500ProductId = 'credits_500';
const String kCredits1000ProductId = 'credits_1000';
const String kCredits2500ProductId = 'credits_2500';
const String kCredits5000ProductId = 'credits_5000';
const String kCredits10000ProductId = 'credits_10000';

/// All product IDs to load
const Set<String> kProductIds = {
  kRemoveAdsProductId,
  kCredits50ProductId,
  kCredits100ProductId,
  kCredits500ProductId,
  kCredits1000ProductId,
  kCredits2500ProductId,
  kCredits5000ProductId,
  kCredits10000ProductId,
};

/// Gem pack configurations (for UI display & backend mapping)
/// The actual prices come from the store, these are just for sorting/display
class GemPackConfig {
  final String productId;
  final int gems;
  final String label;
  final bool isPopular;
  final bool isBestValue;
  
  const GemPackConfig({
    required this.productId,
    required this.gems,
    required this.label,
    this.isPopular = false,
    this.isBestValue = false,
  });
}

/// All gem packs in order (smallest to largest)
const List<GemPackConfig> kGemPacks = [
  GemPackConfig(productId: kCredits50ProductId, gems: 50, label: 'Tiny'),
  GemPackConfig(productId: kCredits100ProductId, gems: 100, label: 'Starter'),
  GemPackConfig(productId: kCredits500ProductId, gems: 500, label: 'Power', isPopular: true),
  GemPackConfig(productId: kCredits1000ProductId, gems: 1000, label: 'Mega'),
  GemPackConfig(productId: kCredits2500ProductId, gems: 2500, label: 'Super'),
  GemPackConfig(productId: kCredits5000ProductId, gems: 5000, label: 'Ultra'),
  GemPackConfig(productId: kCredits10000ProductId, gems: 10000, label: 'Legendary', isBestValue: true),
];

// ============================================================
// PURCHASE STATE (renamed to avoid conflict with in_app_purchase.PurchaseStatus)
// ============================================================

enum IAPState {
  /// Initial state, store not connected
  notAvailable,
  
  /// Store is available and ready
  available,
  
  /// Loading products from store
  loadingProducts,
  
  /// Products loaded successfully
  ready,
  
  /// Purchase in progress
  purchasing,
  
  /// Verifying purchase with backend
  verifying,
  
  /// Purchase completed successfully
  completed,
  
  /// Purchase failed or cancelled
  failed,
  
  /// Error state
  error,
}

// ============================================================
// PURCHASE SERVICE
// ============================================================

class PurchaseService {
  static PurchaseService? _instance;
  static PurchaseService get instance => _instance ??= PurchaseService._();
  
  PurchaseService._();
  
  final InAppPurchase _iap = InAppPurchase.instance;
  
  /// Stream subscription for purchase updates
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  /// Available products from the store
  final ValueNotifier<List<ProductDetails>> productsNotifier = 
      ValueNotifier<List<ProductDetails>>([]);
  
  /// Current purchase state
  final ValueNotifier<IAPState> statusNotifier = 
      ValueNotifier<IAPState>(IAPState.notAvailable);
  
  /// Error message if any
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);
  
  /// Currently processing product ID
  String? _currentPurchaseProductId;
  
  /// Get the currently processing product ID
  String? get currentPurchaseProductId => _currentPurchaseProductId;
  
  /// Callback for purchase completion
  Function(String productId, bool success, String? error)? onPurchaseComplete;
  
  /// Whether service is initialized
  bool _initialized = false;
  
  /// Get a product by ID
  ProductDetails? getProduct(String productId) {
    try {
      return productsNotifier.value.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }
  
  /// Get the Remove Ads product
  ProductDetails? get removeAdsProduct => getProduct(kRemoveAdsProductId);
  
  /// Get credit pack products
  List<ProductDetails> get creditPackProducts {
    return productsNotifier.value
        .where((p) => p.id != kRemoveAdsProductId)
        .toList();
  }
  
  // ============================================================
  // INITIALIZATION
  // ============================================================
  
  /// Initialize the purchase service
  /// Call this once during app startup
  Future<void> initialize() async {
    if (_initialized) return;
    
    debugPrint("💳 Initializing PurchaseService...");
    
    // Check if store is available
    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint("⚠️ In-app purchases not available on this device");
      statusNotifier.value = IAPState.notAvailable;
      return;
    }
    
    statusNotifier.value = IAPState.available;
    debugPrint("✅ Store is available");
    
    // Note: enablePendingPurchases() is no longer needed in newer versions
    // It's now enabled by default
    
    // Listen to purchase updates
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        debugPrint("💳 Purchase stream closed");
        _subscription?.cancel();
      },
      onError: (error) {
        debugPrint("❌ Purchase stream error: $error");
        errorNotifier.value = error.toString();
        statusNotifier.value = IAPState.error;
      },
    );
    
    // Load products
    await loadProducts();
    
    _initialized = true;
    debugPrint("✅ PurchaseService initialized");
  }
  
  /// Dispose the service
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
  
  // ============================================================
  // PRODUCT LOADING
  // ============================================================
  
  /// Load products from the store
  Future<void> loadProducts() async {
    statusNotifier.value = IAPState.loadingProducts;
    debugPrint("📦 Loading products: $kProductIds");
    debugPrint("📦 Total product IDs to query: ${kProductIds.length}");
    
    try {
      final response = await _iap.queryProductDetails(kProductIds);
      
      debugPrint("📦 Query response:");
      debugPrint("   - Found: ${response.productDetails.length} products");
      debugPrint("   - Not found: ${response.notFoundIDs.length} IDs");
      
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint("⚠️ Products NOT found in Play Console: ${response.notFoundIDs}");
        debugPrint("   Make sure these product IDs exist and are ACTIVE in Play Console");
      }
      
      if (response.productDetails.isEmpty) {
        debugPrint("⚠️ No products found in store");
        errorNotifier.value = "No products available";
        statusNotifier.value = IAPState.error;
        return;
      }
      
      productsNotifier.value = response.productDetails;
      statusNotifier.value = IAPState.ready;
      
      debugPrint("✅ Loaded ${response.productDetails.length} products:");
      for (final product in response.productDetails) {
        debugPrint("   - ${product.id}: ${product.price} (${product.title})");
      }
    } catch (e) {
      debugPrint("❌ Failed to load products: $e");
      errorNotifier.value = e.toString();
      statusNotifier.value = IAPState.error;
    }
  }
  
  // ============================================================
  // PURCHASE FLOW
  // ============================================================
  
  /// Purchase the Remove Ads product
  /// 
  /// IMPORTANT: This checks with server first to prevent double-purchase.
  /// The product should be set as "Consumable" in Play Console to allow
  /// different Firebase accounts to purchase independently.
  Future<bool> purchaseRemoveAds() async {
    final product = removeAdsProduct;
    if (product == null) {
      errorNotifier.value = "Product not available";
      return false;
    }
    
    // Pre-purchase check: Does this Firebase account already have ad-free?
    // This prevents double-charging the same account
    try {
      debugPrint("🔍 Checking if user already has ad-free...");
      final alreadyAdFree = await UserService().checkAdFreeStatus();
      if (alreadyAdFree) {
        debugPrint("ℹ️ User already has ad-free - blocking purchase");
        errorNotifier.value = "You already have ad-free! No need to purchase again.";
        return false;
      }
    } catch (e) {
      debugPrint("⚠️ Could not check ad-free status: $e");
      // Continue with purchase - server will reject if already ad-free
    }
    
    // Purchase as consumable to allow different accounts to buy independently
    // Server tracks ownership per Firebase account
    return await _purchaseProduct(product, isConsumable: true);
  }
  
  /// Purchase a credit pack
  Future<bool> purchaseCreditPack(String productId) async {
    final product = getProduct(productId);
    if (product == null) {
      errorNotifier.value = "Product not available";
      return false;
    }
    
    return await _purchaseProduct(product, isConsumable: true);
  }
  
  /// Internal purchase method
  Future<bool> _purchaseProduct(ProductDetails product, {required bool isConsumable}) async {
    // Check if user is signed in (required for server verification)
    if (currentUserNotifier.value == null) {
      errorNotifier.value = "Please sign in to make purchases";
      return false;
    }
    
    debugPrint("💳 Starting purchase: ${product.id}");
    statusNotifier.value = IAPState.purchasing;
    _currentPurchaseProductId = product.id;
    errorNotifier.value = null;
    
    try {
      // Create purchase param
      late PurchaseParam purchaseParam;
      
      if (Platform.isAndroid) {
        // Android: Use Google Play purchase param
        purchaseParam = GooglePlayPurchaseParam(
          productDetails: product,
          // Optional: applicationUserName for fraud prevention
          applicationUserName: currentUserNotifier.value?.firebaseUid,
        );
      } else if (Platform.isIOS) {
        // iOS: Use App Store purchase param
        purchaseParam = PurchaseParam(
          productDetails: product,
          applicationUserName: currentUserNotifier.value?.firebaseUid,
        );
      } else {
        throw Exception("Unsupported platform");
      }
      
      // Initiate purchase
      final success = isConsumable
          ? await _iap.buyConsumable(purchaseParam: purchaseParam)
          : await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      
      if (!success) {
        debugPrint("⚠️ Purchase initiation failed");
        statusNotifier.value = IAPState.failed;
        errorNotifier.value = "Could not start purchase";
        return false;
      }
      
      debugPrint("✅ Purchase initiated, waiting for store response...");
      return true; // Purchase initiated, result will come via stream
      
    } catch (e) {
      debugPrint("❌ Purchase error: $e");
      statusNotifier.value = IAPState.failed;
      errorNotifier.value = e.toString();
      _currentPurchaseProductId = null;
      return false;
    }
  }
  
  // ============================================================
  // PURCHASE HANDLING
  // ============================================================
  
  /// Handle purchase updates from the store
  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      debugPrint("💳 Purchase update: ${purchase.productID} - ${purchase.status}");
      
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Purchase is pending (e.g., waiting for payment)
          statusNotifier.value = IAPState.purchasing;
          debugPrint("⏳ Purchase pending: ${purchase.productID}");
          break;
          
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Purchase successful - verify with backend
          await _verifyAndComplete(purchase);
          break;
          
        case PurchaseStatus.error:
          // Purchase failed
          // Note: productID may be empty for some error types, use _currentPurchaseProductId as fallback
          final effectiveProductId = purchase.productID.isNotEmpty 
              ? purchase.productID 
              : _currentPurchaseProductId ?? '';
          
          debugPrint("❌ Purchase error for $effectiveProductId:");
          debugPrint("   Error code: ${purchase.error?.code}");
          debugPrint("   Error message: ${purchase.error?.message}");
          debugPrint("   Error details: ${purchase.error?.details}");
          debugPrint("   Error source: ${purchase.error?.source}");
          
          final errorMsg = purchase.error?.message ?? "Purchase failed";
          
          // Handle "already owned" for remove_ads product
          // This happens when the Play Store account already owns the product
          if (effectiveProductId == kRemoveAdsProductId && 
              (errorMsg.contains('itemUnavailable') || 
               errorMsg.contains('already') ||
               errorMsg.contains('Already') ||
               errorMsg.contains('ITEM_ALREADY_OWNED') ||
               errorMsg.contains('itemAlreadyOwned'))) {
            debugPrint("ℹ️ Play Store says 'already owned' - checking with server...");
            
            try {
              final isAdFree = await UserService().checkAdFreeStatus();
              if (isAdFree) {
                // This Firebase account has ad-free - great!
                debugPrint("✅ Server confirmed ad-free for this account");
                statusNotifier.value = IAPState.completed;
                _notifyPurchaseComplete(effectiveProductId, true, null);
                if (purchase.pendingCompletePurchase) {
                  await _iap.completePurchase(purchase);
                }
                break;
              } else {
                // This Firebase account does NOT have ad-free, but Play Store says "owned"
                // This means another Firebase account claimed this purchase
                debugPrint("⚠️ Play Store owns it, but this Firebase account doesn't have it");
                debugPrint("   This purchase is linked to a different app account.");
                statusNotifier.value = IAPState.failed;
                errorNotifier.value = 'This device\'s Play Store already has an ad-free purchase linked to a different app account. Please sign in with that account, or contact support.';
                _notifyPurchaseComplete(effectiveProductId, false, errorNotifier.value);
                if (purchase.pendingCompletePurchase) {
                  await _iap.completePurchase(purchase);
                }
                break;
              }
            } catch (e) {
              debugPrint("⚠️ Failed to check ad-free status: $e");
            }
          }
          
          statusNotifier.value = IAPState.failed;
          errorNotifier.value = errorMsg;
          _notifyPurchaseComplete(effectiveProductId, false, errorNotifier.value);
          
          // Complete the purchase to clear it
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
          
        case PurchaseStatus.canceled:
          // User cancelled
          debugPrint("🚫 Purchase cancelled: ${purchase.productID}");
          statusNotifier.value = IAPState.ready;
          errorNotifier.value = null;
          _notifyPurchaseComplete(purchase.productID, false, "Cancelled");
          
          // Complete the purchase to clear it
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
      }
    }
  }
  
  /// Verify purchase with backend and complete
  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    debugPrint("🔐 Verifying purchase with backend: ${purchase.productID}");
    statusNotifier.value = IAPState.verifying;
    
    try {
      // Get the purchase token/receipt
      String purchaseToken;
      String platform;
      String? orderId;
      
      if (Platform.isAndroid) {
        // Android: Get from Google Play purchase details
        final androidPurchase = purchase as GooglePlayPurchaseDetails;
        purchaseToken = androidPurchase.billingClientPurchase.purchaseToken;
        orderId = androidPurchase.billingClientPurchase.orderId;
        platform = 'android';
        debugPrint("📱 Android purchase - Token: ${purchaseToken.substring(0, 20)}..., Order: $orderId");
      } else if (Platform.isIOS) {
        // iOS: Get from verification data
        purchaseToken = purchase.verificationData.serverVerificationData;
        platform = 'ios';
        debugPrint("📱 iOS purchase - Receipt length: ${purchaseToken.length}");
      } else {
        throw Exception("Unsupported platform");
      }
      
      // Determine if this is the remove ads product
      if (purchase.productID == kRemoveAdsProductId) {
        // Verify ad-free purchase with backend
        final verified = await UserService().verifyAdFreePurchase(
          purchaseToken: purchaseToken,
          productId: purchase.productID,
          platform: platform,
        );
        
        if (verified) {
          // Update ad-free status
          notifyAdFreeStatusChanged(true, verifiedByServer: true);
          debugPrint("✅ Ad-free purchase verified and activated!");
        } else {
          throw Exception("Server verification failed");
        }
      } else {
        // Credit pack purchase - verify with backend
        debugPrint("💰 Verifying credit pack purchase: ${purchase.productID}");
        
        final result = await UserService().verifyGemPurchase(
          purchaseToken: purchaseToken,
          productId: purchase.productID,
          platform: platform,
          orderId: orderId,
        );
        
        if (result != null && result['success'] == true) {
          final gemsAwarded = result['gems_awarded'] ?? 0;
          final newBalance = result['new_balance'] ?? 0;
          debugPrint("✅ Gem purchase verified! Awarded: $gemsAwarded, New balance: $newBalance");
          
          // Refresh user credits to update UI
          await UserService().refreshCredits();
        } else {
          throw Exception(result?['error'] ?? "Server verification failed");
        }
      }
      
      // Complete the purchase with the store
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
        debugPrint("✅ Purchase completed with store");
      }
      
      statusNotifier.value = IAPState.completed;
      _notifyPurchaseComplete(purchase.productID, true, null);
      
    } catch (e) {
      debugPrint("❌ Purchase verification failed: $e");
      
      // Handle specific error cases with user-friendly messages
      String errorMessage = e.toString();
      
      if (errorMessage.contains('already used') || 
          errorMessage.contains('already verified') ||
          errorMessage.contains('duplicate')) {
        // This purchase token was already used by another account
        errorMessage = 'This purchase is linked to another account. Please sign in with the original account.';
      } else if (errorMessage.contains('invalid') || errorMessage.contains('Invalid')) {
        errorMessage = 'Purchase verification failed. Please try again or contact support.';
      }
      
      statusNotifier.value = IAPState.failed;
      errorNotifier.value = errorMessage;
      _notifyPurchaseComplete(purchase.productID, false, errorMessage);
      
      // Still complete the purchase to clear it from pending
      // The user can contact support if there's an issue
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
  
  void _notifyPurchaseComplete(String productId, bool success, String? error) {
    _currentPurchaseProductId = null;
    onPurchaseComplete?.call(productId, success, error);
  }
  
  // ============================================================
  // RESTORE PURCHASES
  // ============================================================
  
  /// Restore previous purchases (required by App Store)
  /// For our app, this mainly restores the ad-free purchase (non-consumable)
  /// Consumables (gem packs) are handled server-side and don't need restore
  /// 
  /// Returns true if ad-free was restored, false otherwise
  Future<bool> restorePurchases() async {
    debugPrint("🔄 Restoring purchases...");
    statusNotifier.value = IAPState.purchasing;
    errorNotifier.value = null;
    
    try {
      // First, check with server for ad-free status
      // This is more reliable than Google Play restore for our use case
      debugPrint("🔍 Checking ad-free status with server...");
      final isAdFree = await UserService().checkAdFreeStatus();
      
      if (isAdFree) {
        debugPrint("✅ Ad-free status confirmed by server");
        statusNotifier.value = IAPState.completed;
        // Don't call _notifyPurchaseComplete here - just update state
        // The caller can handle the UI update based on isAdFreeNotifier
        return true;
      }
      
      // If server says not ad-free, try Google Play restore
      // This handles cases where purchase wasn't verified yet
      debugPrint("📱 Initiating Google Play restore...");
      await _iap.restorePurchases();
      debugPrint("✅ Restore initiated - waiting for results");
      // Results will come through the purchase stream
      
      // Wait for results to come through (verification can take a few seconds)
      // Poll every 500ms for up to 8 seconds
      for (int i = 0; i < 16; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Check if we got a result (either completed or failed)
        if (statusNotifier.value == IAPState.completed) {
          debugPrint("✅ Restore completed successfully");
          return true;
        }
        if (statusNotifier.value == IAPState.failed) {
          debugPrint("❌ Restore failed: ${errorNotifier.value}");
          return false;
        }
      }
      
      // Timeout - no restore came through
      debugPrint("ℹ️ No purchases to restore from Play Store (timeout)");
      statusNotifier.value = IAPState.ready;
      errorNotifier.value = "No purchases to restore";
      return false;
      
    } catch (e) {
      debugPrint("❌ Restore failed: $e");
      statusNotifier.value = IAPState.failed;
      errorNotifier.value = e.toString();
      return false;
    }
  }
  
  // ============================================================
  // iOS SPECIFIC
  // ============================================================
  
  /// Check for pending transactions on iOS
  /// Call this on app startup to handle any stuck transactions
  Future<void> checkPendingTransactions() async {
    if (!Platform.isIOS) return;
    
    try {
      // Access the StoreKit platform addition for iOS-specific operations
      // ignore: unused_local_variable
      final _ = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      final transactions = await SKPaymentQueueWrapper().transactions();
      
      for (final transaction in transactions) {
        debugPrint("📱 Pending iOS transaction: ${transaction.transactionIdentifier}");
        // These will be processed through the purchase stream
      }
    } catch (e) {
      debugPrint("⚠️ Failed to check pending transactions: $e");
    }
  }
}
