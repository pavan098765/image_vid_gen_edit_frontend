# FFmpeg Kit - keep all JNI classes and native method bindings
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# Keep FFmpeg Kit callback interfaces (called from native code via JNI)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Media Kit - keep native bindings
-keep class com.alexmercerind.** { *; }

# Flutter plugins - don't strip plugin registrant classes
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep all Flutter-related annotations
-keepattributes *Annotation*

# Firebase
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class io.flutter.plugins.googlemobileads.** { *; }

# General: keep native methods across all classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter embedding references Play Core (deferred components); suppress if not used
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# TensorFlow Lite GPU delegate classes (release + R8)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
