import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/main.dart' show initializeApp;

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const SplashScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _textController;
  late AnimationController _particleController;
  
  // Animations
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pulseAnimation;
  late Animation<double> _textSlide;
  late Animation<double> _textOpacity;
  late Animation<double> _taglineOpacity;
  
  // Particles for background effect
  final List<_Particle> _particles = [];
  
  // Track initialization state
  bool _animationsComplete = false;
  bool _initializationComplete = false;
  
  @override
  void initState() {
    super.initState();
    _initAnimations();
    _generateParticles();
    _startAnimationSequence();
    _runInitialization();
  }
  
  Future<void> _runInitialization() async {
    try {
      await initializeApp();
      _initializationComplete = true;
      _checkComplete();
    } catch (e) {
      debugPrint("⚠️ Initialization error: $e");
      // Still complete splash even if init fails - app can handle errors later
      _initializationComplete = true;
      _checkComplete();
    }
  }
  
  void _checkComplete() {
    if (_animationsComplete && _initializationComplete && mounted) {
      widget.onComplete();
    }
  }
  
  void _initAnimations() {
    // Logo entrance animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );
    
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    
    // Pulse animation (continuous)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Text animation
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _textSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
    
    // Particle animation
    _particleController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }
  
  void _generateParticles() {
    final random = math.Random();
    for (int i = 0; i < 20; i++) {
      _particles.add(_Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 4 + 2,
        speed: random.nextDouble() * 0.5 + 0.2,
        opacity: random.nextDouble() * 0.5 + 0.2,
      ));
    }
  }
  
  void _startAnimationSequence() async {
    // Start logo animation
    _logoController.forward();
    
    // Start pulse after logo appears
    await Future.delayed(const Duration(milliseconds: 600));
    _pulseController.repeat(reverse: true);
    
    // Start text animation
    await Future.delayed(const Duration(milliseconds: 300));
    _textController.forward();
    
    // Mark animations as complete after minimum display time
    await Future.delayed(const Duration(milliseconds: 1500));
    _animationsComplete = true;
    _checkComplete();
  }
  
  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _textController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D0D1A), // Deep dark
              Color(0xFF1A1A2E), // Surface dark
              Color(0xFF16162A), // Mid dark
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated particles background
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, child) {
                return CustomPaint(
                  size: size,
                  painter: _ParticlePainter(
                    particles: _particles,
                    progress: _particleController.value,
                  ),
                );
              },
            ),
            
            // Gradient orbs (decorative)
            Positioned(
              top: -100,
              right: -100,
              child: _buildGradientOrb(200, KalaColors.purple.withOpacity(0.15)),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: _buildGradientOrb(300, KalaColors.cyan.withOpacity(0.1)),
            ),
            
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with animations
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoController, _pulseController]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScale.value * _pulseAnimation.value,
                        child: Opacity(
                          opacity: _logoOpacity.value,
                          child: child,
                        ),
                      );
                    },
                    child: _buildAnimatedLogo(),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // App name with slide animation
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: Opacity(
                          opacity: _textOpacity.value,
                          child: child,
                        ),
                      );
                    },
                    child: _buildAppName(),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Tagline with fade animation
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _taglineOpacity.value,
                        child: child,
                      );
                    },
                    child: _buildTagline(),
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Loading indicator
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _taglineOpacity.value,
                        child: child,
                      );
                    },
                    child: _buildLoadingIndicator(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnimatedLogo() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KalaColors.purple.withOpacity(0.4),
            blurRadius: 40,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: KalaColors.cyan.withOpacity(0.3),
            blurRadius: 60,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              KalaColors.purple.withOpacity(0.2),
              KalaColors.cyan.withOpacity(0.1),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Image.asset(
              'assets/kala_ai_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAppName() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          KalaColors.purple,
          KalaColors.magenta,
          KalaColors.cyan,
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: const Text(
        'Kala AI',
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: Colors.white,
        ),
      ),
    );
  }
  
  Widget _buildTagline() {
    return Text(
      'Create with Intelligence',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
        color: Colors.white.withOpacity(0.6),
      ),
    );
  }
  
  Widget _buildLoadingIndicator() {
    return SizedBox(
      width: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 2000),
          builder: (context, value, child) {
            return LinearProgressIndicator(
              value: value,
              minHeight: 3,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.lerp(KalaColors.purple, KalaColors.cyan, value)!,
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildGradientOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

// Particle data class
class _Particle {
  double x;
  double y;
  final double size;
  final double speed;
  final double opacity;
  
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

// Particle painter for background effect
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  
  _ParticlePainter({
    required this.particles,
    required this.progress,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Update particle position
      final y = (particle.y + progress * particle.speed) % 1.0;
      
      final paint = Paint()
        ..color = Color.lerp(
          KalaColors.purple,
          KalaColors.cyan,
          particle.x,
        )!.withOpacity(particle.opacity * 0.6)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(particle.x * size.width, y * size.height),
        particle.size,
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

