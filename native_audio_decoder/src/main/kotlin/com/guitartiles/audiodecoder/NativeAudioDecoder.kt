package com.guitartiles.audiodecoder

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
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class NativeAudioDecoder(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "godot"
        private const val PREFIX = "NativeAudioDecoder: "
        private const val TARGET_RATE = 48000
        private const val TARGET_CH = 2
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

            // 1. Pre-scan max duration across all stems
            var maxDurationUs = 0L
            for (path in inputPaths) {
                val dur = getAudioDurationUs(path)
                if (dur > maxDurationUs) maxDurationUs = dur
            }
            if (maxDurationUs <= 0L) {
                maxDurationUs = 15L * 60 * 1_000_000
                Log.w(TAG, "${PREFIX}could not read duration, using 15 min fallback")
            }

            val maxFrames = ((maxDurationUs / 1_000_000.0 + 2.0) * TARGET_RATE * 1.05).toLong()
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
                    val stemLen = streamDecodeIntoMapped(path, floatBuf, maxSamples.toInt(), idx, total)
                    if (stemLen > 0) {
                        if (stemLen > actualLen) actualLen = stemLen
                        decodedCount++
                        val durationSec = stemLen.toFloat() / TARGET_CH / TARGET_RATE
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

            // 5. Write WAV
            writeWavFromMapped(floatBuf, actualLen, peak, normalized, outputWav)

            // 6. Cleanup temp file
            try { channel.close() } catch (_: Throwable) {}
            try { raf.close() } catch (_: Throwable) {}
            try { tempFile.delete() } catch (_: Throwable) {}
            channel = null; raf = null; tempFile = null

            val elapsed = System.currentTimeMillis() - t0
            Log.i(TAG, "${PREFIX}mixed $decodedCount stems (preview excluded) in ${elapsed}ms, peak=%.1f, normalized=$normalized, RAM stable".format(peak))
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
    private fun streamDecodeIntoMapped(
        filePath: String,
        floatBuf: FloatBuffer,
        maxSamples: Int,
        stemIdx: Int,
        totalStems: Int
    ): Int {
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
            if (trackIdx < 0 || format == null) return 0

            val mime = format.getString(MediaFormat.KEY_MIME)!!
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            Log.i(TAG, "${PREFIX}  track: $mime ${sampleRate}Hz ${channels}ch")

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
            val needsResample = sampleRate != TARGET_RATE
            var resampleSrcFraction = 0.0
            var lastProgressPct = -1
            val fname = File(filePath).name

            while (!outputDone) {
                if (cancelFlag.get()) return 0

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

                // Drain output
                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx >= 0 -> {
                        if (info.size > 0 && writePos < maxSamples) {
                            val outBuf = codec.getOutputBuffer(outIdx)!!
                            outBuf.order(ByteOrder.LITTLE_ENDIAN)
                            val shortBuf = outBuf.asShortBuffer()
                            val shortCount = info.size / 2

                            if (!needsResample) {
                                writePos = accumulateChunk(shortBuf, shortCount, channels, floatBuf, writePos, maxSamples)
                            } else {
                                val chunk = ShortArray(shortCount)
                                shortBuf.get(chunk)
                                val stereoChunk = chunkToStereo(chunk, channels)
                                val srcFrames = stereoChunk.size / TARGET_CH
                                val ratio = TARGET_RATE.toDouble() / sampleRate
                                var srcIdx = resampleSrcFraction
                                while (srcIdx < srcFrames - 1 && writePos + 1 < maxSamples) {
                                    val idx = srcIdx.toInt()
                                    val frac = (srcIdx - idx).toFloat()
                                    for (c in 0 until TARGET_CH) {
                                        val s0 = stereoChunk[idx * TARGET_CH + c].toFloat()
                                        val s1 = stereoChunk[(idx + 1) * TARGET_CH + c].toFloat()
                                        floatBuf.put(writePos, floatBuf.get(writePos) + s0 + frac * (s1 - s0))
                                        writePos++
                                    }
                                    srcIdx += 1.0 / ratio
                                }
                                resampleSrcFraction = srcIdx - (srcFrames - 1)
                                if (resampleSrcFraction < 0) resampleSrcFraction = 0.0
                            }

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
                        sampleRate = newRate
                        channels = newCh
                    }
                }
            }

            return writePos

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

    /** Convert a short chunk to stereo (small temp buffer). */
    private fun chunkToStereo(data: ShortArray, srcCh: Int): ShortArray {
        if (srcCh == TARGET_CH) return data
        if (srcCh == 1) {
            val out = ShortArray(data.size * 2)
            for (i in data.indices) { out[i * 2] = data[i]; out[i * 2 + 1] = data[i] }
            return out
        }
        val frames = data.size / srcCh
        val out = ShortArray(frames * 2)
        for (f in 0 until frames) {
            var left = 0; var right = 0
            for (c in 0 until srcCh) {
                val s = data[f * srcCh + c].toInt()
                if (c % 2 == 0) left += s else right += s
            }
            out[f * 2] = max(-32768, min(32767, left)).toShort()
            out[f * 2 + 1] = max(-32768, min(32767, right)).toShort()
        }
        return out
    }

    /** Stream WAV output from the mapped FloatBuffer with on-the-fly normalization. */
    private fun writeWavFromMapped(
        floatBuf: FloatBuffer, accumLen: Int, peak: Float, normalized: Boolean, path: String
    ) {
        val dataSize = accumLen * 2
        val byteRate = TARGET_RATE * TARGET_CH * 2

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
            header.putInt(TARGET_RATE)
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
        Log.i(TAG, "${PREFIX}WAV written: $path (${dataSize / 1024}KB, ${accumLen / TARGET_CH / TARGET_RATE}s)")
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
            var sampleRate = TARGET_RATE
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
            Log.i(TAG, "${PREFIX}  source: $mime ${sampleRate}Hz ${channels}ch")

            extractor.selectTrack(audioTrack)

            // Get duration for buffer sizing
            val format = extractor.getTrackFormat(audioTrack)
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) else 600_000_000L
            val durationSec = (durationUs / 1_000_000.0).toFloat()
            val maxFrames = ((durationSec + 10) * TARGET_RATE).toInt()
            val maxSamples = maxFrames * TARGET_CH

            // Memory-mapped accumulator
            val tempFile = File.createTempFile("stereo_accum_", ".tmp", File(outputWav).parentFile)
            val fileSizeBytes = maxSamples.toLong() * 4
            val raf = RandomAccessFile(tempFile, "rw")
            raf.setLength(fileSizeBytes)
            val channel = raf.channel
            val mappedBuf = channel.map(FileChannel.MapMode.READ_WRITE, 0, fileSizeBytes)
            val floatBuf = mappedBuf.order(ByteOrder.nativeOrder()).asFloatBuffer()

            // Decode
            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var writePos = 0
            var actualChannels = channels

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
                            writePos = accumulateChunk(shortBuf, shortCount, actualChannels, floatBuf, writePos, maxSamples)
                        }

                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        val newCh = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        Log.i(TAG, "${PREFIX}  format changed: ${newCh}ch (was ${actualChannels}ch)")
                        // Keep original channel count if MediaCodec wrongly reports 1ch for multi-ch
                        if (newCh > 1) {
                            actualChannels = newCh
                        }
                    }
                }
            }

            codec.stop()
            codec.release()
            extractor.release()

            // Find peak for normalization check
            var peak = 0f
            for (i in 0 until writePos) {
                val v = abs(floatBuf.get(i))
                if (v > peak) peak = v
            }

            // Write WAV
            writeWavFromMapped(floatBuf, writePos, peak, false, outputWav)

            // Cleanup temp
            try { channel.close() } catch (_: Throwable) {}
            try { raf.close() } catch (_: Throwable) {}
            try { tempFile.delete() } catch (_: Throwable) {}

            Log.i(TAG, "${PREFIX}decodeToStereoWav done: ${writePos / TARGET_CH / TARGET_RATE}s, peak=$peak")
            return ""
        } catch (e: Throwable) {
            Log.e(TAG, "${PREFIX}decodeToStereoWav failed: ${e.message}", e)
            return e.message ?: "Unknown error"
        }
    }

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
}
