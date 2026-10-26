package ru.koshelek.app.data

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.runtime.*
import androidx.core.content.FileProvider
import kotlinx.coroutines.*
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import okhttp3.Request
import java.io.File

/**
 * Обновление Android-версии без магазина: GitHub Actions собирает APK и кладёт его на ваш сервер
 * (коллекция kp_builds), а приложение при запуске проверяет, нет ли сборки новее, и предлагает установить.
 */
object Updater {
    data class Release(val version: Int, val name: String, val notes: String, val url: String)

    private lateinit var app: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    var available by mutableStateOf<Release?>(null)
    var progress by mutableStateOf<Float?>(null)
    var error by mutableStateOf<String?>(null)
    private var lastCheck = 0L

    val currentVersion: Int get() = runCatching {
        val pi = app.packageManager.getPackageInfo(app.packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode.toInt() else @Suppress("DEPRECATION") pi.versionCode
    }.getOrDefault(0)
    val currentName: String get() = runCatching { app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "" }.getOrDefault("")

    fun init(ctx: Context) { app = ctx.applicationContext }

    fun check(force: Boolean = false) {
        if (!force && System.currentTimeMillis() - lastCheck < 30 * 60_000) return
        lastCheck = System.currentTimeMillis()
        scope.launch {
            runCatching {
                val o = Server.call("/api/collections/kp_builds/records?sort=-version&perPage=1", auth = false, retry = false)
                val r = (o["items"] as? JsonArray)?.firstOrNull() as? JsonObject ?: return@launch
                val b = Release(r.num("version").toInt(), r.str("name"), r.str("notes"),
                    "${Server.url}/api/files/kp_builds/${r.str("id")}/${r.str("apk")}")
                available = if (b.version > currentVersion && r.str("apk").isNotEmpty()) b else null
            }
        }
    }

    fun install(b: Release) {
        if (progress != null) return
        error = null; progress = 0f
        scope.launch {
            try {
                val f = File(app.cacheDir, "kopilka-${b.version}.apk")
                withContext(Dispatchers.IO) {
                    Server.http.newCall(Request.Builder().url(b.url).build()).execute().use { r ->
                        if (!r.isSuccessful) throw ApiError("Сервер не отдал файл (${r.code})")
                        val body = r.body ?: throw ApiError("Пустой ответ")
                        val total = body.contentLength().takeIf { it > 0 } ?: -1L
                        body.byteStream().use { inp ->
                            f.outputStream().use { out ->
                                val buf = ByteArray(64 * 1024); var got = 0L
                                while (true) {
                                    val n = inp.read(buf); if (n < 0) break
                                    out.write(buf, 0, n); got += n
                                    if (total > 0) withContext(Dispatchers.Main) { progress = got.toFloat() / total }
                                }
                            }
                        }
                    }
                }
                val uri = FileProvider.getUriForFile(app, "ru.koshelek.app.files", f)
                app.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (e: Exception) {
                error = e.message ?: "Не удалось скачать обновление"
            } finally { progress = null }
        }
    }
}
