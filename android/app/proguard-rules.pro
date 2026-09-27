# The Flutter Gradle plugin adds the rules the Flutter embedding needs, and
# Firebase, WebView and the other plugins ship their own consumer rules, so
# broad "-keep class x.**" rules are not needed here (they only bloat the APK).

# Flutter references Play Core for deferred components, which this app does not use.
-dontwarn com.google.android.play.core.**
