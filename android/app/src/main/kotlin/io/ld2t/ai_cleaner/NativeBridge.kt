package io.ld2t.ai_cleaner

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.storage.StorageManager
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class NativeBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "io.ld2t.ai_cleaner/native"
    }

    private val ctx: Context get() = activity.applicationContext
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())
    private val videoCompressor by lazy { VideoCompressor(ctx) }

    fun dispose() {
        io.shutdownNow()
        videoCompressor.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)
            "storageInfo" -> background(result) { storageInfo() }
            "queryMedia" -> background(result) { queryMedia(call.argument<String>("type") ?: "image") }
            "analyzeImages" -> {
                val ids = call.argument<List<Number>>("ids")?.map { it.toLong() } ?: emptyList()
                background(result) { ImageAnalyzer.analyzeAll(ctx, ids) }
            }
            "queryPastEvents" -> background(result) { queryPastEvents() }
            "deleteEvents" -> {
                val ids = call.argument<List<Number>>("ids")?.map { it.toLong() } ?: emptyList()
                background(result) { deleteEvents(ids) }
            }
            "hasUsageAccess" -> result.success(hasUsageAccess())
            "openUsageAccessSettings" -> {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .setData(Uri.parse("package:${ctx.packageName}"))
                runCatching { activity.startActivity(intent) }.onFailure {
                    activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                }
                result.success(null)
            }
            "listApps" -> background(result) { listApps() }
            "uninstallApp" -> {
                val pkg = call.argument<String>("package")!!
                activity.startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")))
                result.success(null)
            }
            "isInstalled" -> {
                val pkg = call.argument<String>("package")!!
                result.success(isInstalled(pkg))
            }
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:${ctx.packageName}"))
                activity.startActivity(intent)
                result.success(null)
            }
            "compressVideo" -> {
                val id = (call.argument<Number>("id") ?: 0).toLong()
                val factor = call.argument<Double>("factor") ?: 0.5
                val maxShortSide = call.argument<Int>("maxShortSide") ?: 720
                videoCompressor.compress(id, factor, maxShortSide) { path, error ->
                    if (path != null) result.success(path) else result.error("compress_failed", error, null)
                }
            }
            "videoProgress" -> result.success(videoCompressor.progress())
            "cancelVideoCompress" -> {
                videoCompressor.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("native_error", e.message, null) }
            }
        }
    }

    private fun storageInfo(): Map<String, Long> {
        val ssm = ctx.getSystemService(StorageStatsManager::class.java)
        return mapOf(
            "total" to ssm.getTotalBytes(StorageManager.UUID_DEFAULT),
            "free" to ssm.getFreeBytes(StorageManager.UUID_DEFAULT),
        )
    }

    private fun queryMedia(type: String): List<Map<String, Any?>> {
        val isVideo = type == "video"
        val uri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.ORIENTATION,
        )
        if (isVideo) projection.add(MediaStore.MediaColumns.DURATION)
        val out = ArrayList<Map<String, Any?>>()
        ctx.contentResolver.query(
            uri, projection.toTypedArray(), null, null,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC"
        )?.use { c ->
            val iId = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val iSize = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val iW = c.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
            val iH = c.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
            val iTaken = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val iAdded = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val iMod = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val iPath = c.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
            val iName = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val iMime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val iOri = c.getColumnIndexOrThrow(MediaStore.MediaColumns.ORIENTATION)
            val iDur = if (isVideo) c.getColumnIndexOrThrow(MediaStore.MediaColumns.DURATION) else -1
            while (c.moveToNext()) {
                val taken = c.getLong(iTaken)
                out.add(
                    mapOf(
                        "id" to c.getLong(iId),
                        "size" to c.getLong(iSize),
                        "width" to c.getInt(iW),
                        "height" to c.getInt(iH),
                        // seconds
                        "date" to if (taken > 0) taken / 1000 else c.getLong(iAdded),
                        "modified" to c.getLong(iMod),
                        "path" to (c.getString(iPath) ?: ""),
                        "name" to (c.getString(iName) ?: ""),
                        "mime" to (c.getString(iMime) ?: ""),
                        "orientation" to c.getInt(iOri),
                        "duration" to if (iDur >= 0) c.getLong(iDur) else 0L,
                    )
                )
            }
        }
        return out
    }

    private fun queryPastEvents(): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.CALENDAR_DISPLAY_NAME,
            CalendarContract.Events.CALENDAR_COLOR,
            CalendarContract.Events.EVENT_LOCATION,
        )
        val selection = "${CalendarContract.Events.DTEND} < ? AND " +
            "(${CalendarContract.Events.RRULE} IS NULL OR ${CalendarContract.Events.RRULE} = '') AND " +
            "${CalendarContract.Events.DELETED} = 0 AND " +
            "${CalendarContract.Events.CALENDAR_ACCESS_LEVEL} >= ${CalendarContract.Events.CAL_ACCESS_CONTRIBUTOR}"
        val out = ArrayList<Map<String, Any?>>()
        ctx.contentResolver.query(
            CalendarContract.Events.CONTENT_URI, projection, selection,
            arrayOf(now.toString()), "${CalendarContract.Events.DTSTART} DESC"
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "title" to (c.getString(1) ?: ""),
                        "start" to c.getLong(2),
                        "end" to c.getLong(3),
                        "allDay" to (c.getInt(4) == 1),
                        "calendar" to (c.getString(5) ?: ""),
                        "color" to c.getInt(6),
                        "location" to (c.getString(7) ?: ""),
                    )
                )
            }
        }
        return out
    }

    private fun deleteEvents(ids: List<Long>): Int {
        var count = 0
        for (id in ids) {
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
            count += runCatching { ctx.contentResolver.delete(uri, null, null) }.getOrDefault(0)
        }
        return count
    }

    private fun hasUsageAccess(): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)
        val mode = ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isInstalled(pkg: String): Boolean = try {
        ctx.packageManager.getApplicationInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun listApps(): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val packages = pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it != ctx.packageName }

        val usage = hasUsageAccess()
        val lastUsed = HashMap<String, Long>()
        if (usage) {
            val usm = ctx.getSystemService(UsageStatsManager::class.java)
            val now = System.currentTimeMillis()
            usm.queryAndAggregateUsageStats(now - 365L * 24 * 3600 * 1000, now)
                .forEach { (pkg, stats) -> lastUsed[pkg] = stats.lastTimeUsed }
        }
        val ssm = ctx.getSystemService(StorageStatsManager::class.java)

        val out = ArrayList<Map<String, Any?>>()
        for (pkg in packages) {
            val info = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull() ?: continue
            val isSystem = info.flags and ApplicationInfo.FLAG_SYSTEM != 0 &&
                info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP == 0
            if (isSystem) continue
            val pInfo = runCatching { pm.getPackageInfo(pkg, 0) }.getOrNull()
            var size = -1L
            if (usage) {
                runCatching {
                    val s = ssm.queryStatsForPackage(info.storageUuid, pkg, Process.myUserHandle())
                    size = s.appBytes + s.dataBytes + s.cacheBytes
                }
            }
            out.add(
                mapOf(
                    "package" to pkg,
                    "name" to pm.getApplicationLabel(info).toString(),
                    "installTime" to (pInfo?.firstInstallTime ?: 0L),
                    "updateTime" to (pInfo?.lastUpdateTime ?: 0L),
                    "lastUsed" to (lastUsed[pkg] ?: 0L),
                    "size" to size,
                    "icon" to iconBytes(pm, info),
                )
            )
        }
        return out
    }

    private fun iconBytes(pm: PackageManager, info: ApplicationInfo): ByteArray? = runCatching {
        val drawable = pm.getApplicationIcon(info)
        val px = 96
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, px, px)
        drawable.draw(canvas)
        val bos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
        bmp.recycle()
        bos.toByteArray()
    }.getOrNull()
}

