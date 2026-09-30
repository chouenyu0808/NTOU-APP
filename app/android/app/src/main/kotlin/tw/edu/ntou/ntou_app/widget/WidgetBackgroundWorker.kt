package tw.edu.ntou.ntou_app.widget

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * 等 Dart 完成畫圖、存檔及排下一輪鬧鐘，才讓 WorkManager 結束背景工作。
 * 套件內建的 worker 在送出呼叫後就回報成功，App 沒開著時程序可能提早被回收。
 * 每次使用獨立引擎，也避免背景 isolate 沿用前一次的課表快取。
 */
class WidgetBackgroundWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.Main) {
        val uri = inputData.getString(URI_KEY) ?: return@withContext Result.failure()
        val dispatcher = HomeWidgetPlugin.getDispatcherHandle(applicationContext)
        val callback = HomeWidgetPlugin.getHandle(applicationContext)
        // 尚未開過 App 時沒有回呼；下次更新會建立新工作，不會污染整條鏈。
        if (dispatcher == 0L || callback == 0L) return@withContext Result.failure()

        var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
        try {
            withTimeout(120_000L) {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcher)
                    ?: error("找不到小組件背景回呼")
                val ready = CompletableDeferred<Unit>()
                val completed = CompletableDeferred<Unit>()
                val backgroundEngine = FlutterEngine(applicationContext)
                engine = backgroundEngine
                val backgroundChannel = MethodChannel(
                    backgroundEngine.dartExecutor.binaryMessenger,
                    "home_widget/background",
                )
                channel = backgroundChannel
                backgroundChannel.setMethodCallHandler { call, result ->
                    if (call.method == "HomeWidget.backgroundInitialized") {
                        result.success(null)
                        ready.complete(Unit)
                    } else {
                        result.notImplemented()
                    }
                }
                backgroundEngine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(applicationContext.assets, loader.findAppBundlePath(), info),
                )
                ready.await()
                // 套件的 dispatcher 會 await Dart callback，這個回覆才代表真正完成。
                backgroundChannel.invokeMethod("", listOf(callback, uri), object : MethodChannel.Result {
                    override fun success(result: Any?) { completed.complete(Unit) }
                    override fun error(code: String, message: String?, details: Any?) {
                        completed.completeExceptionally(IllegalStateException("小組件背景更新失敗"))
                    }
                    override fun notImplemented() {
                        completed.completeExceptionally(IllegalStateException("小組件背景入口不存在"))
                    }
                })
                completed.await()
            }
            Result.success()
        } catch (_: TimeoutCancellationException) {
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // 只有限次退避重試；之後仍可由節次鬧鐘和定期更新恢復。
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                channel?.setMethodCallHandler(null)
                engine?.destroy()
            }
        }
    }

    companion object {
        const val URI_KEY = "uri"
    }
}
