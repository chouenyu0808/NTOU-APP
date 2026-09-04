package tw.edu.ntou.ntou_app.widget

import android.content.SharedPreferences
import tw.edu.ntou.ntou_app.R

/**
 * 今日課表小組件。
 *
 * **完全不用網路，也不用登入。** 內容來自 App 已經抓下來的課表快取，
 * 所以學校系統掛掉、或帳號正在電腦上登著（學校一次只允許一個 session）
 * 的時候，桌面上這一塊照樣是對的 —— 那正是快取原本要救的情境。
 */
class TimetableWidgetProvider : NtouWidgetProvider() {

    override val layoutId = R.layout.widget_timetable
    override val host = "timetable"
    override val lightKey = "timetable_image_light"
    override val darkKey = "timetable_image_dark"
    override val surfaceKey = "timetable_surface"
    override val drawnKey = "timetable_drawn"

    /**
     * 手上這張圖過期了沒有。
     *
     * `timetable_valid_until` 是 Dart 算的「下一個節次交界」——
     * 原生這邊完全不需要知道節次表長什麼樣，只要比一個時間大小。
     *
     * **一定要有這個判斷。** 沒有的話每次 onUpdate 都會叫 Dart 重畫，
     * 而 Dart 畫完會叫 updateWidget，又觸發 onUpdate —— 一個不會停的迴圈。
     */
    override fun isStale(data: SharedPreferences, now: Long): Boolean =
        now >= data.millis(VALID_UNTIL)

    private companion object {
        const val VALID_UNTIL = "timetable_valid_until"
    }
}
