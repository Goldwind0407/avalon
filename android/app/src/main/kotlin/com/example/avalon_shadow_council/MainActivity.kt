package com.example.avalon_shadow_council

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import android.media.AudioAttributes
import android.media.SoundPool
import java.io.File

class MainActivity : FlutterActivity() {
    private var pool: SoundPool? = null
    private val samples = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()
    private val pending = mutableMapOf<Int, Pair<Float, Boolean>>()
    private val streams = mutableListOf<Int>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "avalon/sound_effects")
            .setMethodCallHandler { call, result ->
                if (call.method == "stop") { stopSounds(); result.success(null) }
                else if (call.method == "play") {
                    val name = call.argument<String>("name")
                    if (name == null || !name.matches(Regex("[a-zA-Z]+"))) {
                        result.error("invalid_sound", "Unknown sound", null)
                    } else try {
                        val volume = (call.argument<Double>("volume") ?: 0.6).toFloat().coerceIn(0f, 1f)
                        val important = call.argument<Boolean>("important") ?: false
                        playSound(name, volume, important)
                        result.success(null)
                    } catch (e: Exception) { result.error("sound_error", e.message, null) }
                } else result.notImplemented()
            }
    }

    private fun soundPool(): SoundPool {
        return pool ?: SoundPool.Builder().setMaxStreams(3).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        ).build().also { p ->
            pool = p
            p.setOnLoadCompleteListener { _, sample, status ->
                val request = pending.remove(sample)
                if (status == 0) {
                    ready.add(sample)
                    if (request != null) startSample(sample, request.first, request.second)
                } else samples.entries.removeAll { it.value == sample }
            }
        }
    }
    private fun playSound(name: String, volume: Float, important: Boolean) {
        val p = soundPool()
        if (important) stopSounds()
        val sample = samples.getOrPut(name) {
            val asset = FlutterInjector.instance().flutterLoader()
                .getLookupKeyForAsset("assets/audio/$name.wav")
            val file = File(cacheDir, "avalon-sfx-$name.wav")
            assets.open(asset).use { input -> file.outputStream().use { input.copyTo(it) } }
            p.load(file.absolutePath, 1)
        }
        if (ready.contains(sample)) startSample(sample, volume, important)
        else pending[sample] = Pair(volume, important)
    }
    private fun startSample(sample: Int, volume: Float, important: Boolean) {
        if (important) stopSounds()
        while (streams.size >= 3) pool?.stop(streams.removeAt(0))
        val stream = pool?.play(sample, volume, volume, if (important) 2 else 1, 0, 1f) ?: 0
        if (stream != 0) streams.add(stream)
    }
    private fun stopSounds() {
        pending.clear()
        streams.forEach { pool?.stop(it) }
        streams.clear()
    }
    override fun onPause() { stopSounds(); super.onPause() }
    override fun onDestroy() {
        stopSounds(); pool?.release(); pool = null
        super.onDestroy()
    }
}
