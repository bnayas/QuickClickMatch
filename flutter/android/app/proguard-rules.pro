# Keep Flutter's plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Preserve classes used by JSON (Moshi/Gson) reflection
-keep class com.google.gson.** { *; }
-keep class kotlinx.serialization.** { *; }
-keep class org.json.** { *; }

# Keep AWS Cognito models referenced via reflection
-keep class com.amazonaws.** { *; }
-keep class com.amazonaws.mobileconnectors.** { *; }
