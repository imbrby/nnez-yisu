# Flutter-specific ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-keep class com.brby.yisu.CanteenWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }

# Widget provider
-keep class com.brby.yisu.CanteenWidgetProvider { *; }
