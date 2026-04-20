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

# mt_plugin - dontwarn missing classes
-dontwarn com.toivan.mtcamera.mt_plugin.**
-keep class com.toivan.mtcamera.mt_plugin.** { *; }

# Agora SDK
-keep class io.agora.** { *; }

# FaceBeauty SDK
-keep class com.nimo.facebeauty.** { *; }
-dontwarn com.nimo.facebeauty.**
