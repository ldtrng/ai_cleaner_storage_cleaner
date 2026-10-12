# Flutter plugins are kept by their own consumer rules; keep our bridge + Media3 reflection.
-keep class io.ld2t.ai_cleaner.** { *; }
-dontwarn com.google.android.play.core.**

# Release crash on launch: R8 full mode strips the no-arg constructor of Room-generated classes
# (WorkManager's WorkDatabase_Impl, pulled in transitively by a plugin), so
# androidx.startup fails with "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
