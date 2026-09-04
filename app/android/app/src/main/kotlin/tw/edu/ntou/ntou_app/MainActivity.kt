package tw.edu.ntou.ntou_app

import android.os.Bundle
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        unpoisonWidgetWork()
    }

    /**
     * 把桌面小組件那條背景工作鏈上已經結束的紀錄清掉。
     *
     * **這是在解一個會永久卡死的狀況。** `home_widget` 用
     * `ExistingWorkPolicy.APPEND` 把每一次背景請求接到同一條 unique work
     * 鏈上（名字是 `home_widget_background`），而 WorkManager 的規則是：
     * **鏈上只要有一筆 FAILED 或 CANCELLED，之後每一次 append 都會被立刻
     * 取消。** 不會有錯誤、不會有 log，小組件就是永遠停在「載入中」。
     *
     * 而第一次失敗幾乎是必然的：使用者裝好 App、還沒開過就先把小組件放上
     * 桌面 —— 那時候 Dart 的 callback handle 還沒註冊，worker 一定丟例外。
     *
     * `pruneWork` 會把已經結束、而且沒有未完成後續的工作從資料庫刪掉。
     * 鏈上的紀錄一旦消失，下一次 append 就等於開一條新的鏈。
     *
     * 放在 `onCreate`：使用者開 App 是我們唯一確定能修好它的時機，而那也
     * 正好是他發現小組件壞掉之後會做的事。
     */
    private fun unpoisonWidgetWork() {
        runCatching { WorkManager.getInstance(applicationContext).pruneWork() }
    }
}
