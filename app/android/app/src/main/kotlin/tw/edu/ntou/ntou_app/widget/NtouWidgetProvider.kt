package tw.edu.ntou.ntou_app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import tw.edu.ntou.ntou_app.MainActivity
import tw.edu.ntou.ntou_app.R

/**
 * 兩個小組件共用的部分。
 *
 * **這一層刻意什麼都不判斷。** 它只做三件事：把 Dart 畫好的 PNG 貼上去、
 * 在該重畫的時候叫 Dart、把點擊轉回去。
 *
 * 「現在是第幾節」「這班車還有幾分鐘」「這條路線往哪裡」全部留在 Dart ——
 * 那些判斷錯了畫面上完全看不出來（顯示的是一個看起來很合理的別的東西），
 * 而 Dart 那邊有測試守著，這邊沒有。
 */
abstract class NtouWidgetProvider : HomeWidgetProvider() {

    /** `R.layout.widget_xxx`。 */
    protected abstract val layoutId: Int

    /** 背景 URI 的 host，要跟 Dart 的 `widgetHostXxx` 一致。 */
    protected abstract val host: String

    /** 存 PNG 路徑的 key，要跟 Dart 的 `WidgetKeys` 一致。 */
    protected abstract val lightKey: String
    protected abstract val darkKey: String

    /**
     * 存「小組件現在多大」的 key。**這一個是原生寫的。**
     *
     * 為什麼要原生寫：Dart 的前景路徑（App 開著、剛抓完課表）不知道桌面上
     * 那塊東西多大，它只能讀這裡。而如果只有 Dart 在畫完之後才寫，就會變成
     * 一個解不開的死結 —— 新裝的 App 還沒畫過任何一張圖，前景路徑讀不到
     * 尺寸就直接放棄，於是永遠畫不出第一張。
     *
     * 這個值同時也是「桌面上真的有這個小組件」的唯一證據。
     */
    protected abstract val surfaceKey: String

    /**
     * 存「手上那張圖是照什麼尺寸畫的」的 key。**這一個是 Dart 寫的。**
     *
     * 跟 [surfaceKey] 分開是必要的：要判斷「使用者把小組件拉大了」，比的是
     * 「現在多大」對「圖是照多大畫的」。兩件事寫進同一個 key 的話，原生一寫
     * 就等於把自己要比對的對象也蓋掉，尺寸變化永遠偵測不到。
     */
    protected abstract val drawnKey: String

    /**
     * 尺寸沒變的時候，這次要不要叫 Dart 重算。
     *
     * 尺寸變了一定要重畫（拿舊尺寸的圖去拉會糊），那個判斷在基底這裡；
     * 「資料過期了沒有」各自不同，交給子類別。
     */
    protected abstract fun isStale(data: SharedPreferences, now: Long): Boolean

    /** 子類別要多綁的東西（交通那顆重新整理鈕）。 */
    protected open fun decorate(
        context: Context,
        views: RemoteViews,
        surface: Surface,
    ) = Unit

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        var asked = false

