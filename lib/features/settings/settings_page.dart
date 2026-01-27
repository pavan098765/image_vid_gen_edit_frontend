import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // Cache info
  String _thumbnailCacheSize = 'Calculating...';
  String _previewCacheSize = 'Calculating...';
  String _totalStorageUsed = 'Calculating...';

  // App info
  String _appVersion = '';
  String _buildNumber = '';

  // Loading states
  bool _isClearingCache = false;
  bool _isRefreshingCredits = false;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _calculateCacheSize();
    
    // Listen to global email verification status changes (from Credits page or other)
    emailVerifiedNotifier.addListener(_onEmailVerificationChanged);
  }
  
  void _onEmailVerificationChanged() {
    if (mounted) {
      setState(() {}); // Refresh UI to show verified badge
    }
  }
  
  @override
  void dispose() {
    emailVerifiedNotifier.removeListener(_onEmailVerificationChanged);
    super.dispose();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (e) {
      setState(() {
        _appVersion = '1.0.0';
        _buildNumber = '1';
      });
    }
  }

  Future<void> _calculateCacheSize() async {
    try {
      // Thumbnail cache
      final thumbDir = Directory(await ThumbnailService.instance.thumbnailDirPath);
      int thumbSize = 0;
      if (await thumbDir.exists()) {
        await for (final file in thumbDir.list(recursive: true)) {
          if (file is File) {
            thumbSize += await file.length();
          }
        }
      }

      // Preview cache
      final tempDir = await getTemporaryDirectory();
      int previewSize = 0;
      await for (final file in tempDir.list(recursive: false)) {
        if (file is File && file.path.contains('preview_')) {
          previewSize += await file.length();
        }
      }

      // Total app storage
      int totalSize = thumbSize + previewSize;

      setState(() {
        _thumbnailCacheSize = _formatBytes(thumbSize);
        _previewCacheSize = _formatBytes(previewSize);
        _totalStorageUsed = _formatBytes(totalSize);
      });
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
      setState(() {
        _thumbnailCacheSize = 'Unknown';
        _previewCacheSize = 'Unknown';
        _totalStorageUsed = 'Unknown';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _clearAllCache() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Cache',
      message:
          'This will clear all cached thumbnails and previews. Downloaded files in your gallery will not be affected.',
    );
    if (confirmed != true) return;

    setState(() => _isClearingCache = true);
    try {
      await ThumbnailService.instance.clearCache();
      await FileService.clearPreviewCache();
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    } finally {
      setState(() => _isClearingCache = false);
    }
  }

  Future<void> _deleteAllJobs() async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete All Jobs',
      message:
          'This will permanently delete all your job history. Downloaded files in your gallery will not be affected. This action cannot be undone.',
      isDangerous: true,
    );
    if (confirmed != true) return;

    try {
      // 🛡️ Mark all jobs as deleted so FCM won't recreate them
      final allJobIds = jobListNotifier.value.map((j) => j.jobId).toList();
      await markJobsAsDeleted(allJobIds);
      
      jobListNotifier.value = [];
      await saveJobsToPrefs();
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All jobs deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete jobs: $e')),
        );
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    bool isDangerous = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDangerous ? cs.error : cs.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: cs.primary)),
          ),
          GradientButton(
            label: isDangerous ? 'Delete' : 'Confirm',
            onPressed: () => Navigator.pop(context, true),
            variant: isDangerous ? ButtonVariant.danger : ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  void _showThemeSelector() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Theme',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _buildThemeOption(
                context,
                title: 'System Default',
                subtitle: 'Follow system theme',
                icon: LucideIcons.smartphone,
                mode: ThemeMode.system,
              ),
              _buildThemeOption(
                context,
                title: 'Light',
                subtitle: 'Always use light theme',
                icon: LucideIcons.sun,
                mode: ThemeMode.light,
              ),
              _buildThemeOption(
                context,
                title: 'Dark',
                subtitle: 'Always use dark theme',
                icon: LucideIcons.moon,
                mode: ThemeMode.dark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeMode mode,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = themeModeNotifier.value == mode;

    return Material(
      color:
          isSelected ? cs.primaryContainer.withOpacity(0.3) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: InkWell(
        onTap: () async {
          await AppSettings.setThemeMode(mode);
          Navigator.pop(context);
          // Force rebuild to show updated selection
          setState(() {});
        },
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? cs.primary : cs.onSurfaceVariant),
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
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) Icon(LucideIcons.check, color: cs.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // AUTHENTICATION METHODS
  // ============================================================

  void _showAuthSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AuthSheet(
        onSignInWithEmail: _handleEmailSignIn,
        onSignUpWithEmail: _handleEmailSignUp,
        onSignInWithGoogle: _handleGoogleSignIn,
        onForgotPassword: _handleForgotPassword,
      ),
    );
  }

  Future<void> _handleEmailSignIn(String email, String password) async {
    await _authService.signInWithEmail(email, password);
    
    // Sync with backend
    await _userService.syncUser(isNewSignUp: false);
    
    if (mounted) {
      Navigator.pop(context); // Close auth sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in successfully!')),
      );
      setState(() {}); // Refresh UI
    }
    // Errors will propagate to the _AuthSheet which shows them inline
  }

  Future<void> _handleEmailSignUp(String email, String password) async {
    await _authService.signUpWithEmail(email, password);
    
    // DO NOT sync for email sign-ups - wait until verification is complete
    // This prevents any credits from being granted before email is verified
    // syncUser will be called in _checkVerificationStatus after verification
    
    if (mounted) {
      Navigator.pop(context); // Close auth sheet
      
      // UI will now show verification pending state in _buildAccountTile
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please verify your email to get 50 free credits!')),
      );
      setState(() {}); // Refresh UI to show verification pending state
    }
    // Errors will propagate to the _AuthSheet which shows them inline
  }

  /// Resend verification email
  Future<void> _resendVerificationEmail() async {
    try {
      await _authService.resendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  /// Check verification status and grant credits if verified
  Future<void> _checkVerificationStatus() async {
    try {
      await _authService.reloadUser();
      
      if (_authService.isEmailVerified) {
        // IMPORTANT: Force refresh the ID token to get updated email_verified claim
        // Without this, the server might still see email_verified=false in the cached token
        await _authService.forceRefreshToken();
        
        // Email verified! Now sync with isNewSignUp to grant credits
        await _userService.syncUser(isNewSignUp: true);
        
        // Notify all other pages about verification status change
        notifyEmailVerificationChanged(true);
        
        if (mounted) {
          _showVerificationSuccessDialog();
          setState(() {}); // Refresh UI to show verified badge
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email not verified yet. Please check your inbox and click the link.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  /// Shows success dialog after email verification with credits
  void _showVerificationSuccessDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: KalaColors.brandGradient),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.gift, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Welcome!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            Text(
              'Email Verified!',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You\'ve received',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: KalaColors.brandGradient,
              ).createShader(bounds),
              child: const Text(
                '50 Free Credits',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          GradientButton(
            label: 'Start Creating',
            icon: LucideIcons.sparkles,
            onPressed: () => Navigator.pop(context),
            variant: ButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    final credential = await _authService.signInWithGoogle();
    final isNew = await _authService.isNewUser(credential);
    
    // Sync with backend - Google emails are pre-verified so bonus is granted immediately
    await _userService.syncUser(isNewSignUp: isNew);
    
    if (mounted) {
      Navigator.pop(context); // Close auth sheet
      
      // Show bonus message for new users (Google emails are already verified)
      if (isNew) {
        _showGoogleSignUpSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in with Google!')),
        );
      }
      setState(() {}); // Refresh UI
    }
    // Errors will propagate to the _AuthSheet which shows them inline
  }

  /// Success dialog for Google sign-up (emails are pre-verified)
  void _showGoogleSignUpSuccessDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: KalaColors.brandGradient),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.gift, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Welcome!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You\'ve received',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: KalaColors.brandGradient,
              ).createShader(bounds),
              child: const Text(
                '50 Free Credits',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          GradientButton(
            label: 'Start Creating',
            icon: LucideIcons.sparkles,
            onPressed: () => Navigator.pop(context),
            variant: ButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  Future<void> _handleForgotPassword(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthService.getErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await _showConfirmDialog(
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
    );
    if (confirmed != true) return;

    try {
      await _authService.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    }
  }

  Future<void> _refreshCredits() async {
    if (!_authService.isSignedIn) return;
    
    setState(() => _isRefreshingCredits = true);
    try {
      await _userService.refreshCredits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credits refreshed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh credits: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingCredits = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
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

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
          backgroundColor: cs.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      body: StreamBuilder<User?>(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          final isSignedIn = snapshot.data != null;
          
          return ListView(
            padding: const EdgeInsets.all(AppStyles.spacing16),
            children: [
              // Account Section
              _buildSectionHeader(context, 'Account', LucideIcons.user),
              _buildCard(
                context,
                children: [
                  if (isSignedIn) ...[
                    _buildAccountTile(context),
                    _buildDivider(cs),
                    // Credits row
                    _buildCreditsTile(context),
                    _buildDivider(cs),
                    _buildSettingsTile(
                      context,
                      icon: LucideIcons.logOut,
                      title: 'Sign Out',
                      subtitle: 'Sign out of your account',
                      onTap: _signOut,
                      iconColor: cs.error,
                    ),
                  ] else
                    _buildSignInTile(context),
                ],
              ),
              const SizedBox(height: AppStyles.spacing20),

              // Appearance Section
              _buildSectionHeader(context, 'Appearance', LucideIcons.palette),
              _buildCard(
                context,
                children: [
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.sun,
                    title: 'Theme',
                    subtitle: _getThemeName(),
                    onTap: _showThemeSelector,
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacing20),

              // Preferences Section
              _buildSectionHeader(context, 'Preferences', LucideIcons.settings),
              _buildCard(
                context,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: LucideIcons.zap,
                    title: 'High Quality Previews',
                    subtitle: 'Load full resolution in preview (uses more data)',
                    value: AppSettings.highQualityPreviews,
                    onChanged: (value) async {
                      await AppSettings.setHighQualityPreviews(value);
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacing20),

              // Storage & Cache Section
              _buildSectionHeader(context, 'Storage & Cache', LucideIcons.hardDrive),
              _buildCard(
                context,
                children: [
                  _buildInfoTile(
                    context,
                    icon: LucideIcons.database,
                    title: 'Total Storage Used',
                    value: _totalStorageUsed,
                  ),
                  _buildDivider(cs),
                  _buildInfoTile(
                    context,
                    icon: LucideIcons.image,
                    title: 'Thumbnail Cache',
                    value: _thumbnailCacheSize,
                  ),
                  _buildDivider(cs),
                  _buildInfoTile(
                    context,
                    icon: LucideIcons.eye,
                    title: 'Preview Cache',
                    value: _previewCacheSize,
                  ),
                  _buildDivider(cs),
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.trash2,
                    title: 'Clear All Cache',
                    subtitle: 'Free up storage space',
                    onTap: _isClearingCache ? null : _clearAllCache,
                    trailing: _isClearingCache
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacing20),

              // Data Section
              _buildSectionHeader(context, 'Data Management', LucideIcons.folderCog),
              _buildCard(
                context,
                children: [
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.trash,
                    title: 'Delete All Jobs',
                    subtitle: 'Permanently delete all job history',
                    onTap: _deleteAllJobs,
                    iconColor: cs.error,
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacing20),

              // About Section
              _buildSectionHeader(context, 'About', LucideIcons.info),
              _buildCard(
                context,
                children: [
                  _buildInfoTile(
                    context,
                    icon: LucideIcons.package,
                    title: 'Version',
                    value: '$_appVersion ($_buildNumber)',
                  ),
                  _buildDivider(cs),
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.fileText,
                    title: 'Terms of Service',
                    subtitle: 'Read our terms',
                    onTap: () => _showLegalDocument(
                      title: 'Terms of Service',
                      rawUrl: 'https://pastebin.com/raw/bprTSU66',
                    ),
                  ),
                  _buildDivider(cs),
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.shield,
                    title: 'Privacy Policy',
                    subtitle: 'How we handle your data',
                    onTap: () => _showLegalDocument(
                      title: 'Privacy Policy',
                      rawUrl: 'https://pastebin.com/raw/66qXZNSW',
                    ),
                  ),
                  _buildDivider(cs),
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.star,
                    title: 'Rate the App',
                    subtitle: 'Help us improve with your feedback',
                    onTap: () => _openUrl('https://play.google.com/store/apps'),
                  ),
                  _buildDivider(cs),
                  _buildSettingsTile(
                    context,
                    icon: LucideIcons.mail,
                    title: 'Contact Support',
                    subtitle: 'Get help or report issues',
                    onTap: () => _openUrl('mailto:support@example.com'),
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacing32),

              // Footer with Kala AI branding
              Center(
                child: Column(
                  children: [
                    // Logo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/kala_ai_logo.png',
                        width: 64,
                        height: 64,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Brand name with gradient
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: KalaColors.brandGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'Kala AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create Images & Videos with AI',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Made with ❤️',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppStyles.spacing24),
            ],
          );
        },
      ),
      ),
    );
  }

  String _getThemeName() {
    switch (themeModeNotifier.value) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
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
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: AppStyles.cardDecoration(cs),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildDivider(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      color: cs.outlineVariant.withOpacity(0.15),
    );
  }

  Widget _buildAccountTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawUserName = _authService.userName;
    final userName = (rawUserName == null || rawUserName.isEmpty) ? 'User' : rawUserName;
    final userEmail = _authService.userEmail ?? '';
    final photoUrl = _authService.userPhotoUrl;
    final isVerified = _authService.isEmailVerified;

    // Show verification pending UI inline if not verified
    if (!isVerified) {
      return _buildVerificationPendingTile(context, userName, userEmail, photoUrl);
    }

    return Padding(
      padding: const EdgeInsets.all(AppStyles.spacing16),
      child: Row(
        children: [
          // Avatar
          _buildAvatar(cs, userName, photoUrl),
          const SizedBox(width: AppStyles.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  userEmail,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Verified badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.checkCircle, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Verified',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ColorScheme cs, String userName, String? photoUrl) {
    // Safely get the first character, fallback to 'U' if empty
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';
    
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: photoUrl == null
            ? LinearGradient(
                colors: [cs.primary, cs.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        shape: BoxShape.circle,
        image: photoUrl != null
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: photoUrl == null
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildVerificationPendingTile(
    BuildContext context,
    String userName,
    String userEmail,
    String? photoUrl,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppStyles.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info row
          Row(
            children: [
              _buildAvatar(cs, userName, photoUrl),
              const SizedBox(width: AppStyles.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      userEmail,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Pending badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertCircle, color: Colors.orange, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Pending',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Verification reminder card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KalaColors.gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              border: Border.all(color: KalaColors.gold.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.gift, color: KalaColors.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verify your email to get 50 free credits!',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Check your inbox and click the verification link, then tap "I\'ve Verified" below.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        label: "I've Verified",
                        icon: LucideIcons.checkCircle,
                        onPressed: _checkVerificationStatus,
                        variant: ButtonVariant.primary,
                        size: ButtonSize.small,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _resendVerificationEmail,
                      icon: const Icon(LucideIcons.refreshCw, size: 14),
                      label: const Text('Resend'),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditsTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return ValueListenableBuilder<int>(
      valueListenable: userCreditsNotifier,
      builder: (context, credits, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _refreshCredits,
            child: Padding(
              padding: const EdgeInsets.all(AppStyles.spacing16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppStyles.spacing10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: KalaColors.brandGradient),
                      borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                    ),
                    child: const Icon(LucideIcons.gem, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: AppStyles.spacing16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Balance',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to refresh',
                          style: TextStyle(
                            color: cs.onSurfaceVariant.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isRefreshingCredits)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: KalaColors.brandGradient,
                      ).createShader(bounds),
                      child: Text(
                        '$credits',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignInTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _showAuthSheet,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.all(AppStyles.spacing16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: KalaColors.brandGradient),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.userPlus,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: AppStyles.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign In / Sign Up',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    children: [
                      Icon(LucideIcons.gift, size: 14, color: KalaColors.gold),
                      SizedBox(width: 4),
                      Text(
                        '50 free credits on signup!',
                        style: TextStyle(
                          color: KalaColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: cs.primary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppStyles.spacing16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppStyles.spacing10),
                decoration: BoxDecoration(
                  color: (iconColor ?? cs.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? cs.primary),
              ),
              const SizedBox(width: AppStyles.spacing16),
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: cs.onSurfaceVariant.withOpacity(0.5),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppStyles.spacing16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppStyles.spacing10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppStyles.radiusSm),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: AppStyles.spacing16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppStyles.spacing16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppStyles.spacing10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppStyles.radiusSm),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: AppStyles.spacing16),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: cs.primary,
          ),
        ],
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

// =============================================================================
// Authentication Sheet with Email/Password and Google Sign-In
// =============================================================================

class _AuthSheet extends StatefulWidget {
  final Future<void> Function(String email, String password) onSignInWithEmail;
  final Future<void> Function(String email, String password) onSignUpWithEmail;
  final Future<void> Function() onSignInWithGoogle;
  final Future<void> Function(String email) onForgotPassword;

  const _AuthSheet({
    required this.onSignInWithEmail,
    required this.onSignUpWithEmail,
    required this.onSignInWithGoogle,
    required this.onForgotPassword,
  });

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showForgotPassword = false;
  String? _errorMessage; // Error message to display inline

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null; // Clear previous error
    });
    
    try {
      if (_showForgotPassword) {
        await widget.onForgotPassword(_emailController.text);
        setState(() => _showForgotPassword = false);
      } else if (_isSignUp) {
        await widget.onSignUpWithEmail(_emailController.text, _passwordController.text);
      } else {
        await widget.onSignInWithEmail(_emailController.text, _passwordController.text);
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = AuthService.getErrorMessage(e);
        debugPrint("❌ Auth error in settings: $errorMsg");
        setState(() => _errorMessage = errorMsg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.onSignInWithGoogle();
    } catch (e) {
      if (mounted) {
        final errorMsg = AuthService.getErrorMessage(e);
        debugPrint("❌ Google sign-in error in settings: $errorMsg");
        setState(() => _errorMessage = errorMsg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        // Account for both keyboard and device safe area (home bar/navigation)
        bottom: keyboardPadding + bottomSafeArea + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showForgotPassword 
                            ? 'Reset Password'
                            : (_isSignUp ? 'Create Account' : 'Welcome Back'),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isSignUp && !_showForgotPassword) ...[
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(LucideIcons.gift, size: 16, color: KalaColors.gold),
                            SizedBox(width: 4),
                            Text(
                              '50 free credits on signup!',
                              style: TextStyle(
                                color: KalaColors.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _showForgotPassword
                    ? 'Enter your email to receive a reset link'
                    : (_isSignUp
                        ? 'Sign up to sync your work and use AI tools'
                        : 'Sign in to access your account'),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              
              // Error message display (inline, visible above the form)
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.alertCircle, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Google Sign-In Button (only show if not forgot password)
              if (!_showForgotPassword) ...[
                _GoogleSignInButton(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 16),
                
                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: Divider(color: cs.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Email Field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: _showForgotPassword 
                    ? TextInputAction.done 
                    : TextInputAction.next,
                decoration: AppStyles.inputDecoration(
                  cs,
                  hintText: 'Email address',
                  prefixIcon: LucideIcons.mail,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Please enter a valid email';
                  }
                  // Only allow trusted email providers on sign-up
                  if (_isSignUp && !AuthService.isAllowedEmailDomain(value)) {
                    return 'Use Gmail, Outlook, Yahoo etc. or Google Sign-In';
                  }
                  return null;
                },
              ),

              // Password Fields (hide for forgot password)
              if (!_showForgotPassword) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction:
                      _isSignUp ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: _isSignUp ? null : (_) => _submit(),
                  decoration: AppStyles.inputDecoration(
                    cs,
                    hintText: 'Password',
                    prefixIcon: LucideIcons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                // Confirm Password (Sign Up only)
                if (_isSignUp) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: AppStyles.inputDecoration(
                      cs,
                      hintText: 'Confirm password',
                      prefixIcon: LucideIcons.lock,
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],

                // Forgot Password Link
                if (!_isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _showForgotPassword = true),
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(color: cs.primary),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),

              // Submit Button
              GradientButton(
                label: _isLoading 
                    ? null 
                    : (_showForgotPassword 
                        ? 'Send Reset Link'
                        : (_isSignUp ? 'Create Account' : 'Sign In')),
                icon: _showForgotPassword 
                    ? LucideIcons.mail 
                    : (_isSignUp ? LucideIcons.userPlus : LucideIcons.logIn),
                onPressed: _isLoading ? null : _submit,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
                expanded: true,
                child: _isLoading
                    ? SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.25),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),

              // Toggle Sign In / Sign Up / Back from Forgot Password
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_showForgotPassword) ...[
                    TextButton(
                      onPressed: () => setState(() => _showForgotPassword = false),
                      child: Text(
                        '← Back to Sign In',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      _isSignUp
                          ? 'Already have an account?'
                          : "Don't have an account?",
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp ? 'Sign In' : 'Sign Up',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Google Sign-In Button
// =============================================================================

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GoogleSignInButton({
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 90,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: cs.primary,
                      backgroundColor: cs.primary.withOpacity(0.15),
                    ),
                  ),
                )
              else ...[
                // Google logo
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
