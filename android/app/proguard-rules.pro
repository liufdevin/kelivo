-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# LiteRT-LM uses JNI to call back into its Java/Kotlin wrapper classes.
# Keep the wrapper package stable so native method lookups such as
# nativeCreateConversation -> SamplerConfig.getTopK do not abort with mid == null.
-keep class com.google.ai.edge.litertlm.** { *; }
-keep interface com.google.ai.edge.litertlm.** { *; }
-keepnames class com.google.ai.edge.litertlm.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
