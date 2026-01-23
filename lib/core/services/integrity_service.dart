// lib/core/services/integrity_service.dart
// 
// App Integrity Service - Detects tampering, hacking apps, and unauthorized modifications
// This service helps protect against:
// - APK signature tampering
// - Lucky Patcher and similar modding apps
// - Root/Jailbreak exploitation
// - Memory/runtime tampering (Frida, Xposed)
// - Debugger attachment
// - Emulator-based attacks

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of integrity check
enum IntegrityStatus {
  /// App passed all integrity checks
  passed,
  
  /// App signature has been modified (repackaged APK)
  signatureTampered,
  
  /// Hacking/modding apps detected (Lucky Patcher, etc.)
  hackingAppDetected,
  
  /// Device is rooted/jailbroken
  deviceCompromised,
  
  /// Debugger is attached
  debuggerAttached,
  
  /// Running on emulator (suspicious for production)
  emulatorDetected,
  
  /// Runtime manipulation detected (Frida, Xposed)
  runtimeTampered,
  
  /// Local data has been tampered with
  dataTampered,
  
  /// Unknown integrity issue
  unknown,
}

/// Detailed integrity check result
class IntegrityResult {
  final IntegrityStatus status;
  final String message;
  final String? details;
  final DateTime checkedAt;
  
  IntegrityResult({
    required this.status,
    required this.message,
    this.details,
  }) : checkedAt = DateTime.now();
  
  bool get passed => status == IntegrityStatus.passed;
  
  @override
  String toString() => 'IntegrityResult($status: $message)';
}

class IntegrityService {
  static IntegrityService? _instance;
  static IntegrityService get instance => _instance ??= IntegrityService._();
  
  IntegrityService._();
  
  // Expected app signature (SHA-256 of signing certificate)
  // IMPORTANT: Replace with your actual release signing certificate fingerprint
  // You can get this by running: keytool -list -v -keystore your-key.keystore
  // Or from Play Console: Setup > App signing > App signing key certificate
  static const String _expectedSignature = 'YOUR_RELEASE_SIGNATURE_SHA256';
  
  // Known package names of hacking/modding apps
  static const List<String> _knownHackingApps = [
    'com.chelpus.lackypatch',           // Lucky Patcher
    'com.dimonvideo.luckypatcher',      // Lucky Patcher variant
    'com.android.vending.billing.InAppBillingService.LUCK',
    'com.android.vending.billing.InAppBillingService.LACK',
    'com.forpda.lp',                    // LP variant
    'zone.jasi2169.uretpatcher',        // Uret Patcher
    'p.jasi2169.al3',                   // Jasi Patcher
    'com.android.protips',              // GameKiller
    'com.github.oauthsauce.hook',       // Hook framework
    'com.devadvance.rootcloak',         // Root Cloak
    'com.devadvance.rootcloakplus',     // Root Cloak Plus
    'de.robv.android.xposed.installer', // Xposed Installer
    'org.meowcat.edxposed.manager',     // EdXposed Manager
    'org.lsposed.manager',              // LSPosed Manager
    'com.saurik.substrate',             // Cydia Substrate
    'com.topjohnwu.magisk',             // Magisk Manager
    're.frida.server',                  // Frida Server
    'io.virtualapp',                    // VirtualApp (app cloning)
    'me.weishu.exp',                    // TaiChi (Xposed)
  ];
  
  // Known root-related paths
  static const List<String> _rootPaths = [
    '/system/app/Superuser.apk',
    '/system/xbin/su',
    '/system/bin/su',
    '/sbin/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/data/local/su',
    '/su/bin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/system/usr/we-need-root/su',
    '/system/xbin/busybox',
    '/sbin/busybox',
    '/system/bin/busybox',
    '/data/adb/magisk',
    '/data/adb/modules',
  ];
  
