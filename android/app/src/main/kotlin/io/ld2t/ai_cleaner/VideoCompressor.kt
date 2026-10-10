package io.ld2t.ai_cleaner

import android.content.ContentUris
import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/** Re-encodes a gallery video to H.264 with a lower bitrate / resolution using Media3 Transformer. */
@OptIn(UnstableApi::class)
class VideoCompressor(private val ctx: Context) {
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private val holder = ProgressHolder()

    /** [factor] is the target bitrate as a fraction of the source bitrate. */
    fun compress(id: Long, factor: Double, maxShortSide: Int, done: (String?, String?) -> Unit) {
        main.post {
            try {
                cancel()
                val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                val retriever = MediaMetadataRetriever()
                var bitrate = 8_000_000
                var shortSide = 1080
                try {
                    retriever.setDataSource(ctx, uri)
                    bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: bitrate
                    val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1920
                    val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1080
                    shortSide = minOf(w, h)
                } finally {
                    retriever.release()
                }
                val targetBitrate = maxOf(400_000, (bitrate * factor).toInt())
                val targetShort = minOf(shortSide, maxShortSide).let { it - it % 2 }

                val out = File(ctx.cacheDir, "compressed_${id}_${System.currentTimeMillis()}.mp4")
                val encoderFactory = DefaultEncoderFactory.Builder(ctx)
                    .setRequestedVideoEncoderSettings(
                        VideoEncoderSettings.Builder().setBitrate(targetBitrate).build()
                    )
                    .build()
                val effects = if (targetShort < shortSide) {
                    Effects(listOf(), listOf(Presentation.createForShortSide(targetShort)))
                } else {
                    Effects.EMPTY
                }
                val item = EditedMediaItem.Builder(MediaItem.fromUri(uri)).setEffects(effects).build()
                val t = Transformer.Builder(ctx)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setEncoderFactory(encoderFactory)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            transformer = null
                            done(out.absolutePath, null)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            transformer = null
                            out.delete()
                            done(null, exportException.message)
                        }
                    })
                    .build()
                transformer = t
                t.start(item, out.absolutePath)
            } catch (e: Throwable) {
                transformer = null
                done(null, e.message)
            }
        }
    }

    /** 0..100, or -1 when unknown. Must be read on the main thread. */
    fun progress(): Int {
        val t = transformer ?: return -1
        return if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) holder.progress else -1
    }

    fun cancel() {
        main.post {
            transformer?.cancel()
            transformer = null
        }
    }
}
