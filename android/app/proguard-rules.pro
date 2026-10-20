# Flutter embeds its own rules. The rules below protect classes that are looked up by name at
# runtime (reflection / JNI) and would otherwise be stripped or renamed by R8:
#
#  * Several Flutter plugins (shared_preferences, path_provider, ...) call into their own Kotlin/Java
#    classes through JNI. Without this, release builds fail at startup with
#    "NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll" and never show the first frame.
# JNI resolves methods by their exact signature, so types in those signatures (notably the Kotlin
# suspend-function Continuation) must keep their real names too.
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# flutter_local_notifications deserialises its models with Gson (reflection).
-keep class com.dexterous.** { *; }

-dontwarn com.google.android.play.core.**
