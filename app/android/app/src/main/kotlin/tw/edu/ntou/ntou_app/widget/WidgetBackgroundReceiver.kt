package tw.edu.ntou.ntou_app.widget

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

/** 自動更新和手動刷新共用佇列；前一次失敗不能讓後續更新永久取消。 */
class WidgetBackgroundReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri = intent.data ?: return
        if (uri.scheme != Surface.SCHEME || uri.host !in setOf("timetable", "transit")) return
        WorkManager.getInstance(context).enqueueUniqueWork(
            "ntou_widget_background",
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            OneTimeWorkRequestBuilder<WidgetBackgroundWorker>()
                .setInputData(workDataOf(WidgetBackgroundWorker.URI_KEY to uri.toString()))
                .build(),
        )
    }

    companion object {
        fun getBroadcast(context: Context, uri: Uri): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, WidgetBackgroundReceiver::class.java).setData(uri),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
    }
}
