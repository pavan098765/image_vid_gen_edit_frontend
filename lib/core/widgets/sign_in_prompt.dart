// lib/core/widgets/sign_in_prompt.dart
import 'package:firebase_auth/firebase_auth.dart' show UserCredential;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// A widget that prompts users to sign in to use AI tools
/// Shows benefits of signing up (free credits, sync, etc.)
class SignInPromptCard extends StatelessWidget {
  final VoidCallback? onSignInTap;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const SignInPromptCard({
    super.key,
    this.onSignInTap,
    this.showCloseButton = true,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
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
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: KalaColors.brandGradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sign in to use AI Tools',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(LucideIcons.gift, size: 14, color: KalaColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          '50 free credits on signup!',
                          style: TextStyle(
                            color: KalaColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showCloseButton)
                IconButton(
                  icon: Icon(LucideIcons.x, color: cs.onSurfaceVariant, size: 20),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Benefits list
          _BenefitRow(
            icon: LucideIcons.zap,
            text: 'Access all AI image & video tools',
          ),
          const SizedBox(height: 8),
          _BenefitRow(
            icon: LucideIcons.cloud,
            text: 'Sync your work across devices',
          ),
          const SizedBox(height: 8),
          _BenefitRow(
            icon: LucideIcons.shield,
            text: 'Secure cloud processing',
          ),
          const SizedBox(height: 20),

          // Sign in button
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Sign In / Sign Up',
              icon: LucideIcons.logIn,
              onPressed: onSignInTap,
              variant: ButtonVariant.primary,
              size: ButtonSize.large,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Row(
      children: [
        Icon(icon, size: 16, color: KalaColors.cyan),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: cs.onSurface.withOpacity(0.8),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

/// Screen states for sign-in flow
enum _SignInScreenState {
  showingOptions,         // Default: show sign-in/up options
  pendingVerification,    // Email sign-up done, awaiting verification
  verified,               // Verification complete, show success
}

/// A full-screen sign in prompt (shown when trying to use AI tools without auth)
class SignInRequiredScreen extends StatefulWidget {
  final String? feature;
  final VoidCallback? onSignInSuccess;

  const SignInRequiredScreen({
    super.key,
    this.feature,
    this.onSignInSuccess,
  });

  @override
  State<SignInRequiredScreen> createState() => _SignInRequiredScreenState();
}

class _SignInRequiredScreenState extends State<SignInRequiredScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  bool _isLoading = false;
  
  // State management for verification flow
  _SignInScreenState _screenState = _SignInScreenState.showingOptions;
  String? _pendingVerificationEmail;
  bool _isCheckingVerification = false;
  bool _isResendingEmail = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final credential = await _authService.signInWithGoogle();
      final isNew = await _authService.isNewUser(credential);
      
      // Google emails are pre-verified, so sync with isNewSignUp
      await _userService.syncUser(isNewSignUp: isNew);
      await SignInPromptManager.resetPrompts();
      
      if (mounted) {
        if (isNew) {
          // Show success inline (Google is already verified)
          setState(() => _screenState = _SignInScreenState.verified);
        } else {
          widget.onSignInSuccess?.call();
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthService.getErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEmailAuthSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _EmailAuthSheet(
        onSuccess: (isNew, email) async {
          if (mounted) {
            Navigator.pop(sheetContext); // Close sheet
            
            if (isNew && email != null) {
              // Email sign-up: show inline verification UI (don't grant credits yet)
              // Note: syncUser was called but isNewSignUp was true - backend should check email_verified
              setState(() {
                _pendingVerificationEmail = email;
                _screenState = _SignInScreenState.pendingVerification;
              });
            } else {
              // Sign-in (not new) - already verified
              await SignInPromptManager.resetPrompts();
              widget.onSignInSuccess?.call();
              Navigator.pop(context, true);
            }
          }
        },
      ),
    );
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResendingEmail = true);
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
    } finally {
      if (mounted) setState(() => _isResendingEmail = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() => _isCheckingVerification = true);
    try {
      // Reload user to get latest email verification status
      await _authService.reloadUser();
      
      if (_authService.isEmailVerified) {
        // IMPORTANT: Force refresh the ID token to get updated email_verified claim
        // Without this, the server might still see email_verified=false in the cached token
        await _authService.forceRefreshToken();
        
        // Email verified! Now sync with isNewSignUp to grant credits
        await _userService.syncUser(isNewSignUp: true);
        await SignInPromptManager.resetPrompts();
        
        if (mounted) {
          setState(() => _screenState = _SignInScreenState.verified);
        }
      } else {
        // Email still not verified
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
    } finally {
      if (mounted) setState(() => _isCheckingVerification = false);
    }
  }

  void _cancelVerification() async {
    // Sign out and go back to sign-in options
    await _authService.signOut();
    if (mounted) {
      setState(() {
        _screenState = _SignInScreenState.showingOptions;
        _pendingVerificationEmail = null;
      });
    }
  }

  void _finishSuccess() {
    widget.onSignInSuccess?.call();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: _screenState == _SignInScreenState.showingOptions
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context, false),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + bottomSafeArea,
          ),
          child: _buildContent(cs),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    switch (_screenState) {
      case _SignInScreenState.showingOptions:
        return _buildSignInOptions(cs);
      case _SignInScreenState.pendingVerification:
        return _buildPendingVerification(cs);
      case _SignInScreenState.verified:
        return _buildVerifiedSuccess(cs);
    }
  }

  Widget _buildSignInOptions(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        // Logo
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                KalaColors.purple.withOpacity(0.2),
                KalaColors.cyan.withOpacity(0.1),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/kala_ai_logo.png',
              width: 80,
              height: 80,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Title
        Text(
          'Sign in to continue',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        
        if (widget.feature != null)
          Text(
            'Sign in is required to use ${widget.feature}',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 8),

        // Bonus callout
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: KalaColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KalaColors.gold.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.gift, size: 18, color: KalaColors.gold),
              const SizedBox(width: 8),
              Text(
                '50 free credits on signup!',
                style: TextStyle(
                  color: KalaColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Google Sign-In Button
        SizedBox(
          width: double.infinity,
          child: _GoogleSignInButton(
            onPressed: _isLoading ? null : _handleGoogleSignIn,
            isLoading: _isLoading,
          ),
        ),
        const SizedBox(height: 16),

        // Email Sign-In Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _showEmailAuthSheet,
            icon: const Icon(LucideIcons.mail),
            label: const Text('Continue with Email'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Benefits
        Text(
          'Why sign in?',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _BenefitRow(icon: LucideIcons.zap, text: 'Access all AI tools'),
        const SizedBox(height: 8),
        _BenefitRow(icon: LucideIcons.cloud, text: 'Sync across devices'),
        const SizedBox(height: 8),
        _BenefitRow(icon: LucideIcons.shield, text: 'Secure processing'),
      ],
    );
  }

  Widget _buildPendingVerification(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        // Mail icon
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: KalaColors.cyan.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.mailCheck,
            size: 64,
            color: KalaColors.cyan,
          ),
        ),
        const SizedBox(height: 24),

        // Title
        Text(
          'Verify Your Email',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Bonus reminder
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KalaColors.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
            border: Border.all(color: KalaColors.gold.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.gift, color: KalaColors.gold, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Verify your email to receive 50 free credits!',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Email info
        Text(
          'We\'ve sent a verification link to:',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _pendingVerificationEmail ?? '',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Click the link in the email, then tap "I\'ve Verified" below.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 32),

        // I've Verified Button
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: _isCheckingVerification ? 'Checking...' : "I've Verified My Email",
            icon: LucideIcons.checkCircle,
            onPressed: _isCheckingVerification ? null : _checkVerification,
            variant: ButtonVariant.primary,
            size: ButtonSize.large,
            expanded: true,
          ),
        ),
        const SizedBox(height: 16),

        // Resend email
        TextButton.icon(
          onPressed: _isResendingEmail ? null : _resendVerificationEmail,
          icon: _isResendingEmail 
              ? const SizedBox(
                  width: 16, 
                  height: 16, 
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(_isResendingEmail ? 'Sending...' : 'Resend Verification Email'),
        ),
        const SizedBox(height: 8),

        // Cancel / Start over
        TextButton(
          onPressed: _cancelVerification,
          child: Text(
            'Cancel & Start Over',
            style: TextStyle(
              color: cs.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerifiedSuccess(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        // Success icon
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: KalaColors.brandGradient),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.gift,
            size: 64,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),

        // Verified badge (if email verification was done)
        if (_pendingVerificationEmail != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.checkCircle2, size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Text(
                  'Email Verified!',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Welcome title
        Text(
          'Welcome!',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'You\'ve received',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),

        // Credits amount
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: KalaColors.brandGradient,
          ).createShader(bounds),
          child: const Text(
            '50 Free Credits',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 40),

        // Start creating button - centered
        Center(
          child: GradientButton(
            label: 'Start Creating',
            icon: LucideIcons.sparkles,
            onPressed: _finishSuccess,
            variant: ButtonVariant.primary,
            size: ButtonSize.large,
          ),
        ),
      ],
    );
  }
}

/// Google Sign-In Button
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
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              else ...[
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

/// Email Auth Bottom Sheet
class _EmailAuthSheet extends StatefulWidget {
  final Future<void> Function(bool isNew, String? email) onSuccess;

  const _EmailAuthSheet({required this.onSuccess});

  @override
  State<_EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<_EmailAuthSheet> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
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
      UserCredential credential;
      bool isNew;
      final email = _emailController.text.trim();
      
      if (_isSignUp) {
        credential = await _authService.signUpWithEmail(
          email,
          _passwordController.text,
        );
        isNew = true;
        // DO NOT sync for email sign-ups - wait until verification is complete
        // This prevents any credits from being granted before email is verified
      } else {
        credential = await _authService.signInWithEmail(
          email,
          _passwordController.text,
        );
        isNew = await _authService.isNewUser(credential);
        // For sign-in: sync normally (user already exists)
        await _userService.syncUser(isNewSignUp: false);
      }
      
      // Pass email only for new sign-ups (to show verification UI)
      await widget.onSuccess(isNew, isNew ? email : null);
    } catch (e) {
      if (mounted) {
        final errorMsg = AuthService.getErrorMessage(e);
        debugPrint("❌ Auth error shown to user: $errorMsg");
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isSignUp ? 'Create Account' : 'Sign In',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
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
              const SizedBox(height: 20),

              // Email Field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: AppStyles.inputDecoration(
                  cs,
                  hintText: 'Email',
                  prefixIcon: LucideIcons.mail,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter email';
                  if (!v.contains('@')) return 'Invalid email';
                  // Only allow trusted email providers on sign-up
                  if (_isSignUp && !AuthService.isAllowedEmailDomain(v)) {
                    return 'Use Gmail, Outlook, Yahoo etc. or Google Sign-In';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Password Field
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: AppStyles.inputDecoration(
                  cs,
                  hintText: 'Password',
                  prefixIcon: LucideIcons.lock,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter password';
                  if (v.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),

              if (_isSignUp) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  decoration: AppStyles.inputDecoration(
                    cs,
                    hintText: 'Confirm password',
                    prefixIcon: LucideIcons.lock,
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) return 'Passwords don\'t match';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 20),

              GradientButton(
                label: _isLoading ? null : (_isSignUp ? 'Create Account' : 'Sign In'),
                onPressed: _isLoading ? null : _submit,
                variant: ButtonVariant.primary,
                expanded: true,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp ? 'Have an account?' : 'No account?',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp ? 'Sign In' : 'Sign Up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper function to check if sign-in is required and show prompt
Future<bool> requireSignIn(BuildContext context, {String? feature}) async {
  if (AuthService().isSignedIn) {
    return true;
  }

  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => SignInRequiredScreen(feature: feature),
      fullscreenDialog: true,
    ),
  );

  return result ?? false;
}