  // Cached result to avoid repeated checks
  IntegrityResult? _cachedResult;
  DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  /// Perform comprehensive integrity check
  /// Returns cached result if checked recently
  Future<IntegrityResult> checkIntegrity({bool forceRefresh = false}) async {
    // Return cached result if still valid
    if (!forceRefresh && 
        _cachedResult != null && 
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedResult!;
    }
    
    try {
      // Skip most checks in debug mode
      if (kDebugMode) {
        debugPrint('🔓 Integrity: Debug mode - skipping most checks');
        _cachedResult = IntegrityResult(
          status: IntegrityStatus.passed,
          message: 'Debug mode - checks skipped',
        );
        _lastCheckTime = DateTime.now();
        return _cachedResult!;
      }
      
      // 1. Check for debugger (even in release mode)
      if (await _isDebuggerAttached()) {
        return _setResult(IntegrityResult(
          status: IntegrityStatus.debuggerAttached,
          message: 'Security violation detected',
          details: 'Debugger attachment detected',
        ));
      }
      
      // Platform-specific checks
      if (Platform.isAndroid) {
        // 2. Check for hacking apps
        final hackingApp = await _detectHackingApps();
        if (hackingApp != null) {
          return _setResult(IntegrityResult(
            status: IntegrityStatus.hackingAppDetected,
            message: 'Unauthorized modification detected',
            details: 'Suspicious app: $hackingApp',
          ));
        }
        
        // 3. Check for root
        if (await _isDeviceRooted()) {
          // Note: Some users legitimately root their devices
          // You may choose to allow rooted devices but log it
          debugPrint('⚠️ Integrity: Rooted device detected');
          // Uncomment to block rooted devices:
          // return _setResult(IntegrityResult(
          //   status: IntegrityStatus.deviceCompromised,
          //   message: 'Device security compromised',
          //   details: 'Root access detected',
          // ));
        }
        
        // 4. Check app signature
        if (!await _verifyAppSignature()) {
          return _setResult(IntegrityResult(
            status: IntegrityStatus.signatureTampered,
            message: 'App verification failed',
            details: 'Application has been modified',
          ));
        }
        
        // 5. Check for Frida/Xposed hooks
        if (await _detectRuntimeManipulation()) {
          return _setResult(IntegrityResult(
            status: IntegrityStatus.runtimeTampered,
            message: 'Security violation detected',
            details: 'Runtime manipulation detected',
          ));
        }
      }
      
      if (Platform.isIOS) {
        // iOS-specific checks
        if (await _isJailbroken()) {
          debugPrint('⚠️ Integrity: Jailbroken device detected');
          // Uncomment to block jailbroken devices:
          // return _setResult(IntegrityResult(
          //   status: IntegrityStatus.deviceCompromised,
          //   message: 'Device security compromised',
          //   details: 'Jailbreak detected',
          // ));
        }
      }
      
      // 6. Check for emulator (optional - may block legitimate testers)
      if (await _isEmulator()) {
        debugPrint('⚠️ Integrity: Running on emulator');
        // Uncomment to block emulators:
        // return _setResult(IntegrityResult(
        //   status: IntegrityStatus.emulatorDetected,
        //   message: 'Unsupported environment',
        //   details: 'Running on emulator',
        // ));
      }
      
      // 7. Verify local data integrity
      if (!await _verifyDataIntegrity()) {
        return _setResult(IntegrityResult(
          status: IntegrityStatus.dataTampered,
          message: 'Data integrity check failed',
          details: 'Local storage has been modified',
        ));
      }
      
      // All checks passed
      return _setResult(IntegrityResult(
        status: IntegrityStatus.passed,
        message: 'Integrity verified',
      ));
      
    } catch (e, st) {
      debugPrint('⚠️ Integrity check error: $e\n$st');
      // On error, allow app to run but log the issue
      return _setResult(IntegrityResult(
        status: IntegrityStatus.passed,
        message: 'Check completed with warnings',
        details: e.toString(),
      ));
    }
  }
  
  IntegrityResult _setResult(IntegrityResult result) {
    _cachedResult = result;
    _lastCheckTime = DateTime.now();
    return result;
  }
  
  /// Check if debugger is attached
  Future<bool> _isDebuggerAttached() async {
    // In Flutter, we can check if assertions are enabled
    bool isDebugging = false;
    assert(() {
      isDebugging = true;
      return true;
    }());
    
    // Also check if profile mode
    if (kProfileMode) {
      return false; // Profile mode is OK for testing
    }
    
    return isDebugging && !kDebugMode;
  }
  
