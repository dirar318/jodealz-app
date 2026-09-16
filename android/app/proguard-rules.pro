# Flutter Wrapper rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# Firebase rules
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.internal.measurement.** { *; }
-dontwarn com.google.android.gms.internal.measurement.**

# Keep standard Kotlin classes
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Keep webview_flutter rules if needed
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class android.webkit.** { *; }

# Ignore Google Play Core warnings for deferred components since they are not used
-dontwarn com.google.android.play.core.**

