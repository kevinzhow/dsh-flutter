# Whalee compatibility patch

Upstream: flutter_inappwebview_android 1.1.3, https://pub.dev/packages/flutter_inappwebview_android/versions/1.1.3 . The upstream license is retained in LICENSE.

Android Gradle Plugin 9 rejects the obsolete proguard-android.txt default because it disables R8 optimization. Both build types now use proguard-android-optimize.txt. No runtime behavior or JavaScript handlers are changed. Remove this override when an upstream stable release provides this compatibility fix.