/** Perceptual hash + sharpness score computed from MediaStore thumbnails. */
object ImageAnalyzer {
    private const val THUMB = 256

    // Separate from the bridge's IO pool so a caller running on that pool can block on it safely.
    private val workers = Executors.newFixedThreadPool(maxOf(2, Runtime.getRuntime().availableProcessors() - 1))

    fun analyzeAll(ctx: Context, ids: List<Long>): List<Map<String, Any>> =
        ids.map { id -> workers.submit<Map<String, Any>?> { analyze(ctx, id) } }
            .mapNotNull { runCatching { it.get() }.getOrNull() }

    fun analyze(ctx: Context, id: Long): Map<String, Any>? {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        val bmp = runCatching { ctx.contentResolver.loadThumbnail(uri, Size(THUMB, THUMB), null) }.getOrNull()
            ?: return null
        try {
            val w = bmp.width
            val h = bmp.height
            if (w < 9 || h < 8) return null
            val pixels = IntArray(w * h)
            bmp.getPixels(pixels, 0, w, 0, 0, w, h)
            val gray = DoubleArray(w * h) { i ->
                val p = pixels[i]
                0.299 * ((p shr 16) and 0xff) + 0.587 * ((p shr 8) and 0xff) + 0.114 * (p and 0xff)
            }
            return mapOf(
                "id" to id,
                "hash" to dHash(gray, w, h),
                "sharpness" to laplacianVariance(gray, w, h),
                "contrast" to stdDev(gray),
            )
        } finally {
            bmp.recycle()
        }
    }

    /** 64-bit difference hash on a 9x8 box-averaged grid. */
    private fun dHash(gray: DoubleArray, w: Int, h: Int): Long {
        val gw = 9
        val gh = 8
        val grid = DoubleArray(gw * gh)
        for (gy in 0 until gh) {
            val y0 = gy * h / gh
            val y1 = maxOf(y0 + 1, (gy + 1) * h / gh)
            for (gx in 0 until gw) {
                val x0 = gx * w / gw
                val x1 = maxOf(x0 + 1, (gx + 1) * w / gw)
                var sum = 0.0
                for (y in y0 until y1) for (x in x0 until x1) sum += gray[y * w + x]
                grid[gy * gw + gx] = sum / ((y1 - y0) * (x1 - x0))
            }
        }
        var hash = 0L
        var bit = 0
        for (gy in 0 until gh) for (gx in 0 until 8) {
            if (grid[gy * gw + gx] > grid[gy * gw + gx + 1]) hash = hash or (1L shl bit)
            bit++
        }
        return hash
    }

    private fun laplacianVariance(gray: DoubleArray, w: Int, h: Int): Double {
        var sum = 0.0
        var sumSq = 0.0
        var n = 0
        for (y in 1 until h - 1) for (x in 1 until w - 1) {
            val i = y * w + x
            val lap = gray[i - w] + gray[i + w] + gray[i - 1] + gray[i + 1] - 4 * gray[i]
            sum += lap
            sumSq += lap * lap
            n++
        }
        if (n == 0) return 0.0
        val mean = sum / n
        return sumSq / n - mean * mean
    }

    private fun stdDev(gray: DoubleArray): Double {
        val mean = gray.average()
        var acc = 0.0
        for (g in gray) acc += (g - mean) * (g - mean)
        return Math.sqrt(acc / gray.size)
    }
}