        for (id in appWidgetIds) {
            val surface = surfaceOf(context, appWidgetManager, id)
            // 先把尺寸記下來，**在問 Dart 之前**。這是 App 前景那條路徑
            // 唯一能知道「桌面上有這塊東西、而且它這麼大」的方式。
            remember(context, surface)

            val views = RemoteViews(context.packageName, layoutId)

            val hasImage = bindImages(views, widgetData)
            views.setViewVisibility(
                R.id.widget_placeholder,
                if (hasImage) View.GONE else View.VISIBLE,
            )
            // 點整塊開 App。
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            decorate(context, views, surface)
            appWidgetManager.updateAppWidget(id, views)

            // **一次 onUpdate 只叫 Dart 一次。** 桌面上放兩個一樣的小組件是
            // 允許的，每個都叫的話同樣的工作會做兩遍 —— 交通那邊就是打兩次
            // TDX，而那正是會被回 429 的原因。
            if (asked) continue
            val sizeChanged = !surface.matches(widgetData.getString(drawnKey, null))
            if (sizeChanged || isStale(widgetData, now)) {
                askDart(context, surface)
                asked = true
            }
        }
    }

    /**
     * 使用者把小組件拉大縮小了。
     *
     * 一定要接：圖是照當時的尺寸畫的，尺寸變了還貼同一張就會被 ImageView
     * 拉伸成一張糊圖，而那看起來只像「這個 App 的小組件畫質很差」。
     *
     * **但一定要先確認尺寸真的變了。** 這個回呼不是只有拉大縮小才會來 ——
     * launcher 重新排版、換桌布、旋轉、甚至我們自己 updateWidget 之後
     * 重新量測，都可能發它。無條件叫 Dart 的話就是
     * 「畫完 → updateWidget → 重新量測 → 又叫 → 再畫」，一個不會停的迴圈，
     * 而交通那邊每繞一圈還會打一次 TDX。實測一次回桌面就繞了四圈。
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val surface = surfaceOf(context, appWidgetManager, appWidgetId)
        remember(context, surface)
        val data = HomeWidgetPlugin.getData(context)
        if (!surface.matches(data.getString(drawnKey, null))) askDart(context, surface)
    }

    /**
     * 把現在的尺寸寫進 widget data。
     *
     * 寫的是 `home_widget` 自己那份 SharedPreferences，所以 Dart 用
     * `HomeWidget.getWidgetData` 就讀得到。**檔名是套件內部的常數**
     * （`HomeWidgetPlugin.PREFERENCES`，internal 拿不到），只能照抄 ——
     * 套件哪天改掉這個名字，症狀會是前景路徑永遠讀不到尺寸、
     * 小組件只能靠背景更新，而且不會有任何錯誤。
     */
    private fun remember(context: Context, surface: Surface) {
        runCatching {
            context
                .getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(surfaceKey, surface.encode())
                .apply()
        }
    }

    /**
     * 兩張圖都貼。
     *
     * 為什麼兩張都貼：layout / layout-night 決定哪一個 ImageView 顯示，
     * 而那是 launcher 依它自己的設定 inflate 的 —— 我們不知道現在是哪一個，
     * 也不該知道。詳見 layout/widget_timetable.xml 的說明。
     *
     * 用 setImageViewBitmap 不是 setImageViewUri：PNG 存在 App 的私有目錄，
     * **launcher 是另一個 process，那個路徑它讀不到**（畫面上就是一片空白，
     * 沒有任何錯誤）。Bitmap 走的是 ashmem，不會撞到 binder 的傳輸上限。
     */
    private fun bindImages(views: RemoteViews, data: SharedPreferences): Boolean {
        val light = decode(data.getString(lightKey, null))
        val dark = decode(data.getString(darkKey, null))
        if (light == null && dark == null) return false
        light?.let { views.setImageViewBitmap(R.id.widget_image_light, it) }
        dark?.let { views.setImageViewBitmap(R.id.widget_image_dark, it) }
        return true
    }

    private fun decode(path: String?) =
        path?.takeIf { it.isNotEmpty() && File(it).exists() }?.let {
            // 檔案被寫到一半、或上一次畫壞了，decodeFile 會回 null 而不是丟例外。
            // 那時候就當作沒有圖，讓佔位字出來 —— 總比崩掉好。
            runCatching { BitmapFactory.decodeFile(it) }.getOrNull()
        }

    /**
     * 叫背景的 Dart 重算並重畫。
     *
     * **最後一道防線：短時間內只叫一次。**
     *
     * 上面每一個呼叫點都各自有自己的條件（資料夠舊了、尺寸變了……），
     * 但那些條件都依賴「Dart 有把狀態寫回來」。只要有一條路徑寫失敗、
     * 或者哪天多加一個呼叫點忘了加條件，整件事就會變成一個每次都打 TDX 的
     * 迴圈 —— 而畫面上完全看不出來，只有電池和 429 會告訴你。
     *
     * 這個節流不看任何業務狀態，所以那些條件全錯的時候它還是擋得住。
     * 使用者按右上角的重新整理鈕不經過這裡（那是直接掛 PendingIntent），
     * 所以擋不到他。
     */
    protected fun askDart(context: Context, surface: Surface) {
        val prefs = context.getSharedPreferences(HOME_WIDGET_PREFERENCES, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.millis(ASK_KEY) < ASK_COOLDOWN_MS) return
        runCatching { prefs.edit().putString(ASK_KEY, now.toString()).apply() }

        runCatching {
            HomeWidgetBackgroundIntent.getBroadcast(context, surface.uri(host)).send()
        }
    }

    /** 這個小組件現在多大。 */
    protected fun surfaceOf(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
    ): Surface {
        val options = manager.getAppWidgetOptions(id)
        val portrait =
            context.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT

        // 直向時寬度看 MIN、高度看 MAX；橫向反過來。這兩組是「小組件在兩種
        // 方向下各自的尺寸」，不是最小值和最大值 —— 取錯的話直向會拿到
        // 橫向那個寬度，圖畫出來比格子寬。
        val width = if (portrait) {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        } else {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
        }
        val height = if (portrait) {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        } else {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        }

        // 有些 launcher 在第一次 onUpdate 時還沒填 options，兩個都是 0。
        // 退回規格檔上的最小尺寸 —— 畫一張稍微小一點的圖，總比畫一張 0×0 的好。
        return Surface(
            width = if (width > 0) width.toFloat() else FALLBACK_WIDTH_DP,
            height = if (height > 0) height.toFloat() else FALLBACK_HEIGHT_DP,
            density = context.resources.displayMetrics.density,
        )
    }

    private companion object {
        /** 跟 xml/widget_*_info.xml 的 minWidth / minHeight 一致。 */
        const val FALLBACK_WIDTH_DP = 250f
        const val FALLBACK_HEIGHT_DP = 110f

        /** `home_widget` 存資料的 SharedPreferences 檔名。見 [remember]。 */
        const val HOME_WIDGET_PREFERENCES = "HomeWidgetPreferences"

        /** 上次叫 Dart 是什麼時候。見 [askDart]。 */
        const val ASK_KEY = "widget_last_ask"

        /**
         * 兩次叫 Dart 之間至少隔多久。
         *
         * 十秒：**足夠短到使用者感覺不到**（正常情況下一次動作只會叫一次），
         * 又足夠長到把任何一種「畫完又被叫」的迴圈切斷。
         */
        const val ASK_COOLDOWN_MS = 10_000L
    }
}

