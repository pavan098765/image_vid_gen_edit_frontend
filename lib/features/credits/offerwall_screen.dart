import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/adgem_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Offerwall screen displaying AdGem offers in a WebView
/// 
/// Users can complete offers (app installs, registrations, etc.) to earn free gems.
/// Credits are awarded automatically via server postback when offers are completed.
class OfferwallScreen extends StatefulWidget {
  /// Callback when user returns from offerwall (to refresh credits)
  final VoidCallback? onReturn;
  
  const OfferwallScreen({super.key, this.onReturn});

  @override
  State<OfferwallScreen> createState() => _OfferwallScreenState();
}

class _OfferwallScreenState extends State<OfferwallScreen> {
  final AdGemService _adGemService = AdGemService();
  
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  double _loadingProgress = 0;
  
  @override
  void initState() {
    super.initState();
    _initWebView();
  }
  
  void _initWebView() {
    final offerwallUrl = _adGemService.getOfferwallUrl();
    
    if (offerwallUrl == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please sign in to access offers';
        _isLoading = false;
      });
      return;
    }
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadingProgress = 0;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress / 100;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('🔴 WebView error: ${error.description}');
            // Only show error for main frame errors
            if (error.isForMainFrame ?? false) {
              setState(() {
                _hasError = true;
                _errorMessage = 'Failed to load offers. Please check your connection.';
                _isLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            debugPrint('🔗 Navigation request: $url');
            
            // Handle external links (app stores, etc.)
            if (_shouldOpenExternally(url)) {
              _openExternalUrl(url);
              return NavigationDecision.prevent;
            }
            
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(offerwallUrl));
  }
  
  /// Check if URL should be opened in external browser/app store
  bool _shouldOpenExternally(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    
    // Open app store links externally
    if (url.contains('play.google.com') ||
        url.contains('apps.apple.com') ||
        url.contains('itunes.apple.com') ||
        url.contains('market://') ||
        url.contains('itms-apps://')) {
      return true;
    }
    
    // Open deep links externally
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return true;
    }
    
    return false;
  }
  
  /// Open URL in external browser or app
  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('🔴 Failed to launch URL: $e');
    }
  }
  
  /// Refresh the offerwall
  Future<void> _refresh() async {
    final offerwallUrl = _adGemService.getOfferwallUrl();
    if (offerwallUrl != null) {
      setState(() {
        _hasError = false;
        _isLoading = true;
      });
      await _controller.loadRequest(Uri.parse(offerwallUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Notify parent to refresh credits when leaving
        widget.onReturn?.call();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: KalaColors.brandGradient),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.gift, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'Free Gems',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Column(
          children: [
            // Loading progress bar
            if (_isLoading)
              LinearProgressIndicator(
                value: _loadingProgress > 0 ? _loadingProgress : null,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            
            // Info banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    KalaColors.purple.withOpacity(0.1),
                    KalaColors.cyan.withOpacity(0.05),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Complete offers to earn free gems. Credits may take a few minutes to appear.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // WebView or Error state
            Expanded(
              child: _hasError
                  ? _buildErrorState(cs)
                  : Stack(
                      children: [
                        // Add bottom padding for system navigation bar
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom,
                          ),
                          child: WebViewWidget(controller: _controller),
                        ),
                        
                        // Loading overlay
                        if (_isLoading && _loadingProgress < 0.5)
                          Container(
                            color: cs.surface,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: cs.primary),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading offers...',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
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
  
  Widget _buildErrorState(ColorScheme cs) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + bottomPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.wifiOff,
                size: 48,
                color: cs.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Could not load offers',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Please check your internet connection and try again.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
