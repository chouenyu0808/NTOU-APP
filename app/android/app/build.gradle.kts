import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 專案自己的簽章設定（`android/key.properties`，不進版控）。
//
// **為什麼不直接用 debug keystore**：`~/.android/debug.keystore` 是 Android SDK
// 在每台電腦第一次 build 時自動產生的，內容隨機。所以換一台電腦 build，裝到
// 同一支手機就會被 Android 拒絕：
//
//     INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match newer version
//
// 而唯一的覆蓋方式是先解除安裝 —— 那會把預排課表、記住的帳密、課表快取整個
// 清掉。兩台機器指向同一個 keystore 檔案，這個問題就不存在。
//
// **檔案不在時整段跳過，退回 debug** —— 只做 app/、不裝實機的人不必準備
// 任何東西，行為跟以前完全一樣。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
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

    signingConfigs {
        // 只有在 key.properties 存在時才建立這一組。
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("ntou") {
                storeFile =
                    rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 就用專案自己那把，否則退回 debug keystore
            // （行為跟以前一樣，只是換一台電腦 build 就裝不上同一支手機）。
            //
            // **換掉這把 key 之後，已經裝在手機上的 App 就要先解除安裝才裝得
            // 回去**，而解除安裝會清掉使用者的預排課表和登入資料。所以
            // `android/ntou-release.keystore` 那個檔案要當成長期資產保管，
            // 不是隨時可以重新產生的東西。
            signingConfig = signingConfigs.findByName("ntou")
                ?: signingConfigs.getByName("debug")

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
