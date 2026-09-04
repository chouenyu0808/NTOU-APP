plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tw.edu.ntou.ntou_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tw.edu.ntou.ntou_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // ML Kit requires API 21+
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // 只是「加」一份規則上去，不是取代 —— Flutter 的 Gradle plugin 自己
            // 也會塞一份，那份要留著。內容見 proguard-rules.pro：ML Kit 只用了
            // 拉丁那一套，R8 會為另外四套語系找不到類別而中斷。
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // MainActivity 要用 WorkManager 把桌面小組件那條中毒的背景工作鏈清掉
    // （理由見 MainActivity.unpoisonWidgetWork）。home_widget 本來就把它帶
    // 進來了，這裡明寫是因為**我們自己的程式碼直接用到它** ——
    // 靠傳遞依賴的話，哪天套件換掉實作，這裡會在編譯期才炸。
    implementation("androidx.work:work-runtime-ktx:2.10.0")
}

flutter {
    source = "../.."
}
