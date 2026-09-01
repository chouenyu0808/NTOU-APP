# ML Kit 的文字辨識分成五套語系，每一套是各自獨立的 artifact。
#
# 我們只用拉丁（見 lib/src/ui/login_page.dart 的 TextRecognitionScript.latin），
# 另外四套的 artifact 沒有進 build。但 google_mlkit_text_recognition 的
# Android 端對五套都有引用，所以 R8 在 release 會找不到那四組類別而中斷
# （`:app:minifyReleaseWithR8` 失敗）。debug 不跑 R8，所以撞不到 ——
# 這個破口從 1f6acb3 加進 OCR 那天就在了，只是一直都在裝 debug。
#
# 這幾行不是把警告藏起來：那些類別本來就不該在，缺的只是「別為它們報錯」。
# 哪天真的要認中日韓，要做的是把對應的 artifact 加進 dependencies，
# 不是把這幾行刪掉。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# 上面那四行只讓 build 過得去，**不會保住任何東西** —— 這是第一版漏掉的。
#
# ML Kit 的 component registrar 是 MlKitInitProvider 用反射實例化的：類別名
# 寫在 AndroidManifest 的 metadata 裡，執行期才 Class.forName + newInstance。
# R8 看不到任何程式碼呼叫那些建構子，就把它們拿掉了，於是 App 一啟動就是
#
#   Could not instantiate com.google.mlkit.common.internal.CommonComponentRegistrar
#   Caused by: java.lang.NoSuchMethodException: ...<init> []
#
# ML Kit 整個初始化不起來，之後 TextRecognizer 那邊會拿到 null，
# MethodChannel 丟 NullPointerException。而 _autoRecognizeCaptcha 的 catch
# 只進 debugPrint，release 又看不到 —— 所以症狀是「驗證碼欄就是不會自動填」，
# 沒有任何錯誤訊息。要接 logcat 才看得到。
#
# 這個 App 目前宣告了三個（AndroidManifest 裡查得到）：
#   com.google.mlkit.common.internal.CommonComponentRegistrar
#   com.google.mlkit.vision.common.internal.VisionCommonRegistrar
#   com.google.mlkit.vision.text.internal.TextRegistrar
# 但用 implements 寫，之後加別的 ML Kit 功能不用回來改這裡。
#
# 名字不能被混淆（manifest 是用字串指的），無參數建構子要留（反射要用）。
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
