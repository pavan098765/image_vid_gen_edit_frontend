// lib/core/services/auth_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Allowlist of trusted email providers (more reliable than blocking temp domains)
/// Includes major providers globally - users with other domains can use Google Sign-In
const Set<String> _allowedEmailDomains = {
  // Google
  'gmail.com', 'googlemail.com',
  // Microsoft
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'hotmail.co.uk',
  'hotmail.fr', 'hotmail.de', 'hotmail.it', 'hotmail.es', 'outlook.in',
  'outlook.co.uk', 'outlook.de', 'outlook.fr', 'outlook.es', 'outlook.jp',
  // Yahoo
  'yahoo.com', 'yahoo.co.uk', 'yahoo.co.in', 'yahoo.ca', 'yahoo.com.au',
  'yahoo.de', 'yahoo.fr', 'yahoo.es', 'yahoo.it', 'yahoo.co.jp',
  'ymail.com', 'rocketmail.com',
  // Apple
  'icloud.com', 'me.com', 'mac.com',
  // ProtonMail (privacy-focused but legitimate)
  'protonmail.com', 'proton.me', 'pm.me',
  // Zoho
  'zoho.com', 'zohomail.com', 'zohomail.in',
  // AOL
  'aol.com', 'aol.co.uk',
  // India
  'rediffmail.com', 'rediff.com',
  // Germany
  'gmx.com', 'gmx.de', 'gmx.net', 'gmx.at', 'gmx.ch',
  'web.de', 't-online.de', 'freenet.de', 'arcor.de',
  // France
  'orange.fr', 'wanadoo.fr', 'laposte.net', 'sfr.fr', 'free.fr',
  // UK
  'btinternet.com', 'virginmedia.com', 'sky.com', 'talktalk.net',
  // Italy
  'libero.it', 'virgilio.it', 'alice.it', 'tin.it', 'fastwebnet.it',
  // Spain
  'telefonica.net', 'terra.es',
  // Russia
  'mail.ru', 'yandex.ru', 'yandex.com', 'rambler.ru',
  // China
  'qq.com', '163.com', '126.com', 'sina.com', 'sohu.com',
  // Japan
  'nifty.com', 'docomo.ne.jp', 'ezweb.ne.jp', 'softbank.ne.jp',
  // Brazil
  'uol.com.br', 'bol.com.br', 'globo.com', 'ig.com.br', 'terra.com.br',
  // Other popular
  'mail.com', 'email.com', 'usa.com', 'fastmail.com', 'fastmail.fm',
  'tutanota.com', 'tutamail.com', 'tuta.io',
  'comcast.net', 'verizon.net', 'att.net', 'sbcglobal.net', 'cox.net',
  'charter.net', 'earthlink.net', 'juno.com', 'netzero.net',
};

