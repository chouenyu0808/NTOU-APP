package tw.edu.ntou.ntou_app.widget

import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import tw.edu.ntou.ntou_app.R

/**
 * 交通小組件。
 *
 * 跟課表相反，這裡**每次更新都要打網路** —— 到站時間沒有本機來源。
 * 而 Android 小組件最快只能 30 分鐘自動更新一次（`updatePeriodMillis`
 * 的系統下限），所以上面的數字必然是舊的，Dart 那邊會把資料時間畫上去。
 */
class TransitWidgetProvider : NtouWidgetProvider() {

    override val layoutId = R.layout.widget_transit
    override val host = "transit"
    override val lightKey = "transit_image_light"
    override val darkKey = "transit_image_dark"
    override val surfaceKey = "transit_surface"

    /**
     * 該不該再去抓一次。
     *
     * 兩個條件要同時成立：
     *
     * - **資料夠舊了**（超過 [STALE_MS]）。少了這條，我們自己畫完呼叫的
     *   updateWidget 會觸發 onUpdate，又去抓一次 —— 一個每次都打 TDX 的迴圈。
     * - **距離上次嘗試夠久了**（超過 [RETRY_MS]）。少了這條，抓失敗時
     *   「畫更新失敗 → onUpdate → 資料還是舊的 → 再抓」一樣會繞不停，
     *   而**重試本身正是被回 429 的原因**：一直重試就一直被擋。
     *
     * 使用者按右上角的重新整理鈕是直接送 broadcast，不經過這裡 ——
     * 那是他明確在說「現在再試一次」。
     */
    override fun isStale(data: SharedPreferences, now: Long): Boolean {
        val stale = now - data.millis(UPDATED_AT) >= STALE_MS
        val cooled = now - data.millis(LAST_ATTEMPT) >= RETRY_MS
        return stale && cooled
    }

    /** 右上角那顆重新整理鈕。圖是不能點的，所以它是疊在上面的真 View。 */
    override fun decorate(context: Context, views: RemoteViews, surface: Surface) {
        views.setOnClickPendingIntent(
            R.id.widget_refresh,
            HomeWidgetBackgroundIntent.getBroadcast(context, surface.uri(host)),
        )
    }

    private companion object {
        const val UPDATED_AT = "transit_updated_at"
        const val LAST_ATTEMPT = "transit_last_attempt"

        /**
         * 資料放多久算舊。
         *
         * 比 `updatePeriodMillis`（30 分）短一點，這樣週期性的 onUpdate 一定
         * 會判定成該抓 —— 抓成一樣長的話，系統的鬧鐘早個幾秒就會整輪跳過，
         * 而症狀是「小組件有時候會更新有時候不會」，非常難查。
         */
        const val STALE_MS = 25L * 60 * 1000

        /** 失敗之後至少隔這麼久再試。 */
        const val RETRY_MS = 5L * 60 * 1000
    }
}
