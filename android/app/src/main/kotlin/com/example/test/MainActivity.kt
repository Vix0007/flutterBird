package com.example.test

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Plays the short sound effects the Dart code synthesizes (16-bit mono PCM).
// No plugins or packages needed: Dart sends the samples once ("load"),
// then asks for them by name ("play").
class MainActivity : FlutterActivity() {
    private val sampleRate = 22050
    private val sounds = HashMap<String, ByteArray>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy/sfx")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> {
                        val name = call.argument<String>("name")
                        val data = call.argument<ByteArray>("data")
                        if (name != null && data != null && data.size >= 2) {
                            sounds[name] = data
                            result.success(null)
                        } else {
                            result.error("bad_args", "name or data missing", null)
                        }
                    }
                    "musicLoad" -> {
                        val data = call.arguments as? ByteArray
                        if (data != null && data.size >= 2) {
                            loadMusic(data)
                            result.success(null)
                        } else {
                            result.error("bad_args", "music data missing", null)
                        }
                    }
                    "musicStart" -> {
                        try { music?.play() } catch (e: Exception) { }
                        result.success(null)
                    }
                    "musicStop" -> {
                        try { music?.pause() } catch (e: Exception) { }
                        result.success(null)
                    }
                    "play" -> {
                        val data = (call.arguments as? String)?.let { sounds[it] }
                        if (data != null) play(data)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        keys = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy/keys")

        // Remembers the best score between app launches (no plugin needed).
        val prefs = getSharedPreferences("flappy", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy/save")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBest" -> result.success(prefs.getInt("best", 0))
                    "setBest" -> {
                        prefs.edit().putInt("best", (call.arguments as? Int) ?: 0).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var music: AudioTrack? = null
    private var keys: MethodChannel? = null

    // Android can swallow the first Esc before Flutter sees it, so catch it
    // here and tell the game ourselves.
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.keyCode == android.view.KeyEvent.KEYCODE_ESCAPE) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                keys?.invokeMethod("escape", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // The background tune: one static buffer that loops forever.
    private fun loadMusic(data: ByteArray) {
        try {
            music?.release()
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(data.size)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track.write(data, 0, data.size)
            track.setLoopPoints(0, data.size / 2, -1)
            music = track
        } catch (e: Exception) {
            music = null
        }
    }

    override fun onDestroy() {
        try { music?.release() } catch (e: Exception) { }
        super.onDestroy()
    }

    private fun play(data: ByteArray) {
        Thread {
            var track: AudioTrack? = null
            try {
                track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(data.size)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()
                track.write(data, 0, data.size)
                track.play()
                // wait for the sound to finish, then free the player
                Thread.sleep(data.size / 2 * 1000L / sampleRate + 100)
                Log.d("sfx", "played ${data.size / 2} frames, device consumed ${track.playbackHeadPosition}")
            } catch (e: Exception) {
                // a missed sound effect must never crash the game
            } finally {
                try {
                    track?.release()
                } catch (e: Exception) {
                }
            }
        }.start()
    }
}
