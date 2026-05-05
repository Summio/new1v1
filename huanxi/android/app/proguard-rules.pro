# Flutter default rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Play Store split compatibility (referenced but not used without Play Services)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Agora SDK
-keep class io.agora.** { *; }