  /// Detect known hacking/modding apps
  Future<String?> _detectHackingApps() async {
    if (!Platform.isAndroid) return null;
    
    try {
      // Check if any hacking app packages are installed
      // This requires checking installed packages or app existence
      
      // Method 1: Check for specific files that hacking apps create
      final suspiciousFiles = [
        '/data/data/com.chelpus.lackypatch',
        '/data/data/com.dimonvideo.luckypatcher',
        '/data/data/zone.jasi2169.uretpatcher',
        '/data/data/com.topjohnwu.magisk',
      ];
      
      for (final path in suspiciousFiles) {
        if (await File(path).exists()) {
          return path.split('/').last;
        }
      }
      
      // Method 2: Check running processes (requires /proc access)
      // This is limited on newer Android versions
      
      return null;
    } catch (e) {
      debugPrint('⚠️ Hacking app detection error: $e');
      return null;
    }
  }
  
  /// Check if device is rooted
  Future<bool> _isDeviceRooted() async {
    if (!Platform.isAndroid) return false;
    
    try {
      // Check for root-related files
      for (final path in _rootPaths) {
        if (await File(path).exists()) {
          debugPrint('🔍 Root indicator found: $path');
          return true;
        }
      }
      
      // Check for root management apps
      final rootApps = [
        '/system/app/Superuser.apk',
        '/system/app/SuperSU.apk',
        '/system/app/Magisk.apk',
      ];
      
      for (final app in rootApps) {
        if (await File(app).exists()) {
          return true;
        }
      }
      
      // Try to execute 'su' command
      try {
        final result = await Process.run('which', ['su']);
        if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
          return true;
        }
      } catch (_) {
        // Command failed, likely not rooted
      }
      
      return false;
    } catch (e) {
      debugPrint('⚠️ Root detection error: $e');
      return false;
    }
  }
  
  /// Check if iOS device is jailbroken
  Future<bool> _isJailbroken() async {
    if (!Platform.isIOS) return false;
    
    try {
      // Check for jailbreak-related files
      final jailbreakPaths = [
        '/Applications/Cydia.app',
        '/Library/MobileSubstrate/MobileSubstrate.dylib',
        '/bin/bash',
        '/usr/sbin/sshd',
        '/etc/apt',
        '/private/var/lib/apt/',
        '/private/var/lib/cydia',
        '/private/var/stash',
        '/private/var/tmp/cydia.log',
        '/var/log/syslog',
        '/usr/libexec/sftp-server',
        '/usr/bin/sshd',
        '/bin/sh',
        '/etc/ssh/sshd_config',
        '/usr/libexec/ssh-keysign',
      ];
      
      for (final path in jailbreakPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
      
      // Check if app can write outside sandbox
      try {
        final file = File('/private/jailbreak_test.txt');
        await file.writeAsString('test');
        await file.delete();
        return true; // If we can write here, device is jailbroken
      } catch (_) {
        // Expected to fail on non-jailbroken devices
      }
      
      return false;
    } catch (e) {
      debugPrint('⚠️ Jailbreak detection error: $e');
      return false;
    }
  }
  
  /// Verify app signature hasn't been modified
  Future<bool> _verifyAppSignature() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      
      // In debug mode, skip signature check
      if (kDebugMode) return true;
      
      // Get the app's signature
      // Note: This requires platform channel implementation for full verification
      // For now, we verify the package name hasn't changed
      
      if (packageInfo.packageName != 'com.shambhutech.kalaai') {
        debugPrint('⚠️ Package name mismatch: ${packageInfo.packageName}');
        return false;
      }
      
      // TODO: Implement full signature verification via platform channel
      // This would compare the APK's signing certificate against expected value
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Signature verification error: $e');
      return true; // Allow on error to prevent false positives
    }
  }
  
  /// Detect Frida, Xposed, or other runtime manipulation
  Future<bool> _detectRuntimeManipulation() async {
    try {
      // Check for Frida
      // Frida typically opens a port on the device
      final fridaPorts = [27042, 27043, 27044, 27045];
      
      for (final port in fridaPorts) {
        try {
          final socket = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 100),
          );
          await socket.close();
          debugPrint('⚠️ Frida port open: $port');
          return true;
        } catch (_) {
          // Port closed, good
        }
      }
      
      // Check for Xposed framework
      if (Platform.isAndroid) {
        final xposedFiles = [
          '/system/framework/XposedBridge.jar',
          '/system/bin/app_process.orig',
          '/system/xposed.prop',
        ];
        
        for (final path in xposedFiles) {
          if (await File(path).exists()) {
            debugPrint('⚠️ Xposed indicator found: $path');
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('⚠️ Runtime manipulation detection error: $e');
      return false;
    }
  }
  
  /// Check if running on emulator
  Future<bool> _isEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        
        // Check for emulator indicators
        final indicators = [
          androidInfo.isPhysicalDevice == false,
          androidInfo.model.toLowerCase().contains('sdk'),
          androidInfo.model.toLowerCase().contains('emulator'),
          androidInfo.model.toLowerCase().contains('android sdk'),
          androidInfo.manufacturer.toLowerCase().contains('genymotion'),
          androidInfo.hardware.toLowerCase().contains('goldfish'),
          androidInfo.hardware.toLowerCase().contains('ranchu'),
          androidInfo.fingerprint.toLowerCase().contains('generic'),
          androidInfo.fingerprint.toLowerCase().contains('sdk'),
          androidInfo.product.toLowerCase().contains('sdk'),
        ];
        
        return indicators.any((indicator) => indicator);
      }
      
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
      
      return false;
    } catch (e) {
      debugPrint('⚠️ Emulator detection error: $e');
      return false;
    }
  }
  
  /// Verify local data hasn't been tampered with
  Future<bool> _verifyDataIntegrity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check for impossible values
      final credits = prefs.getInt('cached_credits');
      if (credits != null && credits > 1000000) {
        // Suspiciously high credit count
        debugPrint('⚠️ Suspicious credit count: $credits');
        return false;
      }
      
      // Verify integrity hash for sensitive data
      final storedHash = prefs.getString('_data_integrity_hash');
      if (storedHash != null) {
        final currentHash = await _computeDataHash();
        if (storedHash != currentHash) {
          debugPrint('⚠️ Data integrity hash mismatch');
          return false;
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Data integrity check error: $e');
      return true; // Allow on error
    }
  }
  
  /// Compute hash of sensitive data for integrity verification
  Future<String> _computeDataHash() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Include key values that shouldn't be tampered with
      final dataToHash = {
        'is_ad_free': prefs.getBool('is_ad_free') ?? false,
        'firebase_uid': prefs.getString('firebase_uid') ?? '',
        // Add other sensitive fields
      };
      
      final jsonStr = jsonEncode(dataToHash);
      final bytes = utf8.encode(jsonStr);
      final hash = sha256.convert(bytes);
      
      return hash.toString();
    } catch (e) {
      return '';
    }
  }
  
  /// Update data integrity hash after legitimate changes
  Future<void> updateDataIntegrityHash() async {
    try {
      final hash = await _computeDataHash();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('_data_integrity_hash', hash);
    } catch (e) {
      debugPrint('⚠️ Failed to update integrity hash: $e');
    }
  }
  
  /// Generate a secure device fingerprint for server verification
  Future<String> generateDeviceFingerprint() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final data = <String, dynamic>{};
      
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        data['platform'] = 'android';
        data['model'] = info.model;
        data['manufacturer'] = info.manufacturer;
        data['fingerprint'] = info.fingerprint;
        data['androidId'] = info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        data['platform'] = 'ios';
        data['model'] = info.model;
        data['name'] = info.name;
        data['systemVersion'] = info.systemVersion;
        data['identifierForVendor'] = info.identifierForVendor;
      }
      
      // Add timestamp to make replay attacks harder
      data['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      
      final jsonStr = jsonEncode(data);
      final bytes = utf8.encode(jsonStr);
      final hash = sha256.convert(bytes);
      
      return hash.toString();
    } catch (e) {
      debugPrint('⚠️ Failed to generate device fingerprint: $e');
      return '';
    }
  }
}
