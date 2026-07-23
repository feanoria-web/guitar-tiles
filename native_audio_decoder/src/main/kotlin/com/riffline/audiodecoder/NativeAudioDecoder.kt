package com.riffline.audiodecoder

import android.app.Activity
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class NativeAudioDecoder(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "godot"
        private const val PREFIX = "NativeAudioDecoder: "
        private const val TARGET_CH = 2
        private const val PICK_FILES_REQUEST = 9001
    }

    override fun getPluginName() = "NativeAudioDecoder"

    override fun getPluginSignals(): Set<SignalInfo> {
        return setOf(
            // (percent: Int, stage: String)
            SignalInfo("decode_progress", Integer::class.java, String::class.java),
            // (wav_path: String)
            SignalInfo("decode_done", String::class.java),
            // (error: String)
            SignalInfo("decode_failed", String::class.java),
            // (paths: String) — semicolon-separated content URIs from file picker
            SignalInfo("files_picked", String::class.java),
        )
    }

    private var workerThread: Thread? = null
    private val cancelFlag = AtomicBoolean(false)

    /**
     * Start async decode+mix. Returns immediately.
     * Progress reported via decode_progress(pct, stage) signal.
     * Completion via decode_done(wav_path) or decode_failed(error).
     * Signals are emitted on the render thread (safe for GDScript).
     */
    @UsedByGodot
    fun decodeAndMix(inputPaths: Array<String>, outputWav: String) {
        cancelFlag.set(false)

        // If a previous worker is still running, cancel it first
        workerThread?.let { t ->
            if (t.isAlive) {
                Log.w(TAG, "${PREFIX}previous worker still alive, cancelling")
                cancelFlag.set(true)
                t.join(3000)
                cancelFlag.set(false)
            }
        }

        workerThread = Thread({
            doDecodeAndMix(inputPaths, outputWav)
        }, "AudioDecoder-Worker")
        workerThread!!.start()
    }

    /**
     * Cancel an in-progress decode. Worker will stop cleanly,
     * partial WAV file will be deleted.
     */
    @UsedByGodot
    fun cancelDecode() {
        Log.i(TAG, "${PREFIX}cancelDecode requested")
        cancelFlag.set(true)
    }

    /** The actual decode work — runs on worker thread. */
    private fun doDecodeAndMix(inputPaths: Array<String>, outputWav: String) {
        val total = inputPaths.size
        Log.i(TAG, "${PREFIX}decodeAndMix: $total inputs → $outputWav")
        logHeap("start")
        val t0 = System.currentTimeMillis()

        var tempFile: File? = null
        var raf: RandomAccessFile? = null
        var channel: FileChannel? = null

        try {
            if (cancelFlag.get()) { emitFailed("Cancelled"); return }

            // 1. Pre-scan max duration and detect source sample rate
            var maxDurationUs = 0L
            var detectedRate = 0
            for (path in inputPaths) {
                val dur = getAudioDurationUs(path)
                if (dur > maxDurationUs) maxDurationUs = dur
                val rate = getAudioSampleRate(path)
                if (rate > 0 && detectedRate == 0) detectedRate = rate
            }
            if (maxDurationUs <= 0L) {
                maxDurationUs = 15L * 60 * 1_000_000
                Log.w(TAG, "${PREFIX}could not read duration, using 15 min fallback")
            }
            if (detectedRate <= 0) detectedRate = 48000
            var outputRate = detectedRate
            Log.i(TAG, "${PREFIX}output sample rate = $outputRate Hz (from source)")

            val maxFrames = ((maxDurationUs / 1_000_000.0 + 2.0) * outputRate * 1.05).toLong()
            val maxSamples = maxFrames * TARGET_CH
            val fileSizeBytes = maxSamples * 4
            Log.i(TAG, "${PREFIX}accum file: %.1f MB for ~%.0fs max duration".format(
                fileSizeBytes / 1024.0 / 1024.0, maxDurationUs / 1_000_000.0))

            // 2. Create temp file + memory-map as FloatBuffer
            tempFile = File(outputWav + ".accum.tmp")
            tempFile.parentFile?.mkdirs()
            raf = RandomAccessFile(tempFile, "rw")
            raf.setLength(fileSizeBytes)
            channel = raf.channel
            val mappedBuf = channel.map(FileChannel.MapMode.READ_WRITE, 0, fileSizeBytes)
            mappedBuf.order(ByteOrder.nativeOrder())
            val floatBuf: FloatBuffer = mappedBuf.asFloatBuffer()

            // 3. Decode each stem and accumulate into mapped buffer
            var actualLen = 0
            var decodedCount = 0

            for ((idx, path) in inputPaths.withIndex()) {
                if (cancelFlag.get()) {
                    Log.i(TAG, "${PREFIX}cancelled before stem ${idx + 1}")
                    cleanup(channel, raf, tempFile, outputWav)
                    emitFailed("Cancelled")
                    return
                }

                val fname = File(path).name
                val stage = "$fname (${idx + 1}/$total)"
                Log.i(TAG, "${PREFIX}decoding $stage...")
                emitProgress(((idx) * 80) / total, "Çözümleniyor: $stage")

                val stemT0 = System.currentTimeMillis()

                try {
                    val result = streamDecodeIntoMapped(path, floatBuf, maxSamples.toInt(), idx, total, outputRate)
                    if (result.writePos > 0) {
                        if (result.writePos > actualLen) actualLen = result.writePos
                        // Use the ACTUAL decoded rate (from MediaCodec output) for WAV header
                        if (result.actualRate > 0 && result.actualRate != outputRate) {
                            Log.w(TAG, "${PREFIX}  actual decoded rate ${result.actualRate}Hz differs from pre-scan ${outputRate}Hz — using ${result.actualRate}Hz")
                            outputRate = result.actualRate
                        }
                        decodedCount++
                        val durationSec = result.writePos.toFloat() / TARGET_CH / outputRate
                        val stemMs = System.currentTimeMillis() - stemT0
                        Log.i(TAG, "${PREFIX}  done $fname, %.1fs, decoded+accumulated in ${stemMs}ms".format(durationSec))
                    } else {
                        Log.w(TAG, "${PREFIX}  SKIP $fname — no audio track or 0 samples")
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "${PREFIX}  EXCEPTION decoding $fname: ${t.javaClass.simpleName}: ${t.message}", t)
                    logHeap("after exception on $fname")
                }

                emitProgress(((idx + 1) * 80) / total, "Çözümleniyor: $stage")
            }

            if (cancelFlag.get()) {
                cleanup(channel, raf, tempFile, outputWav)
                emitFailed("Cancelled")
                return
            }

            if (decodedCount == 0) {
                val msg = "No files decoded successfully out of $total"
                Log.e(TAG, "$PREFIX$msg")
                cleanup(channel, raf, tempFile, null)
                emitFailed(msg)
                return
            }

            logHeap("after all decodes")
            emitProgress(85, "Normalize ediliyor...")

            // 4. Peak scan
            var peak = 0f
            for (i in 0 until actualLen) {
                val a = abs(floatBuf.get(i))
                if (a > peak) peak = a
            }
            val normalized = peak > 32767f
            Log.i(TAG, "${PREFIX}peak=%.1f, normalized=$normalized, accumLen=$actualLen".format(peak))

            if (cancelFlag.get()) {
                cleanup(channel, raf, tempFile, outputWav)
                emitFailed("Cancelled")
                return
            }

            emitProgress(90, "WAV yazılıyor...")

            // 5. Write WAV (using source's actual sample rate — no resampling)
            writeWavFromMapped(floatBuf, actualLen, peak, normalized, outputWav, outputRate)

            // 6. Cleanup temp file
            try { channel.close() } catch (_: Throwable) {}
            try { raf.close() } catch (_: Throwable) {}
            try { tempFile.delete() } catch (_: Throwable) {}
            channel = null; raf = null; tempFile = null

            val elapsed = System.currentTimeMillis() - t0
            Log.i(TAG, "${PREFIX}mixed $decodedCount stems (preview excluded) in ${elapsed}ms, rate=${outputRate}Hz, peak=%.1f, normalized=$normalized, RAM stable".format(peak))
            logHeap("finished")

            emitProgress(100, "Tamamlandı")
            emitDone(outputWav)

        } catch (t: Throwable) {
            val rt = Runtime.getRuntime()
            val usedMB = (rt.totalMemory() - rt.freeMemory()) / 1024 / 1024
            val totalMB = rt.totalMemory() / 1024 / 1024
            val maxMB = rt.maxMemory() / 1024 / 1024
            val msg = "decodeAndMix crashed: ${t.javaClass.simpleName}: ${t.message} " +
                      "[heap: used=${usedMB}MB, total=${totalMB}MB, max=${maxMB}MB]"
            Log.e(TAG, "$PREFIX$msg", t)
            cleanup(channel, raf, tempFile, outputWav)
            emitFailed(msg)

        } finally {
            // Safety net cleanup
            try { channel?.close() } catch (_: Throwable) {}
            try { raf?.close() } catch (_: Throwable) {}
            try { tempFile?.delete() } catch (_: Throwable) {}
        }
    }

    /** Clean up temp + partial output files. */
    private fun cleanup(channel: FileChannel?, raf: RandomAccessFile?, tempFile: File?, outputWav: String?) {
        try { channel?.close() } catch (_: Throwable) {}
        try { raf?.close() } catch (_: Throwable) {}
        try { tempFile?.delete() } catch (_: Throwable) {}
        if (outputWav != null) {
            try { File(outputWav).delete() } catch (_: Throwable) {}
        }
    }

    /** Emit signals safely on the render thread. */
    private fun emitProgress(pct: Int, stage: String) {
        try {
            runOnRenderThread { emitSignal("decode_progress", pct, stage) }
        } catch (e: Exception) {
            Log.w(TAG, "${PREFIX}emitSignal progress failed: ${e.message}")
        }
    }

    private fun emitDone(wavPath: String) {
        try {
            runOnRenderThread { emitSignal("decode_done", wavPath) }
        } catch (e: Exception) {
            Log.w(TAG, "${PREFIX}emitSignal done failed: ${e.message}")
        }
    }

    private fun emitFailed(error: String) {
        try {
            runOnRenderThread { emitSignal("decode_failed", error) }
        } catch (e: Exception) {
            Log.w(TAG, "${PREFIX}emitSignal failed failed: ${e.message}")
        }
    }

    /** Log current heap usage. */
    private fun logHeap(label: String) {
        val rt = Runtime.getRuntime()
        val usedMB = (rt.totalMemory() - rt.freeMemory()) / 1024 / 1024
        val maxMB = rt.maxMemory() / 1024 / 1024
        Log.i(TAG, "${PREFIX}heap [$label]: used=${usedMB}MB, max=${maxMB}MB")
    }

    /** Read audio sample rate from MediaFormat. Returns 0 if unavailable. */
    private fun getAudioSampleRate(path: String): Int {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    return fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "${PREFIX}getAudioSampleRate failed for $path: ${e.message}")
        } finally {
            extractor.release()
        }
        return 0
    }

    /** Read audio duration in microseconds from MediaFormat. Returns 0 if unavailable. */
    private fun getAudioDurationUs(path: String): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    return if (fmt.containsKey(MediaFormat.KEY_DURATION)) {
                        fmt.getLong(MediaFormat.KEY_DURATION)
                    } else 0L
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "${PREFIX}getAudioDurationUs failed for $path: ${e.message}")
        } finally {
            extractor.release()
        }
        return 0L
    }

    /**
     * Decode a single audio file chunk-by-chunk and accumulate directly into the
     * memory-mapped FloatBuffer. Checks cancelFlag periodically.
     *
     * @return total stereo samples written, or 0 on failure/cancel.
     */
    /**
     * Result from streamDecodeIntoMapped — carries both sample count and actual sample rate.
     */
    private data class DecodeResult(val writePos: Int, val actualRate: Int)

    private fun streamDecodeIntoMapped(
        filePath: String,
        floatBuf: FloatBuffer,
        maxSamples: Int,
        stemIdx: Int,
        totalStems: Int,
        expectedRate: Int
    ): DecodeResult {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null

        try {
            extractor.setDataSource(filePath)

            var format: MediaFormat? = null
            var trackIdx = -1
            for (i in 0 until extractor.trackCount) {
                val tf = extractor.getTrackFormat(i)
                val mime = tf.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIdx = i; format = tf; break
                }
            }
            if (trackIdx < 0 || format == null) return DecodeResult(0, expectedRate)

            val mime = format.getString(MediaFormat.KEY_MIME)!!
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val originalChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var channels = originalChannels
            Log.i(TAG, "${PREFIX}  track: $mime ${sampleRate}Hz ${channels}ch (expected output: ${expectedRate}Hz)")

            if (sampleRate != expectedRate) {
                Log.w(TAG, "${PREFIX}  WARNING: stem rate $sampleRate != expected $expectedRate — accumulating at native rate (no resample)")
            }

            // Get duration for intra-stem progress
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) else 0L

            extractor.selectTrack(trackIdx)
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var writePos = 0
            var lastProgressPct = -1
            val fname = File(filePath).name
            var totalSrcSamples = 0L
            var totalWrittenSamples = 0L

            while (!outputDone) {
                if (cancelFlag.get()) return DecodeResult(0, sampleRate)

                // Feed input
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        val read = extractor.readSampleData(inBuf, 0)
                        if (read < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, read, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // Drain output — no resampling, accumulate at native rate
                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx >= 0 -> {
                        if (info.size > 0 && writePos < maxSamples) {
                            val outBuf = codec.getOutputBuffer(outIdx)!!
                            outBuf.order(ByteOrder.LITTLE_ENDIAN)
                            val shortBuf = outBuf.asShortBuffer()
                            val shortCount = info.size / 2

                            totalSrcSamples += shortCount
                            val prevPos = writePos
                            writePos = accumulateChunk(shortBuf, shortCount, channels, floatBuf, writePos, maxSamples)
                            totalWrittenSamples += (writePos - prevPos)

                            // Intra-stem progress (~5% steps)
                            if (durationUs > 0 && info.presentationTimeUs >= 0) {
                                val stemPct = (info.presentationTimeUs * 100 / durationUs).toInt().coerceIn(0, 100)
                                val overallBase = (stemIdx * 80) / totalStems
                                val overallRange = 80 / totalStems
                                val overallPct = overallBase + (stemPct * overallRange / 100)
                                if (overallPct >= lastProgressPct + 5) {
                                    lastProgressPct = overallPct
                                    emitProgress(overallPct, "Çözümleniyor: $fname (${stemIdx + 1}/$totalStems)")
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val nf = codec.outputFormat
                        val newRate = nf.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val newCh = nf.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        Log.i(TAG, "${PREFIX}  format changed: ${newRate}Hz ${newCh}ch (was ${sampleRate}Hz ${channels}ch)")
                        // Update sample rate from codec output
                        if (newRate > 0) sampleRate = newRate
                        // GUARD: Don't trust 1ch when source is multi-channel.
                        // MediaCodec Vorbis decoder bug: reports 1ch but PCM data is still
                        // fully interleaved with all original channels.
                        if (newCh > 1) {
                            channels = newCh
                        } else if (originalChannels > 1) {
                            Log.w(TAG, "${PREFIX}  IGNORING 1ch report — keeping ${originalChannels}ch (MediaCodec Vorbis multi-ch bug)")
                            channels = originalChannels
                        } else {
                            channels = newCh
                        }
                    }
                }
            }

            val srcDurationSec = totalSrcSamples.toFloat() / channels / sampleRate
            val outDurationSec = totalWrittenSamples.toFloat() / TARGET_CH / sampleRate
            Log.i(TAG, "${PREFIX}  $fname: src=${totalSrcSamples} samples (${srcDurationSec}s @ ${sampleRate}Hz ${channels}ch), written=${totalWrittenSamples} stereo samples (${outDurationSec}s @ ${sampleRate}Hz)")

            return DecodeResult(writePos, sampleRate)

        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            extractor.release()
        }
    }

    /** Convert a chunk of interleaved shorts to stereo and accumulate into mapped FloatBuffer. */
    private fun accumulateChunk(
        shortBuf: java.nio.ShortBuffer, shortCount: Int, srcChannels: Int,
        floatBuf: FloatBuffer, startPos: Int, maxSamples: Int
    ): Int {
        var pos = startPos
        when (srcChannels) {
            TARGET_CH -> {
                for (i in 0 until shortCount) {
                    if (pos >= maxSamples) break
                    floatBuf.put(pos, floatBuf.get(pos) + shortBuf.get(i).toFloat())
                    pos++
                }
            }
            1 -> {
                for (i in 0 until shortCount) {
                    if (pos + 1 >= maxSamples) break
                    val s = shortBuf.get(i).toFloat()
                    floatBuf.put(pos, floatBuf.get(pos) + s)
                    floatBuf.put(pos + 1, floatBuf.get(pos + 1) + s)
                    pos += 2
                }
            }
            else -> {
                val frames = shortCount / srcChannels
                for (f in 0 until frames) {
                    if (pos + 1 >= maxSamples) break
                    var left = 0f; var right = 0f
                    for (c in 0 until srcChannels) {
                        val s = shortBuf.get(f * srcChannels + c).toFloat()
                        if (c % 2 == 0) left += s else right += s
                    }
                    floatBuf.put(pos, floatBuf.get(pos) + left)
                    floatBuf.put(pos + 1, floatBuf.get(pos + 1) + right)
                    pos += 2
                }
            }
        }
        return pos
    }

    /** Stream WAV output from the mapped FloatBuffer with on-the-fly normalization. */
    private fun writeWavFromMapped(
        floatBuf: FloatBuffer, accumLen: Int, peak: Float, normalized: Boolean, path: String, sampleRate: Int
    ) {
        val dataSize = accumLen * 2
        val byteRate = sampleRate * TARGET_CH * 2

        File(path).parentFile?.mkdirs()

        FileOutputStream(path).use { fos ->
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray())
            header.putInt(36 + dataSize)
            header.put("WAVE".toByteArray())
            header.put("fmt ".toByteArray())
            header.putInt(16)
            header.putShort(1)
            header.putShort(TARGET_CH.toShort())
            header.putInt(sampleRate)
            header.putInt(byteRate)
            header.putShort((TARGET_CH * 2).toShort())
            header.putShort(16)
            header.put("data".toByteArray())
            header.putInt(dataSize)
            fos.write(header.array())

            val chunkSamples = 32768
            var offset = 0
            while (offset < accumLen) {
                val end = min(offset + chunkSamples, accumLen)
                val count = end - offset
                val buf = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN)
                val sb = buf.asShortBuffer()
                if (normalized && peak > 0f) {
                    for (i in offset until end) {
                        sb.put(max(-32768, min(32767, (floatBuf.get(i) * 32767f / peak).toInt())).toShort())
                    }
                } else {
                    for (i in offset until end) {
                        sb.put(max(-32768, min(32767, floatBuf.get(i).toInt())).toShort())
                    }
                }
                fos.write(buf.array())
                offset = end
            }
        }
        val durationSec = accumLen / TARGET_CH / sampleRate
        Log.i(TAG, "${PREFIX}WAV written: $path (${dataSize / 1024}KB, ${durationSec}s @ ${sampleRate}Hz)")
    }

    /**
     * Synchronously decode a (possibly multi-channel) audio file to a stereo WAV.
     * Used during import to pre-convert MOGG multi-channel OGGs.
     * Returns "" on success, or error message on failure.
     */
    @UsedByGodot
    fun decodeToStereoWav(inputPath: String, outputWav: String): String {
        try {
            Log.i(TAG, "${PREFIX}decodeToStereoWav: $inputPath → $outputWav")

            val extractor = MediaExtractor()
            extractor.setDataSource(inputPath)

            var audioTrack = -1
            var mime = ""
            var sampleRate = 44100
            var channels = 2
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val m = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    audioTrack = i
                    mime = m
                    sampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    break
                }
            }
            if (audioTrack < 0) return "No audio track found"
            val originalChannels = channels
            Log.i(TAG, "${PREFIX}  source: $mime ${sampleRate}Hz ${channels}ch — will write WAV at ${sampleRate}Hz (no resample)")

            extractor.selectTrack(audioTrack)

            // Get duration for buffer sizing — use SOURCE rate, not a fixed target
            val format = extractor.getTrackFormat(audioTrack)
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) else 600_000_000L
            val durationSec = (durationUs / 1_000_000.0).toFloat()
            val maxFrames = ((durationSec + 10) * sampleRate).toInt()
            val maxSamples = maxFrames * TARGET_CH

            // Memory-mapped accumulator
            val tempFile = File.createTempFile("stereo_accum_", ".tmp", File(outputWav).parentFile)
            val fileSizeBytes = maxSamples.toLong() * 4
            val raf = RandomAccessFile(tempFile, "rw")
            raf.setLength(fileSizeBytes)
            val channel = raf.channel
            val mappedBuf = channel.map(FileChannel.MapMode.READ_WRITE, 0, fileSizeBytes)
            val floatBuf = mappedBuf.order(ByteOrder.nativeOrder()).asFloatBuffer()

            // Decode — no resampling, accumulate at native rate
            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var writePos = 0
            var actualChannels = channels
            var totalSrcSamples = 0L

            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        val read = extractor.readSampleData(inBuf, 0)
                        if (read < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, read, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx >= 0 -> {
                        val outBuf = codec.getOutputBuffer(outIdx)!!
                        outBuf.order(ByteOrder.LITTLE_ENDIAN)
                        val shortBuf = outBuf.asShortBuffer()
                        val shortCount = info.size / 2

                        if (shortCount > 0) {
                            totalSrcSamples += shortCount
                            writePos = accumulateChunk(shortBuf, shortCount, actualChannels, floatBuf, writePos, maxSamples)
                        }

                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        val newRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val newCh = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        Log.i(TAG, "${PREFIX}  format changed: ${newRate}Hz ${newCh}ch (was ${sampleRate}Hz ${actualChannels}ch)")
                        if (newRate > 0) sampleRate = newRate
                        // GUARD: Don't trust 1ch when source is multi-channel (Vorbis decoder bug)
                        if (newCh > 1) {
                            actualChannels = newCh
                        } else if (originalChannels > 1) {
                            Log.w(TAG, "${PREFIX}  IGNORING 1ch report — keeping ${originalChannels}ch (MediaCodec Vorbis multi-ch bug)")
                            actualChannels = originalChannels
                        } else {
                            actualChannels = newCh
                        }
                    }
                }
            }

            codec.stop()
            codec.release()
            extractor.release()

            // Find peak for normalization
            var peak = 0f
            for (i in 0 until writePos) {
                val v = abs(floatBuf.get(i))
                if (v > peak) peak = v
            }
            val shouldNormalize = peak > 32767f

            // Write WAV with SOURCE sample rate
            writeWavFromMapped(floatBuf, writePos, peak, shouldNormalize, outputWav, sampleRate)

            // Cleanup temp
            try { channel.close() } catch (_: Throwable) {}
            try { raf.close() } catch (_: Throwable) {}
            try { tempFile.delete() } catch (_: Throwable) {}

            val outDurationSec = writePos.toFloat() / TARGET_CH / sampleRate
            Log.i(TAG, "${PREFIX}decodeToStereoWav done: src=${totalSrcSamples} samples (${actualChannels}ch), out=${writePos} stereo samples, ${outDurationSec}s @ ${sampleRate}Hz, peak=$peak, normalized=$shouldNormalize")
            return ""
        } catch (e: Throwable) {
            Log.e(TAG, "${PREFIX}decodeToStereoWav failed: ${e.message}", e)
            return e.message ?: "Unknown error"
        }
    }

    // ==================== MOGG Decryption ====================

    private val CTR_KEY_0B = byteArrayOf(
        0x37, 0xb2.toByte(), 0xe2.toByte(), 0xb9.toByte(), 0x1c, 0x74, 0xfa.toByte(), 0x9e.toByte(),
        0x38, 0x81.toByte(), 0x08, 0xea.toByte(), 0x36, 0x23, 0xdb.toByte(), 0xe4.toByte())

    private val HV_KEYS = mapOf(
        0x0C to byteArrayOf(0x01,0x22,0x00,0x38,0xd2.toByte(),0x01,0x78,0x8b.toByte(),0xdd.toByte(),0xcd.toByte(),0xd0.toByte(),0xf0.toByte(),0xfe.toByte(),0x3e,0x24,0x7f),
        0x0D to byteArrayOf(0x01,0x22,0x00,0x38,0xd2.toByte(),0x01,0x78,0x8b.toByte(),0xdd.toByte(),0xcd.toByte(),0xd0.toByte(),0xf0.toByte(),0xfe.toByte(),0x3e,0x24,0x7f),
        0x0E to byteArrayOf(0x51,0x73,0xad.toByte(),0xe5.toByte(),0xb3.toByte(),0x99.toByte(),0xb8.toByte(),0x61,0x58,0x1a,0xf9.toByte(),0xb8.toByte(),0x1e,0xa7.toByte(),0xbe.toByte(),0xbf.toByte()),
        0x0F to byteArrayOf(0xc6.toByte(),0x22,0x94.toByte(),0x30,0xd8.toByte(),0x3c,0x84.toByte(),0x14,0x08,0x73,0x7c,0xf2.toByte(),0x23,0xf6.toByte(),0xeb.toByte(),0x5a),
        0x10 to byteArrayOf(0x02,0x1a,0x83.toByte(),0xf3.toByte(),0x97.toByte(),0xe9.toByte(),0xd4.toByte(),0xb8.toByte(),0x06,0x74,0x14,0x6b,0x30,0x4c,0x00,0x91.toByte()),
    )

    private val HIDDEN_KEYS = arrayOf(
        intArrayOf(0x7f,0x95,0x5b,0x9d,0x94,0xba,0x12,0xf1,0xd7,0x5a,0x67,0xd9,0x16,0x45,0x28,0xdd,0x61,0x55,0x55,0xaf,0x23,0x91,0xd6,0x0a,0x3a,0x42,0x81,0x18,0xb4,0xf7,0xf3,0x04),
        intArrayOf(0x78,0x96,0x5d,0x92,0x92,0xb0,0x47,0xac,0x8f,0x5b,0x6d,0xdc,0x1c,0x41,0x7e,0xda,0x6a,0x55,0x53,0xaf,0x20,0xc8,0xdc,0x0a,0x66,0x43,0xdd,0x1c,0xb2,0xa5,0xa4,0x0c),
        intArrayOf(0x7e,0x92,0x5c,0x93,0x90,0xed,0x4a,0xad,0x8b,0x07,0x36,0xd3,0x10,0x41,0x78,0x8f,0x60,0x08,0x55,0xa8,0x26,0xcf,0xd0,0x0f,0x65,0x11,0x84,0x45,0xb1,0xa0,0xfa,0x57),
        intArrayOf(0x79,0x97,0x0b,0x90,0x92,0xb0,0x44,0xad,0x8a,0x0e,0x60,0xd9,0x14,0x11,0x7e,0x8d,0x35,0x5d,0x5c,0xfb,0x21,0x9c,0xd3,0x0e,0x32,0x40,0xd1,0x48,0xb8,0xa7,0xa1,0x0d),
        intArrayOf(0x28,0xc3,0x5d,0x97,0xc1,0xec,0x42,0xf1,0xdc,0x5d,0x37,0xda,0x14,0x47,0x79,0x8a,0x32,0x5c,0x54,0xf2,0x72,0x9d,0xd3,0x0d,0x67,0x4c,0xd6,0x49,0xb4,0xa2,0xf3,0x50),
        intArrayOf(0x28,0x96,0x5e,0x95,0xc5,0xe9,0x45,0xad,0x8a,0x5d,0x64,0x8e,0x17,0x40,0x2e,0x87,0x36,0x58,0x06,0xfd,0x75,0x90,0xd0,0x5f,0x3a,0x40,0xd4,0x4c,0xb0,0xf7,0xa7,0x04),
        intArrayOf(0x2c,0x96,0x01,0x96,0x9b,0xbc,0x15,0xa6,0xde,0x0e,0x65,0x8d,0x17,0x47,0x2f,0xdd,0x63,0x54,0x55,0xaf,0x76,0xca,0x84,0x5f,0x62,0x44,0x80,0x4a,0xb3,0xf4,0xf4,0x0c),
        intArrayOf(0x7e,0xc4,0x0e,0xc6,0x9a,0xeb,0x43,0xa0,0xdb,0x0a,0x64,0xdf,0x1c,0x42,0x24,0x89,0x63,0x5c,0x55,0xf3,0x71,0x90,0xdc,0x5d,0x60,0x40,0xd1,0x4d,0xb2,0xa3,0xa7,0x0d),
        intArrayOf(0x2c,0x9a,0x0b,0x90,0x9a,0xbe,0x47,0xa7,0x88,0x5a,0x6d,0xdf,0x13,0x1d,0x2e,0x8b,0x60,0x5e,0x55,0xf2,0x74,0x9c,0xd7,0x0e,0x60,0x40,0x80,0x1c,0xb7,0xa1,0xf4,0x02),
        intArrayOf(0x28,0x96,0x5b,0x95,0xc1,0xe9,0x40,0xa3,0x8f,0x0c,0x32,0xdf,0x43,0x1d,0x24,0x8d,0x61,0x09,0x54,0xab,0x27,0x9a,0xd3,0x58,0x60,0x16,0x84,0x4f,0xb3,0xa4,0xf3,0x0d),
        intArrayOf(0x25,0x93,0x08,0xc0,0x9a,0xbd,0x10,0xa2,0xd6,0x09,0x60,0x8f,0x11,0x1d,0x7a,0x8f,0x63,0x0b,0x5d,0xf2,0x21,0xec,0xd7,0x08,0x62,0x40,0x84,0x49,0xb0,0xad,0xf2,0x07),
        intArrayOf(0x29,0xc3,0x0c,0x96,0x96,0xeb,0x10,0xa0,0xda,0x59,0x32,0xd3,0x17,0x41,0x25,0xdc,0x63,0x08,0x04,0xae,0x77,0xcb,0x84,0x5a,0x60,0x4d,0xdd,0x45,0xb5,0xf4,0xa0,0x05),
    )

    /**
     * Decrypt an encrypted Rock Band MOGG file to OGG.
     * Supports versions 0x0A (pass-through) to 0x10.
     * Returns "" on success, or error message on failure.
     * This runs synchronously — call from a worker thread.
     */
    @UsedByGodot
    fun decryptMogg(inputPath: String, outputPath: String): String {
        try {
            val inputFile = File(inputPath)
            if (!inputFile.exists()) return "Input file not found: $inputPath"
            val data = inputFile.readBytes()
            if (data.size < 8) return "File too small"

            val version = readU32LE(data, 0)
            Log.i(TAG, "${PREFIX}decryptMogg: version=0x${version.toString(16)}, size=${data.size}")

            if (version == 0x0A) {
                // Unencrypted — just strip header
                val oggOffset = readU32LE(data, 4)
                if (oggOffset >= data.size) return "OGG offset beyond file size"
                File(outputPath).parentFile?.mkdirs()
                FileOutputStream(outputPath).use { it.write(data, oggOffset, data.size - oggOffset) }
                Log.i(TAG, "${PREFIX}decryptMogg: unencrypted, wrote ${data.size - oggOffset} bytes")
                return ""
            }

            if (version < 0x0B || version > 0x10) return "Unsupported MOGG version 0x${version.toString(16)}"

            val oggOffset = readU32LE(data, 4)
            if (oggOffset >= data.size) return "OGG offset beyond file size"

            // Derive CTR key
            val ctrKey: ByteArray = if (version == 0x0B) {
                CTR_KEY_0B
            } else {
                val hvKey = HV_KEYS[version] ?: return "No HV key for version 0x${version.toString(16)}"
                genKey(hvKey, data, version) ?: return "Key derivation failed"
            }

            // Read nonce
            val hmxHeaderSize = readU32LE(data, 16)
            val nonceOffset = 20 + hmxHeaderSize * 8
            if (nonceOffset + 16 > data.size) return "Nonce offset out of bounds"
            val nonce = data.copyOfRange(nonceOffset, nonceOffset + 16)

            // Decrypt using AES-128 CTR (native javax.crypto — fast!)
            val encrypted = data.copyOfRange(oggOffset, data.size)
            val decrypted = aesCtrDecrypt(ctrKey, nonce, encrypted)

            // Check for HMXA header fixup
            var result = decrypted
            if (result.size >= 4 && result[0] == 0x48.toByte() && result[1] == 0x4D.toByte() &&
                result[2] == 0x58.toByte() && result[3] == 0x41.toByte()) {
                Log.i(TAG, "${PREFIX}decryptMogg: HMXA header detected, applying fixup")
                result = hmxaToOgg(result, data, hmxHeaderSize)
            }

            // Verify OggS magic
            if (result.size < 4 || result[0] != 0x4F.toByte() || result[1] != 0x67.toByte() ||
                result[2] != 0x67.toByte() || result[3] != 0x53.toByte()) {
                return "Decryption failed — no OggS magic (got ${result.take(4).joinToString(" ") { "%02X".format(it) }})"
            }

            File(outputPath).parentFile?.mkdirs()
            FileOutputStream(outputPath).use { it.write(result) }
            Log.i(TAG, "${PREFIX}decryptMogg: success! OGG=${result.size} bytes → $outputPath")
            return ""
        } catch (e: Throwable) {
            Log.e(TAG, "${PREFIX}decryptMogg failed: ${e.message}", e)
            return e.message ?: "Unknown error"
        }
    }

    private fun aesCtrDecrypt(key: ByteArray, nonce: ByteArray, data: ByteArray): ByteArray {
        // AES-128 CTR with little-endian counter increment
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))

        val result = data.copyOf()
        val counter = nonce.copyOf()
        val totalBlocks = (data.size + 15) / 16

        // Process in batches of 256 blocks for efficiency
        val batchSize = 256
        var processed = 0
        while (processed < totalBlocks) {
            val batch = min(batchSize, totalBlocks - processed)
            val counterBuf = ByteArray(batch * 16)
            for (b in 0 until batch) {
                System.arraycopy(counter, 0, counterBuf, b * 16, 16)
                // Increment 128-bit LE counter
                var carry = 1
                for (i in 0 until 16) {
                    if (carry == 0) break
                    val s = (counter[i].toInt() and 0xFF) + carry
                    counter[i] = (s and 0xFF).toByte()
                    carry = s shr 8
                }
            }

            val keystream = cipher.doFinal(counterBuf)

            val dataOffset = processed * 16
            val xorLen = min(batch * 16, data.size - dataOffset)
            for (i in 0 until xorLen) {
                result[dataOffset + i] = (result[dataOffset + i].toInt() xor keystream[i].toInt()).toByte()
            }
            processed += batch
        }
        return result
    }

    private fun genKey(hvKey: ByteArray, data: ByteArray, version: Int): ByteArray? {
        val hmxHeaderSize = readU32LE(data, 16)
        val baseOffset = 20 + hmxHeaderSize * 8 + 16

        // Read and decrypt key_mask
        val keyMaskOffset = baseOffset + 32
        if (keyMaskOffset + 16 > data.size) return null
        val keyMaskEncrypted = data.copyOfRange(keyMaskOffset, keyMaskOffset + 16)

        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(hvKey, "AES"))
        val keyMask = cipher.doFinal(keyMaskEncrypted)

        // Read magic values
        val magicA = readU32LE(data, baseOffset)
        val magicB = readU32LE(data, baseOffset + 8)

        // Read key index (Xbox: index % 6 + 6)
        var keyIndexOffset = baseOffset + 48
        if (version == 0x11) keyIndexOffset += 8
        if (keyIndexOffset + 8 > data.size) return null
        val keyIndexRaw = readU64LE(data, keyIndexOffset)
        val keyIndex = ((keyIndexRaw % 6) + 6).toInt()

        if (keyIndex >= HIDDEN_KEYS.size) return null
        val selectedKey = HIDDEN_KEYS[keyIndex]

        // Reveal key: 14x supershuffle then XOR with masher
        val masher = getMasher()
        val revealed = IntArray(32) { selectedKey[it] }
        repeat(14) { supershuffle(revealed) }
        for (i in 0 until 32) revealed[i] = revealed[i] xor (masher[i].toInt() and 0xFF)

        // Convert hex-string bytes to 16-byte key
        val hexKey = hexStringToBytes(revealed)

        // Grind array
        val ground = grindArray(magicA, magicB, hexKey, version)

        // XOR with key_mask
        val finalKey = ByteArray(16) { i -> (ground[i].toInt() xor keyMask[i].toInt()).toByte() }
        Log.i(TAG, "${PREFIX}genKey: magicA=%08X, magicB=%08X, idx=$keyIndex".format(magicA, magicB))
        return finalKey
    }

    private fun getMasher(): ByteArray {
        val result = ByteArray(32)
        var word = 0xEB
        for (idx in 0 until 8) {
            if (idx == 0) word = 0xEB
            word = ((word.toLong() * 0x19660E + 0x3C6EF35F) and 0xFFFFFFFFL).toInt()
            result[idx * 4] = (word and 0xFF).toByte()
            result[idx * 4 + 1] = ((word shr 8) and 0xFF).toByte()
            result[idx * 4 + 2] = ((word shr 16) and 0xFF).toByte()
            result[idx * 4 + 3] = ((word shr 24) and 0xFF).toByte()
        }
        return result
    }

    private fun supershuffle(key: IntArray) {
        shuffle1(key); shuffle2(key); shuffle3(key)
        shuffle4(key); shuffle5(key); shuffle6(key)
    }

    private fun roll(x: Int): Int = (x + 0x13) % 0x20

    private fun shuffle1(k: IntArray) {
        for (i in 0 until 8) {
            var off = roll(i * 4)
            var tmp = k[off]; k[off] = k[i * 4 + 2]; k[i * 4 + 2] = tmp
            off = roll(i * 4 + 3)
            tmp = k[off]; k[off] = k[i * 4 + 1]; k[i * 4 + 1] = tmp
        }
    }
    private fun shuffle2(k: IntArray) {
        for (i in 0 until 8) {
            var tmp = k[(7-i)*4+1]; k[(7-i)*4+1] = k[i*4+2]; k[i*4+2] = tmp
            tmp = k[(7-i)*4]; k[(7-i)*4] = k[i*4+3]; k[i*4+3] = tmp
        }
    }
    private fun shuffle3(k: IntArray) {
        for (i in 0 until 8) {
            val off = roll((7-i)*4+1)
            var tmp = k[off]; k[off] = k[i*4+2]; k[i*4+2] = tmp
            tmp = k[(7-i)*4]; k[(7-i)*4] = k[i*4+3]; k[i*4+3] = tmp
        }
    }
    private fun shuffle4(k: IntArray) {
        for (i in 0 until 8) {
            var tmp = k[(7-i)*4+1]; k[(7-i)*4+1] = k[i*4+2]; k[i*4+2] = tmp
            val off = roll((7-i)*4)
            tmp = k[off]; k[off] = k[i*4+3]; k[i*4+3] = tmp
        }
    }
    private fun shuffle5(k: IntArray) {
        for (i in 0 until 8) {
            val off = roll(i*4+2)
            var tmp = k[(7-i)*4+1]; k[(7-i)*4+1] = k[off]; k[off] = tmp
            tmp = k[(7-i)*4]; k[(7-i)*4] = k[i*4+3]; k[i*4+3] = tmp
        }
    }
    private fun shuffle6(k: IntArray) {
        for (i in 0 until 8) {
            var tmp = k[(7-i)*4+1]; k[(7-i)*4+1] = k[i*4+2]; k[i*4+2] = tmp
            val off = roll(i*4+3)
            tmp = k[(7-i)*4]; k[(7-i)*4] = k[off]; k[off] = tmp
        }
    }

    private fun hexStringToBytes(s: IntArray): ByteArray {
        val result = ByteArray(16)
        for (i in 0 until 16) {
            val hi = asciiHexDigit(s[i * 2])
            val lo = asciiHexDigit(s[i * 2 + 1])
            result[i] = ((hi * 16 + lo) and 0xFF).toByte()
        }
        return result
    }

    private fun asciiHexDigit(h: Int): Int {
        return when {
            h in 0x61..0x66 -> h - 87  // a-f
            h in 0x41..0x46 -> h - 55  // A-F
            else -> (h - 0x30) and 0xFF // 0-9
        }
    }

    private fun lcg(x: Int): Int = ((x.toLong() * 0x19660D + 0x3C6EF35F) and 0xFFFFFFFFL).toInt()

    private fun grindArray(magicAIn: Int, magicBIn: Int, keyIn: ByteArray, version: Int): ByteArray {
        val key = keyIn.copyOf()
        val magicA = magicAIn
        var magicB = magicBIn

        // Build array2 from magic_a
        val array2 = IntArray(256)
        var ma = magicA
        for (i in 0 until 256) {
            array2[i] = ((ma and 0xFF) ushr 3)
            ma = lcg(ma)
        }

        if (magicB == 0) magicB = 0x303F

        // Build shuffle order array1
        val arrayUsed = IntArray(64)
        val array1 = IntArray(64)
        var mb = magicB
        for (i in 0 until 0x20) {
            var num: Int
            while (true) {
                mb = lcg(mb)
                num = (mb ushr 2) and 0x1F
                if (arrayUsed[num] == 0) break
            }
            array1[i] = num
            arrayUsed[num] = 1
        }

        var array3 = array2.copyOf()

        // Build array4 from magic_b (original)
        val array4 = IntArray(256)
        var ma2 = magicBIn
        for (i in 0 until 256) {
            array4[i] = ((ma2 and 0xFF) ushr 2) and 0x3F
            ma2 = lcg(ma2)
        }

        if (version > 13) {
            var num1 = magicAIn
            for (i in 32 until 64) {
                var num: Int
                while (true) {
                    num1 = lcg(num1)
                    num = ((num1 ushr 2) and 0x1F) + 0x20
                    if (arrayUsed[num] == 0) break
                }
                array1[i] = num
                arrayUsed[num] = 1
            }
            array3 = array4
        }

        // Apply o_funcs
        for (j in 0 until 16) {
            var num3 = key[j].toInt() and 0xFF
            for (k in 0 until 16 step 2) {
                val lookupIdx = key[k].toInt() and 0xFF
                val opIdx = if (lookupIdx < 256) array3[lookupIdx] else 0
                val op = if (opIdx < 64) array1[opIdx] else 0
                num3 = oFunc(num3, key[k + 1].toInt() and 0xFF, op)
            }
            key[j] = (num3 and 0xFF).toByte()
        }

        return key
    }

    private fun rotr8(x: Int, n: Int): Int {
        val v = x and 0xFF; val s = n and 7
        return ((v ushr s) or (v shl (8 - s))) and 0xFF
    }
    private fun rotl8(x: Int, n: Int): Int {
        val v = x and 0xFF; val s = n and 7
        return ((v shl s) or (v ushr (8 - s))) and 0xFF
    }

    private fun oFunc(a1In: Int, a2In: Int, op: Int): Int {
        val a1 = a1In and 0xFF
        val a2 = a2In and 0xFF
        val notA1 = if (a1 == 0) 1 else 0
        val notA2 = if (a2 == 0) 1 else 0
        val ret = when (op) {
            0 -> a2 + rotr8(a1, notA2)
            1 -> a2 + rotr8(a1, 3)
            2 -> a2 + rotl8(a1, 1)
            3 -> a2 xor (((a1 shr (a2 and 7)) or (a1 shl ((-a2) and 7))) and 0xFF)
            4 -> a2 xor rotl8(a1, 4)
            5 -> a2 + (a2 xor rotr8(a1, 3))
            6 -> a2 + rotl8(a1, 2)
            7 -> a2 + notA1
            8 -> a2 xor rotr8(a1, notA2)
            9 -> a2 xor ((a2 + rotl8(a1, 3)) and 0xFF)
            10 -> a2 + rotl8(a1, 3)
            11 -> a2 + rotl8(a1, 4)
            12 -> a1 xor a2
            13 -> a2 xor notA1
            14 -> a2 xor ((a2 + rotr8(a1, 3)) and 0xFF)
            15 -> a2 xor rotl8(a1, 3)
            16 -> a2 xor rotl8(a1, 2)
            17 -> a2 + (a2 xor rotl8(a1, 3))
            18 -> a2 + (a1 xor a2)
            19 -> a1 + a2
            20 -> a2 xor rotr8(a1, 3)
            21 -> a2 xor ((a1 + a2) and 0xFF)
            22 -> rotr8(a1, notA2)
            23 -> a2 + rotr8(a1, 1)
            24 -> ((a1 shr (a2 and 7)) or (a1 shl ((-a2) and 7))) and 0xFF
            25 -> if (a1 == 0) { if (a2 == 0) 128 else 1 } else 0
            26 -> a2 + rotr8(a1, 2)
            27 -> a2 xor rotr8(a1, 1)
            28 -> oFunc((a1.inv()) and 0xFF, a2In, 24)
            29 -> a2 xor rotr8(a1, 2)
            30 -> a2 + (((a1 shr (a2 and 7)) or (a1 shl ((-a2) and 7))) and 0xFF)
            31 -> a2 xor rotl8(a1, 1)
            32 -> (((a1 shl 8) or 170 or (a1 xor 255)) shr 4) xor a2
            33 -> (((a1 xor 255) or (a1 shl 8)) shr 3) xor a2
            34 -> (((a1 shl 8) xor 0xFF00 or a1) shr 2) xor a2
            35 -> (((a1 xor 92) or (a1 shl 8)) shr 5) xor a2
            36 -> (((a1 shl 8) or 101 or (a1 xor 60)) shr 2) xor a2
            37 -> (((a1 xor 54) or (a1 shl 8)) shr 2) xor a2
            38 -> (((a1 xor 54) or (a1 shl 8)) shr 4) xor a2
            39 -> (((a1 xor 92) or (a1 shl 8) or 54) shr 1) xor a2
            40 -> (((a1 xor 255) or (a1 shl 8)) shr 5) xor a2
            41 -> ((((a1.inv()) and 0xFF) shl 8 or a1) shr 6) xor a2
            42 -> (((a1 xor 92) or (a1 shl 8)) shr 3) xor a2
            43 -> (((a1 xor 60) or 101 or (a1 shl 8)) shr 5) xor a2
            44 -> (((a1 xor 54) or (a1 shl 8)) shr 1) xor a2
            45 -> (((a1 xor 101) or (a1 shl 8) or 60) shr 6) xor a2
            46 -> (((a1 xor 92) or (a1 shl 8)) shr 2) xor a2
            47 -> (((a2 xor 170) or (a2 shl 8) or 255) shr 3) xor a1
            48 -> (((a1 xor 99) or (a1 shl 8) or 92) shr 6) xor a2
            49 -> (((a1 xor 92) or (a1 shl 8) or 54) shr 7) xor a2
            50 -> (((a1 xor 92) or (a1 shl 8)) shr 6) xor a2
            51 -> (((a1 shl 8) xor 0xFF00 or a1) shr 3) xor a2
            52 -> (((a1 xor 255) or (a1 shl 8)) shr 6) xor a2
            53 -> (((a1 shl 8) xor 0xFF00 or a1) shr 5) xor a2
            54 -> (((a1 xor 60) or 101 or (a1 shl 8)) shr 4) xor a2
            55 -> (((a1 xor 99) or (a1 shl 8) or 92) shr 3) xor a2
            56 -> (((a1 xor 99) or (a1 shl 8) or 92) shr 5) xor a2
            57 -> (((a1 xor 175) or (a1 shl 8) or 250) shr 5) xor a2
            58 -> (((a1 xor 92) or (a1 shl 8) or 54) shr 5) xor a2
            59 -> (((a1 xor 92) or (a1 shl 8) or 54) shr 3) xor a2
            60 -> (((a1 xor 54) or (a1 shl 8)) shr 3) xor a2
            61 -> (((a1 xor 99) or (a1 shl 8) or 92) shr 4) xor a2
            62 -> (((a1 xor 255) or (a1 shl 8) or 175) shr 6) xor a2
            63 -> (((a1 xor 255) or (a1 shl 8)) shr 2) xor a2
            else -> 0
        }
        return ret and 0xFF
    }

    private fun hmxaToOgg(decrypted: ByteArray, moggData: ByteArray, numEntries: Int): ByteArray {
        val result = decrypted.copyOf()
        val baseOffset = 20 + numEntries * 8 + 16
        val magicA = readU32LE(moggData, baseOffset)
        val magicB = readU32LE(moggData, baseOffset + 8)

        val magicHashA = lcg(lcg(magicA xor 0x5C5C5C5C.toInt()))
        val magicHashB = lcg(magicB xor 0x36363636)

        // Replace HMXA with OggS
        result[0] = 0x4F; result[1] = 0x67; result[2] = 0x67; result[3] = 0x53

        // XOR at offset 12 (4 bytes BE)
        if (result.size >= 16) {
            var valA = ((result[12].toInt() and 0xFF) shl 24) or ((result[13].toInt() and 0xFF) shl 16) or
                       ((result[14].toInt() and 0xFF) shl 8) or (result[15].toInt() and 0xFF)
            valA = valA xor magicHashA
            result[12] = ((valA shr 24) and 0xFF).toByte()
            result[13] = ((valA shr 16) and 0xFF).toByte()
            result[14] = ((valA shr 8) and 0xFF).toByte()
            result[15] = (valA and 0xFF).toByte()
        }

        // XOR at offset 20 (4 bytes BE)
        if (result.size >= 24) {
            var valB = ((result[20].toInt() and 0xFF) shl 24) or ((result[21].toInt() and 0xFF) shl 16) or
                       ((result[22].toInt() and 0xFF) shl 8) or (result[23].toInt() and 0xFF)
            valB = valB xor magicHashB
            result[20] = ((valB shr 24) and 0xFF).toByte()
            result[21] = ((valB shr 16) and 0xFF).toByte()
            result[22] = ((valB shr 8) and 0xFF).toByte()
            result[23] = (valB and 0xFF).toByte()
        }

        return result
    }

    private fun readU32LE(data: ByteArray, offset: Int): Int {
        return (data[offset].toInt() and 0xFF) or
               ((data[offset + 1].toInt() and 0xFF) shl 8) or
               ((data[offset + 2].toInt() and 0xFF) shl 16) or
               ((data[offset + 3].toInt() and 0xFF) shl 24)
    }

    private fun readU64LE(data: ByteArray, offset: Int): Long {
        return (readU32LE(data, offset).toLong() and 0xFFFFFFFFL) or
               ((readU32LE(data, offset + 4).toLong() and 0xFFFFFFFFL) shl 32)
    }

    // ==================== End MOGG Decryption ====================

    /**
     * Copy a content:// URI to a local file path.
     * Returns the original display name of the file, or "" on failure.
     */
    @UsedByGodot
    fun copyContentUri(contentUri: String, destPath: String): String {
        try {
            val uri = android.net.Uri.parse(contentUri)
            val context = activity ?: return ""
            val resolver = context.contentResolver

            // Get display name
            var displayName = "unknown"
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        displayName = cursor.getString(idx) ?: "unknown"
                    }
                }
            }
            Log.i(TAG, "${PREFIX}copyContentUri: $displayName → $destPath")

            // Copy content
            val destFile = File(destPath)
            destFile.parentFile?.mkdirs()
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            } ?: run {
                Log.e(TAG, "${PREFIX}copyContentUri: cannot open input stream")
                return ""
            }

            Log.i(TAG, "${PREFIX}copyContentUri: done, ${destFile.length() / 1024}KB")
            return displayName
        } catch (e: Throwable) {
            Log.e(TAG, "${PREFIX}copyContentUri failed: ${e.message}")
            return ""
        }
    }

    /**
     * Open Android file picker that allows selecting ANY file type.
     * Uses ACTION_GET_CONTENT which bypasses Samsung file type restrictions.
     * Result delivered via "files_picked" signal (semicolon-separated content URIs).
     */
    @UsedByGodot
    fun openFilePicker() {
        val act = activity ?: run {
            Log.e(TAG, "${PREFIX}openFilePicker: no activity")
            runOnRenderThread { emitSignal("files_picked", "") }
            return
        }
        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "*/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            act.startActivityForResult(Intent.createChooser(intent, "Sarki Dosyasi Sec"), PICK_FILES_REQUEST)
            Log.i(TAG, "${PREFIX}openFilePicker: launched")
        } catch (e: Throwable) {
            Log.e(TAG, "${PREFIX}openFilePicker failed: ${e.message}")
            runOnRenderThread { emitSignal("files_picked", "") }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILES_REQUEST) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.i(TAG, "${PREFIX}file picker cancelled")
            runOnRenderThread { emitSignal("files_picked", "") }
            return
        }

        val uris = mutableListOf<String>()
        // Multiple selection
        val clipData = data.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                uris.add(clipData.getItemAt(i).uri.toString())
            }
        } else {
            // Single selection
            data.data?.let { uris.add(it.toString()) }
        }

        val result = uris.joinToString(";")
        Log.i(TAG, "${PREFIX}file picker result: ${uris.size} files")
        runOnRenderThread { emitSignal("files_picked", result) }
    }
}
