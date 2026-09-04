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

    /** 存「上次畫的尺寸」的 key。 */
    protected abstract val surfaceKey: String

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
            val sizeChanged = !surface.matches(widgetData.getString(surfaceKey, null))
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
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        askDart(context, surfaceOf(context, appWidgetManager, appWidgetId))
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

    /** 叫背景的 Dart 重算並重畫。 */
    protected fun askDart(context: Context, surface: Surface) {
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
