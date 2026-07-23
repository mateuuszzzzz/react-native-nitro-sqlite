# KeyProvider.resolveKey is invoked from native via JNI (FindClass +
# GetStaticMethodID by name in cpp-adapter.cpp), so R8/ProGuard sees no
# Java/Kotlin caller and would strip it — breaking SQLCipher key resolution in
# minified release builds. Keep the class and its members in consuming apps.
-keep class com.margelo.rnnitrosqlite.KeyProvider { *; }
