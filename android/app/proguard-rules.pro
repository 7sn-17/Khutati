# Keep Drift/SQLite and Supabase reflection entry points when R8 runs.
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# sqlite3 native bindings
-keep class org.sqlite.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# flutter_local_notifications uses Gson-serialised payloads
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }

# Supabase / GoTrue
-keep class io.supabase.** { *; }

# Flutter's embedding references Play Core deferred-component classes that this
# side-loaded app never uses. Play Core is not a dependency, so R8 reports the
# references as missing classes and fails the release build; they are dead code
# here.
-dontwarn com.google.android.play.core.**

-dontwarn org.jetbrains.annotations.**
