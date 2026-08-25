allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// AGP 9.1 與 flutter_secure_storage 11 的相容性問題。
//
// 那個 plugin 宣告 compileSdk = 37，AGP 就去找 hash string "android-37"。
// 但 Google 從 API 37 開始把平台改成有 minor 版本，只發了 android-37.0 / 37.1，
// **沒有平版的 android-37**。結果是：
//
//     Failed to find target with hash string 'android-37' in: C:\dev\android-sdk
//
// 而且 AGP 會先把 android-37.0 裝起來、然後才說找不到 android-37，
// 所以看起來像 SDK 沒裝好，其實是版號對不上。
//
// 把所有 Android library 子專案釘回 App 自己的 compileSdk。往下釘是安全的：
// flutter_secure_storage 的 minSdk 是 24，程式裡只用 Build.VERSION_CODES 做執行期
// 判斷，沒有用到 API 37 才有的東西。
//
// 用反射而不是 import AGP 的型別 —— 這裡是 root project，AGP 的類別不保證在
// buildscript classpath 上，import 會換成另一種更難查的錯誤。
//
// **這是暫時的。** Google 補上 android-37、或 plugin 改宣告之後就可以拿掉。
// 檢查方式：把這一段刪掉，build 過就是修好了。
val pinnedCompileSdk = 36

subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        val setter =
            androidExtension.javaClass.methods.firstOrNull {
                it.name == "setCompileSdk" &&
                    it.parameterCount == 1 &&
                    it.parameterTypes[0].isAssignableFrom(Integer::class.java)
            } ?: return@afterEvaluate
        setter.invoke(androidExtension, pinnedCompileSdk)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