/**
 * 小組件現在多大、螢幕密度多少。
 *
 * Dart 那邊有一份對應的 `WidgetSurface`。**兩邊的編碼格式要一致**，
 * 但比對是用數值不是字串 —— Dart 的 double 和 Kotlin 的 Float 印出來的
 * 小數位數不保證一樣，比字串的話會永遠不相等，然後每次 onUpdate 都重畫一次。
 */
data class Surface(val width: Float, val height: Float, val density: Float) {

    fun uri(host: String): Uri =
        Uri.parse("$SCHEME://$host?w=$width&h=$height&dpr=$density")

    /** 存進 widget data 的樣子：`寬|高|密度`。要跟 Dart 的 `WidgetSurface` 一致。 */
    fun encode(): String = "$width|$height|$density"

    /** 跟 Dart 存下來的那份（`寬|高|密度`）是不是同一個尺寸。 */
    fun matches(stored: String?): Boolean {
        val parts = stored?.split('|') ?: return false
        if (parts.size != 3) return false
        val w = parts[0].toFloatOrNull() ?: return false
        val h = parts[1].toFloatOrNull() ?: return false
        val d = parts[2].toFloatOrNull() ?: return false
        // dp 差不到一格就當作沒變。有些 launcher 每次回報的數字會差個零點幾，
        // 嚴格比對的話小組件會一直重畫。
        return kotlin.math.abs(w - width) < 1f &&
            kotlin.math.abs(h - height) < 1f &&
            kotlin.math.abs(d - density) < 0.01f
    }

    companion object {
        /** 要跟 Dart 的 `widgetScheme` 一致。 */
        const val SCHEME = "ntouwidget"
    }
}

/** SharedPreferences 裡存的 epoch millis。存成字串的理由見 Dart 的 WidgetKeys。 */
internal fun SharedPreferences.millis(key: String): Long =
    getString(key, null)?.toLongOrNull() ?: 0L
