import 'package:flutter/foundation.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';

/// AdGem Offerwall service for generating offerwall URLs
/// 
/// Configuration:
/// - Property Name: kala-ai-offerwall
/// - App ID: 31874
/// - Credits are awarded via server postback (NEVER client-side)
class AdGemService {
  static const String _appId = '31874';
  static const String _baseUrl = 'https://api.adgem.com/v1/wall';
  
  final AuthService _authService = AuthService();
  
  /// Singleton instance
  static final AdGemService _instance = AdGemService._internal();
  factory AdGemService() => _instance;
  AdGemService._internal();
  
  /// Check if user can access offerwall (must be signed in)
  bool get canAccessOfferwall => _authService.isSignedIn;
  
  /// Get the user's Firebase UID for tracking
  String? get _playerid => _authService.firebaseUid;
  
  /// Generate the offerwall URL with the user's playerid
  /// 
  /// The playerid is the user's Firebase UID, which is used by the server
  /// to identify which user to credit when an offer is completed.
  /// 
  /// Returns null if user is not signed in.
  String? getOfferwallUrl() {
    final playerid = _playerid;
    if (playerid == null) {
      debugPrint('⚠️ AdGem: Cannot generate URL - user not signed in');
      return null;
    }
    
    final url = '$_baseUrl?appid=$_appId&playerid=$playerid';
    debugPrint('🎁 AdGem: Generated offerwall URL for user $playerid');
    return url;
  }
  
  /// Generate offerwall URL with additional optional parameters
  /// 
  /// [subid1], [subid2], etc. can be used for additional tracking
  String? getOfferwallUrlWithParams({
    String? subid1,
    String? subid2,
    String? subid3,
  }) {
    final playerid = _playerid;
    if (playerid == null) {
      debugPrint('⚠️ AdGem: Cannot generate URL - user not signed in');
      return null;
    }
    
    final params = <String, String>{
      'appid': _appId,
      'playerid': playerid,
    };
    
    if (subid1 != null) params['subid1'] = subid1;
    if (subid2 != null) params['subid2'] = subid2;
    if (subid3 != null) params['subid3'] = subid3;
    
    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    debugPrint('🎁 AdGem: Generated offerwall URL with params: $uri');
    return uri.toString();
  }
}
