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