/// Authentication service for Firebase Auth (Email + Google Sign-In)
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Whether user is signed in
  bool get isSignedIn => currentUser != null;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get user's Firebase UID
  String? get firebaseUid => currentUser?.uid;

  /// Get user's email
  String? get userEmail => currentUser?.email;

  /// Get user's display name
  String? get userName => currentUser?.displayName ?? currentUser?.email?.split('@').first;

  /// Get user's photo URL
  String? get userPhotoUrl => currentUser?.photoURL;

  // ============================================================
  // EMAIL VALIDATION
  // ============================================================

  /// Check if email domain is from an allowed/trusted provider
  static bool isAllowedEmailDomain(String email) {
    final domain = email.toLowerCase().split('@').lastOrNull ?? '';
    // Also allow educational (.edu) and organizational domains
    if (domain.endsWith('.edu') || domain.endsWith('.ac.uk') || 
        domain.endsWith('.edu.in') || domain.endsWith('.edu.au')) {
      return true;
    }
    return _allowedEmailDomains.contains(domain);
  }

  /// Legacy method name for compatibility - now checks allowlist
  static bool isTemporaryEmail(String email) {
    return !isAllowedEmailDomain(email);
  }

  /// Validate email for sign-up (checks format and allowed domains)
  static String? validateEmailForSignUp(String email) {
    final trimmed = email.trim().toLowerCase();
    
    // Basic format check
    if (!trimmed.contains('@') || !trimmed.contains('.')) {
      return 'Please enter a valid email address.';
    }
    
    // Check if email domain is allowed
    if (!isAllowedEmailDomain(trimmed)) {
      return 'Please use a common email provider (Gmail, Outlook, Yahoo, etc.) or sign in with Google.';
    }
    
    return null; // Valid
  }

  // ============================================================
  // EMAIL/PASSWORD AUTHENTICATION
  // ============================================================

  /// Sign up with email and password
  /// Returns UserCredential on success, throws FirebaseAuthException on failure
  /// Automatically sends email verification
  /// Blocks temporary/disposable email addresses
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    // Validate email before attempting sign-up
    final validationError = validateEmailForSignUp(email);
    if (validationError != null) {
      throw AuthException(
        code: 'temporary-email-blocked',
        message: validationError,
      );
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      // Update display name to email prefix
      await credential.user?.updateDisplayName(email.split('@').first);
      
      // Send email verification
      await credential.user?.sendEmailVerification();
      debugPrint("📧 Verification email sent to: $email");
      
      debugPrint("✅ Email sign-up successful: ${credential.user?.uid}");
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Email sign-up failed: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  /// Check if current user's email is verified
  bool get isEmailVerified => currentUser?.emailVerified ?? false;
  
  /// Check if user signed in with email/password provider (vs Google/social)
  bool get isEmailPasswordUser {
    final providers = currentUser?.providerData ?? [];
    return providers.any((info) => info.providerId == 'password');
  }
  
  /// Check if user needs email verification (signed up via email but not verified)
  /// Returns false for Google sign-in users (they're auto-verified)
  bool get needsEmailVerification {
    if (!isSignedIn) return false;
    if (!isEmailPasswordUser) return false; // Google users don't need verification
    return !isEmailVerified;
  }

  /// Resend email verification
  Future<void> resendEmailVerification() async {
    try {
      await currentUser?.sendEmailVerification();
      debugPrint("📧 Verification email resent");
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Failed to resend verification: ${e.code}");
      rethrow;
    }
  }

  /// Reload user to check latest email verification status
  Future<void> reloadUser() async {
    await currentUser?.reload();
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      debugPrint("✅ Email sign-in successful: ${credential.user?.uid}");
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Email sign-in failed: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("❌ Email sign-in error: $e");
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      debugPrint("✅ Password reset email sent to: $email");
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Password reset failed: ${e.code} - ${e.message}");
      rethrow;
    }
  }

  // ============================================================
  // GOOGLE SIGN-IN
  // ============================================================

  /// Sign in with Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        throw AuthException(
          code: 'google-sign-in-cancelled',
          message: 'Google sign-in was cancelled by user',
        );
      }

      // Obtain auth details from Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credential
      final userCredential = await _auth.signInWithCredential(credential);
      
      debugPrint("✅ Google sign-in successful: ${userCredential.user?.uid}");
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Google sign-in failed: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("❌ Google sign-in error: $e");
      throw AuthException(
        code: 'google-sign-in-failed',
        message: e.toString(),
      );
    }
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  /// Sign out from both Firebase and Google
  Future<void> signOut() async {
    try {
      // Sign out from Google (if signed in with Google)
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      
      // Sign out from Firebase
      await _auth.signOut();
      
      // Clear local auth data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('user_credits');
      await prefs.remove('last_credit_sync');
      
      debugPrint("✅ Sign-out successful");
    } catch (e) {
      debugPrint("❌ Sign-out error: $e");
      rethrow;
    }
  }

  // ============================================================
  // TOKEN MANAGEMENT
  // ============================================================

  /// Get Firebase ID token for backend API calls
  /// Always call this fresh before API calls (tokens expire after 1 hour)
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      final user = currentUser;
      if (user == null) return null;
      
      final token = await user.getIdToken(forceRefresh);
      return token;
    } catch (e) {
      debugPrint("❌ Failed to get ID token: $e");
      return null;
    }
  }

  /// Get authorization header for API calls
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getIdToken();
    if (token == null) {
      return {'Content-Type': 'application/json'};
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Force refresh the Firebase ID token
  /// This is needed after email verification to get updated claims (email_verified)
  /// Without this, the server might still see stale email_verified=false
  Future<void> forceRefreshToken() async {
    try {
      final user = currentUser;
      if (user == null) return;
      
      await user.getIdToken(true); // true = forceRefresh
      debugPrint("✅ Force refreshed ID token with updated claims");
    } catch (e) {
      debugPrint("❌ Failed to force refresh token: $e");
      rethrow;
    }
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Check if this is a new user (just created account)
  Future<bool> isNewUser(UserCredential credential) async {
    return credential.additionalUserInfo?.isNewUser ?? false;
  }

  /// Get friendly error message from exceptions
  static String getErrorMessage(dynamic e) {
    String code;
    String? message;
    
    if (e is FirebaseAuthException) {
      code = e.code;
      message = e.message;
    } else if (e is AuthException) {
      code = e.code;
      message = e.message;
    } else {
      // Handle generic exceptions - try to extract useful info
      final errStr = e.toString().toLowerCase();
      debugPrint("⚠️ Non-Firebase auth error: $e");
      
      // Check for common patterns in error strings
      if (errStr.contains('invalid-credential') || 
          errStr.contains('invalid_login_credentials') ||
          errStr.contains('wrong-password') ||
          errStr.contains('user-not-found')) {
        return 'Invalid email or password. Please check and try again.';
      }
      if (errStr.contains('network') || errStr.contains('connection')) {
        return 'Network error. Please check your connection.';
      }
      if (errStr.contains('too-many-requests')) {
        return 'Too many attempts. Please try again later.';
      }
      return 'An error occurred. Please try again.';
    }
    
    switch (code) {
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'google-sign-in-cancelled':
        return 'Sign-in was cancelled.';
      case 'google-sign-in-failed':
        return 'Google sign-in failed. Please try again.';
      case 'temporary-email-blocked':
        return 'Please use a common email provider (Gmail, Outlook, Yahoo, etc.) or sign in with Google.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      // Firebase may return various credential errors for wrong email/password
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password. Please check and try again.';
      case 'account-exists-with-different-credential':
        return 'Account exists with a different sign-in method.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';
      default:
        // Log unknown error codes for debugging
        debugPrint("⚠️ Unknown auth error code: $code - $message");
        return message ?? 'An authentication error occurred. Please try again.';
    }
  }

  /// Delete current user's account
  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) return;
      
      await user.delete();
      
      // Also sign out from Google
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      
      // Clear local data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('user_credits');
      await prefs.remove('last_credit_sync');
      
      debugPrint("✅ Account deleted successfully");
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Account deletion failed: ${e.code}");
      rethrow;
    }
  }
}

/// Custom Auth Exception for app-specific errors (Google Sign-In cancellation, etc.)
class AuthException implements Exception {
  final String code;
  final String? message;

  AuthException({required this.code, this.message});

  @override
  String toString() => 'AuthException: $code - $message';
}

