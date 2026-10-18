-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exceptions

-keepclasseswithmembernames class * {
    native <methods>;
}

-keep class com.onyx.terminal.terminal.PtyManager { *; }
-keep class com.onyx.terminal.terminal.NativePty { *; }
-keep class com.onyx.terminal.terminal.NativeExec { *; }

-keep class net.schmizz.** { *; }
-keep class com.hierynomus.** { *; }
-keep class net.i2p.crypto.** { *; }
-keep class org.bouncycastle.** { *; }
-keep class com.github.junrar.** { *; }
-keep class org.apache.commons.compress.** { *; }
-keep class org.tukaani.xz.** { *; }
-keep class org.apache.commons.net.** { *; }

-dontwarn org.bouncycastle.**
-dontwarn net.i2p.crypto.**
-dontwarn javax.naming.**
-dontwarn javax.security.auth.**
-dontwarn org.ietf.jgss.**
-dontwarn com.jcraft.jzlib.**
-dontwarn org.slf4j.**
-dontwarn org.apache.commons.compress.**
-dontwarn org.apache.commons.lang3.**
-dontwarn org.apache.commons.io.**
-dontwarn org.apache.commons.codec.**
-dontwarn org.brotli.**
-dontwarn com.github.luben.zstd.**
-dontwarn org.objectweb.asm.**
-dontwarn java.lang.management.**
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}

-assumenosideeffects class com.onyx.terminal.util.Logger {
    public static void d(...);
}

-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
