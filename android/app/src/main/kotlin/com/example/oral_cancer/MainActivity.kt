package com.example.oral_cancer

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val speechPermissionRequestCode = 8401
    private val engineLock = Any()
    private var cachedEngine: Engine? = null
    private var cachedModelKey: String? = null
    private val yoloLock = Any()
    private var cachedYolo: Interpreter? = null
    private var cachedYoloPath: String? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechListening = false
    private var speechLanguageTag = "en-IN"
    private var pendingSpeechManual = false
    private val accumulatedSpeechText = StringBuilder()
    private var latestPartialSpeechText = ""
    private val speechHandler = Handler(Looper.getMainLooper())
    private var speechRestartRunnable: Runnable? = null
    private var consecutiveNoMatchRestarts = 0
    private var speechEventSink: EventChannel.EventSink? = null

    private fun logMemory(tag: String) {
        val runtime = Runtime.getRuntime()
        val usedMb = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
        val totalMb = runtime.totalMemory() / (1024 * 1024)
        val maxMb = runtime.maxMemory() / (1024 * 1024)
        Log.i(tag, "memory used=${usedMb}MB total=${totalMb}MB max=${maxMb}MB")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "oral_cancer/litert_lm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "infer" -> runLiteRtInference(call.arguments as? Map<*, *>, result)
                "close" -> closeLiteRtEngine(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "oral_cancer/yolo_prefilter"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "detect" -> runYoloDetection(call.arguments as? Map<*, *>, result)
                "close" -> closeYoloInterpreter(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "oral_cancer/speech_intake"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listenOnce" -> startSpeechRecognition(call.arguments as? Map<*, *>, result)
                "startListening" -> beginManualSpeechListening(call.arguments as? Map<*, *>, result)
                "stopListening" -> finishManualSpeechListening(result)
                "cancelListening" -> cancelManualSpeechListening(result)
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "oral_cancer/speech_intake_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                speechEventSink = events
                emitSpeechTranscript()
            }

            override fun onCancel(arguments: Any?) {
                speechEventSink = null
            }
        })
    }

    override fun onDestroy() {
        speechEventSink = null
        speechRecognizer?.destroy()
        speechRecognizer = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == speechPermissionRequestCode) {
            val result = pendingSpeechResult ?: return
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (pendingSpeechManual) {
                    beginSpeechRecognition(
                        mapOf("languageTag" to speechLanguageTag),
                        result,
                        manualMode = true,
                        completeImmediately = true
                    )
                } else {
                    beginSpeechRecognition(emptyMap<Any, Any>(), result, manualMode = false)
                }
            } else {
                pendingSpeechResult = null
                pendingSpeechManual = false
                result.error("AUDIO_PERMISSION_DENIED", "Microphone permission was denied.", null)
            }
        }
    }

    private fun startSpeechRecognition(args: Map<*, *>?, result: MethodChannel.Result) {
        if (!ensureSpeechPermission(result)) {
            return
        }
        beginSpeechRecognition(args ?: emptyMap<Any, Any>(), result, manualMode = false)
    }

    private fun beginManualSpeechListening(args: Map<*, *>?, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("SPEECH_UNAVAILABLE", "Speech recognition is not available on this device.", null)
            return
        }
        if (speechListening || pendingSpeechResult != null) {
            result.error("SPEECH_BUSY", "Speech recognition is already running.", null)
            return
        }
        speechLanguageTag = args?.get("languageTag") as? String ?: "en-IN"
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingSpeechResult = result
            pendingSpeechManual = true
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                speechPermissionRequestCode
            )
            return
        }
        beginSpeechRecognition(
            mapOf("languageTag" to speechLanguageTag),
            result,
            manualMode = true,
            completeImmediately = true
        )
    }

    private fun finishManualSpeechListening(result: MethodChannel.Result) {
        if (!speechListening) {
            result.error("SPEECH_NOT_ACTIVE", "Speech recognition is not running.", null)
            return
        }
        if (pendingSpeechResult != null) {
            result.error("SPEECH_BUSY", "Speech recognition is already finishing.", null)
            return
        }
        cancelScheduledSpeechRestart()
        pendingSpeechResult = result
        val accumulated = currentTranscript()
        if (accumulated.isNotEmpty()) {
            deliverSpeechSuccess(accumulated, listOf(accumulated))
            return
        }
        try {
            speechRecognizer?.stopListening()
        } catch (error: Throwable) {
            Log.e("OralCancerSpeech", "stopListening failed", error)
            deliverSpeechFailure(
                "SPEECH_RECOGNITION_FAILED",
                "Could not stop speech recognition.",
                SpeechRecognizer.ERROR_CLIENT
            )
        }
    }

    private fun cancelManualSpeechListening(result: MethodChannel.Result) {
        resetSpeechSession()
        result.success(null)
    }

    private fun resetSpeechSession() {
        cancelScheduledSpeechRestart()
        pendingSpeechResult = null
        speechListening = false
        consecutiveNoMatchRestarts = 0
        accumulatedSpeechText.clear()
        latestPartialSpeechText = ""
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    private fun cancelScheduledSpeechRestart() {
        speechRestartRunnable?.let { speechHandler.removeCallbacks(it) }
        speechRestartRunnable = null
    }

    private fun scheduleManualListenCycle(languageTag: String, delayMs: Long = 500L) {
        if (!speechListening || pendingSpeechResult != null) {
            return
        }
        cancelScheduledSpeechRestart()
        val runnable = Runnable {
            speechRestartRunnable = null
            if (!speechListening || pendingSpeechResult != null) {
                return@Runnable
            }
            beginManualListenCycle(languageTag)
        }
        speechRestartRunnable = runnable
        speechHandler.postDelayed(runnable, delayMs)
    }

    private fun beginManualListenCycle(languageTag: String) {
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).also { recognizer ->
            recognizer.setRecognitionListener(
                createSpeechRecognitionListener(languageTag, manualMode = true)
            )
            recognizer.startListening(buildSpeechIntent(languageTag, manualMode = true))
            Log.i("OralCancerSpeech", "listen cycle started")
        }
    }

    private fun buildSpeechIntent(languageTag: String, manualMode: Boolean): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak patient intake details")
            if (manualMode) {
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 120_000L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 120_000L)
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    120_000L
                )
            }
        }
    }

    private fun emitSpeechTranscript() {
        if (!speechListening) {
            return
        }
        val text = currentTranscript()
        runOnUiThread { speechEventSink?.success(text) }
    }

    private fun currentTranscript(): String {
        val base = accumulatedSpeechText.toString().trim()
        val partial = latestPartialSpeechText.trim()
        if (partial.isEmpty()) {
            return base
        }
        if (base.isEmpty()) {
            return partial
        }
        return if (base.endsWith(partial)) base else "$base $partial"
    }

    private fun appendSpeechResults(results: Bundle?) {
        val matches = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            .orEmpty()
        val text = matches.firstOrNull().orEmpty().trim()
        if (text.isEmpty()) {
            return
        }
        if (accumulatedSpeechText.isNotEmpty()) {
            accumulatedSpeechText.append(' ')
        }
        accumulatedSpeechText.append(text)
        latestPartialSpeechText = ""
        consecutiveNoMatchRestarts = 0
        Log.i(
            "OralCancerSpeech",
            "accumulated chars=${accumulatedSpeechText.length} segmentChars=${text.length}"
        )
        emitSpeechTranscript()
    }

    private fun deliverSpeechSuccess(text: String, alternatives: List<String>) {
        val pending = pendingSpeechResult ?: return
        cancelScheduledSpeechRestart()
        pendingSpeechResult = null
        speechListening = false
        consecutiveNoMatchRestarts = 0
        accumulatedSpeechText.clear()
        latestPartialSpeechText = ""
        speechRecognizer?.destroy()
        speechRecognizer = null
        Log.i("OralCancerSpeech", "delivered chars=${text.length}")
        pending.success(
            mapOf(
                "text" to text,
                "alternatives" to alternatives
            )
        )
    }

    private fun deliverSpeechFailure(code: String, message: String, errorValue: Int) {
        val pending = pendingSpeechResult ?: return
        cancelScheduledSpeechRestart()
        pendingSpeechResult = null
        speechListening = false
        consecutiveNoMatchRestarts = 0
        accumulatedSpeechText.clear()
        latestPartialSpeechText = ""
        speechRecognizer?.destroy()
        speechRecognizer = null
        Log.e("OralCancerSpeech", "failure message=$message")
        pending.error(code, message, errorValue)
    }

    private fun shouldRecoverManualSpeechError(error: Int): Boolean {
        return error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
            error == SpeechRecognizer.ERROR_CLIENT ||
            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY
    }

    private fun ensureSpeechPermission(result: MethodChannel.Result): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("SPEECH_UNAVAILABLE", "Speech recognition is not available on this device.", null)
            return false
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingSpeechResult = result
            pendingSpeechManual = false
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                speechPermissionRequestCode
            )
            return false
        }
        return true
    }

    private fun beginSpeechRecognition(
        args: Map<*, *>,
        result: MethodChannel.Result,
        manualMode: Boolean,
        completeImmediately: Boolean = false
    ) {
        if (!completeImmediately) {
            pendingSpeechResult = result
        }
        val languageTag = args["languageTag"] as? String ?: "en-IN"
        speechLanguageTag = languageTag
        if (manualMode) {
            accumulatedSpeechText.clear()
            latestPartialSpeechText = ""
            consecutiveNoMatchRestarts = 0
            speechListening = true
            cancelScheduledSpeechRestart()
            beginManualListenCycle(languageTag)
            if (completeImmediately) {
                result.success(null)
            }
            return
        }

        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.destroy()
        speechRecognizer = recognizer
        speechListening = false
        recognizer.setRecognitionListener(
            createSpeechRecognitionListener(languageTag, manualMode = false)
        )
        recognizer.startListening(buildSpeechIntent(languageTag, manualMode = false))
    }

    private fun createSpeechRecognitionListener(
        languageTag: String,
        manualMode: Boolean
    ): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.i("OralCancerSpeech", "ready language=$languageTag")
            }

            override fun onBeginningOfSpeech() {
                consecutiveNoMatchRestarts = 0
                Log.i("OralCancerSpeech", "beginning")
            }

            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() {
                Log.i("OralCancerSpeech", "end")
            }

            override fun onError(error: Int) {
                val pending = pendingSpeechResult
                val accumulated = accumulatedSpeechText.toString().trim()
                if (pending != null && accumulated.isNotEmpty() &&
                    shouldRecoverManualSpeechError(error)
                ) {
                    deliverSpeechSuccess(accumulated, listOf(accumulated))
                    return
                }
                if (pending != null && accumulated.isEmpty() &&
                    (error == SpeechRecognizer.ERROR_NO_MATCH ||
                        error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                        error == SpeechRecognizer.ERROR_CLIENT)
                ) {
                    deliverSpeechFailure(
                        "SPEECH_RECOGNITION_FAILED",
                        "No speech was recognized. Tap start, speak clearly, then tap stop.",
                        error
                    )
                    return
                }
                if (pending == null && manualMode && speechListening) {
                    if (error == SpeechRecognizer.ERROR_NO_MATCH) {
                        consecutiveNoMatchRestarts++
                        val delayMs = min(
                            2_000L,
                            500L + consecutiveNoMatchRestarts * 250L
                        )
                        Log.d(
                            "OralCancerSpeech",
                            "no-match pause; next cycle in ${delayMs}ms"
                        )
                        scheduleManualListenCycle(languageTag, delayMs)
                        return
                    }
                    if (shouldRecoverManualSpeechError(error)) {
                        Log.d("OralCancerSpeech", "recovering error=$error")
                        scheduleManualListenCycle(languageTag, 700L)
                        return
                    }
                }
                if (pending == null) {
                    return
                }
                val message = speechErrorMessage(error)
                Log.e("OralCancerSpeech", "error=$error message=$message")
                deliverSpeechFailure("SPEECH_RECOGNITION_FAILED", message, error)
            }

            override fun onResults(results: Bundle?) {
                val pending = pendingSpeechResult
                val matches = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    .orEmpty()
                if (pending == null && manualMode && speechListening) {
                    appendSpeechResults(results)
                    scheduleManualListenCycle(languageTag, 500L)
                    return
                }
                if (pending == null) {
                    return
                }
                appendSpeechResults(results)
                val text = accumulatedSpeechText.toString().trim()
                    .ifEmpty { matches.firstOrNull().orEmpty().trim() }
                deliverSpeechSuccess(
                    text,
                    if (matches.isEmpty() && text.isNotEmpty()) listOf(text) else matches
                )
            }

            override fun onPartialResults(partialResults: Bundle?) {
                if (!manualMode || !speechListening) {
                    return
                }
                latestPartialSpeechText = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    .orEmpty()
                    .trim()
                emitSpeechTranscript()
            }

            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        }
    }

    private fun speechErrorMessage(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error."
            SpeechRecognizer.ERROR_CLIENT -> "Speech client error."
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is missing."
            SpeechRecognizer.ERROR_NETWORK -> "Network error during speech recognition."
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech recognition network timeout."
            SpeechRecognizer.ERROR_NO_MATCH -> "No speech was recognized."
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech recognizer is busy."
            SpeechRecognizer.ERROR_SERVER -> "Speech recognizer server error."
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input was detected."
            else -> "Speech recognition failed."
        }
    }

    private fun closeLiteRtEngine(result: MethodChannel.Result) {
        synchronized(engineLock) {
            cachedEngine?.close()
            cachedEngine = null
            cachedModelKey = null
        }
        System.gc()
        Log.i("OralCancerLiteRT", "Engine closed")
        logMemory("OralCancerLiteRT")
        result.success(null)
    }

    private fun runLiteRtInference(args: Map<*, *>?, result: MethodChannel.Result) {
        if (args == null) {
            result.error("BAD_ARGS", "Missing LiteRT-LM inference arguments.", null)
            return
        }
        val modelPath = args["modelPath"] as? String
        val prompt = args["prompt"] as? String
        val backendName = args["backend"] as? String ?: "gpu"
        val imagePaths = (args["imagePaths"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        if (modelPath.isNullOrBlank()) {
            result.error("MODEL_PATH_REQUIRED", "LiteRT model path is required.", null)
            return
        }
        if (prompt.isNullOrBlank()) {
            result.error("PROMPT_REQUIRED", "Prompt is required.", null)
            return
        }
        if (!File(modelPath).exists()) {
            result.error("MODEL_NOT_FOUND", "LiteRT model file does not exist: $modelPath", null)
            return
        }
        for (path in imagePaths) {
            if (!File(path).exists()) {
                result.error("IMAGE_NOT_FOUND", "Image file does not exist: $path", null)
                return
            }
        }

        thread(name = "litert-lm-inference") {
            try {
                val started = System.currentTimeMillis()
                Log.i("OralCancerLiteRT", "Inference request model=$modelPath backend=$backendName images=${imagePaths.size} promptChars=${prompt.length}")
                logMemory("OralCancerLiteRT")
                val engine = synchronized(engineLock) {
                    val modelKey = "$modelPath::$backendName"
                    if (cachedEngine == null || cachedModelKey != modelKey) {
                        Log.i("OralCancerLiteRT", "Initializing LiteRT-LM engine for $modelPath using $backendName")
                        cachedEngine?.close()
                        logMemory("OralCancerLiteRT")
                        val backend = when (backendName.lowercase()) {
                            "cpu" -> Backend.CPU()
                            "gpu" -> Backend.GPU()
                            else -> throw IllegalArgumentException("Unsupported LiteRT backend: $backendName")
                        }
                        val engineConfig = EngineConfig(
                            modelPath = modelPath,
                            backend = backend,
                            visionBackend = backend,
                            cacheDir = cacheDir.path
                        )
                        Engine(engineConfig).also {
                            it.initialize()
                            cachedEngine = it
                            cachedModelKey = modelKey
                            Log.i("OralCancerLiteRT", "Engine initialized elapsedMs=${System.currentTimeMillis() - started}")
                            logMemory("OralCancerLiteRT")
                        }
                    } else {
                        Log.i("OralCancerLiteRT", "Reusing cached LiteRT-LM engine")
                    }
                    cachedEngine!!
                }
                Log.i("OralCancerLiteRT", "Running inference with ${imagePaths.size} image(s)")
                synchronized(engineLock) {
                    engine.createConversation().use { conversation ->
                        logMemory("OralCancerLiteRT")
                        val contents = Contents.of(
                            *(imagePaths.map { Content.ImageFile(it) } + Content.Text(prompt)).toTypedArray()
                        )
                        val response = conversation.sendMessage(contents)
                        val text = response.contents.contents
                            .filterIsInstance<Content.Text>()
                            .joinToString(separator = "") { it.text }
                        Log.i("OralCancerLiteRT", "Inference complete elapsedMs=${System.currentTimeMillis() - started} chars=${text.length}")
                        logMemory("OralCancerLiteRT")
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "text" to text,
                                    "modelName" to File(modelPath).name
                                )
                            )
                        }
                    }
                }
            } catch (error: Throwable) {
                Log.e("OralCancerLiteRT", "Inference failed", error)
                runOnUiThread {
                    result.error(
                        "LITERT_LM_INFERENCE_FAILED",
                        error.message ?: error.toString(),
                        error.stackTraceToString()
                    )
                }
            }
        }
    }

    private fun runYoloDetection(args: Map<*, *>?, result: MethodChannel.Result) {
        if (args == null) {
            result.error("BAD_ARGS", "Missing YOLO detection arguments.", null)
            return
        }
        val modelPath = args["modelPath"] as? String
        val imagePath = args["imagePath"] as? String
        val confidenceThreshold = (args["confidenceThreshold"] as? Number)?.toFloat() ?: 0.25f
        val iouThreshold = (args["iouThreshold"] as? Number)?.toFloat() ?: 0.45f
        val inputSize = (args["inputSize"] as? Number)?.toInt() ?: 640
        val maxDetections = (args["maxDetections"] as? Number)?.toInt() ?: 10

        if (modelPath.isNullOrBlank() || !File(modelPath).exists()) {
            result.error("YOLO_MODEL_NOT_FOUND", "YOLO model file does not exist: $modelPath", null)
            return
        }
        if (imagePath.isNullOrBlank() || !File(imagePath).exists()) {
            result.error("IMAGE_NOT_FOUND", "Image file does not exist: $imagePath", null)
            return
        }

        thread(name = "yolo-prefilter") {
            try {
                val started = System.currentTimeMillis()
                Log.i("OralCancerYOLO", "Detection request model=$modelPath image=$imagePath conf=$confidenceThreshold inputSize=$inputSize")
                logMemory("OralCancerYOLO")
                val detections = synchronized(yoloLock) {
                    val interpreter = getYoloInterpreter(modelPath)
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                        ?: throw IllegalArgumentException("Could not decode image: $imagePath")
                    Log.i("OralCancerYOLO", "Decoded image width=${bitmap.width} height=${bitmap.height}")
                    val prepared = letterbox(bitmap, inputSize)
                    val input = Array(1) {
                        Array(inputSize) {
                            Array(inputSize) {
                                FloatArray(3)
                            }
                        }
                    }
                    for (y in 0 until inputSize) {
                        for (x in 0 until inputSize) {
                            val pixel = prepared.bitmap.getPixel(x, y)
                            input[0][y][x][0] = Color.red(pixel) / 255.0f
                            input[0][y][x][1] = Color.green(pixel) / 255.0f
                            input[0][y][x][2] = Color.blue(pixel) / 255.0f
                        }
                    }
                    val output = Array(1) { Array(5) { FloatArray(8400) } }
                    interpreter.run(input, output)
                    val decoded = decodeYolo(
                        output = output[0],
                        sourceWidth = bitmap.width,
                        sourceHeight = bitmap.height,
                        scale = prepared.scale,
                        padX = prepared.padX,
                        padY = prepared.padY,
                        confidenceThreshold = confidenceThreshold,
                        iouThreshold = iouThreshold,
                        maxDetections = maxDetections
                    )
                    Log.i("OralCancerYOLO", "Detection complete elapsedMs=${System.currentTimeMillis() - started} detections=${decoded.size}")
                    logMemory("OralCancerYOLO")
                    decoded
                }
                runOnUiThread { result.success(detections.map { it.toMap() }) }
            } catch (error: Throwable) {
                Log.e("OralCancerYOLO", "YOLO detection failed", error)
                runOnUiThread {
                    result.error(
                        "YOLO_DETECTION_FAILED",
                        error.message ?: error.toString(),
                        error.stackTraceToString()
                    )
                }
            }
        }
    }

    private fun getYoloInterpreter(modelPath: String): Interpreter {
        if (cachedYolo == null || cachedYoloPath != modelPath) {
            cachedYolo?.close()
            val options = Interpreter.Options().apply {
                setNumThreads(max(2, Runtime.getRuntime().availableProcessors() / 2))
            }
            Log.i("OralCancerYOLO", "Initializing YOLO interpreter model=$modelPath")
            logMemory("OralCancerYOLO")
            cachedYolo = Interpreter(loadMappedFile(modelPath), options)
            cachedYoloPath = modelPath
            Log.i("OralCancerYOLO", "YOLO interpreter initialized")
            logMemory("OralCancerYOLO")
        }
        return cachedYolo!!
    }

    private fun closeYoloInterpreter(result: MethodChannel.Result) {
        synchronized(yoloLock) {
            cachedYolo?.close()
            cachedYolo = null
            cachedYoloPath = null
        }
        System.gc()
        Log.i("OralCancerYOLO", "Interpreter closed")
        logMemory("OralCancerYOLO")
        result.success(null)
    }

    private fun loadMappedFile(path: String): MappedByteBuffer {
        FileInputStream(path).use { stream ->
            val channel = stream.channel
            return channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size())
        }
    }

    private data class LetterboxResult(
        val bitmap: Bitmap,
        val scale: Float,
        val padX: Int,
        val padY: Int
    )

    private fun letterbox(source: Bitmap, size: Int): LetterboxResult {
        val scale = min(size.toFloat() / source.width, size.toFloat() / source.height)
        val newWidth = (source.width * scale).roundToInt()
        val newHeight = (source.height * scale).roundToInt()
        val padX = (size - newWidth) / 2
        val padY = (size - newHeight) / 2
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.rgb(114, 114, 114))
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(
            source,
            null,
            Rect(padX, padY, padX + newWidth, padY + newHeight),
            paint
        )
        return LetterboxResult(output, scale, padX, padY)
    }

    private data class Detection(
        val x1: Float,
        val y1: Float,
        val x2: Float,
        val y2: Float,
        val confidence: Float
    ) {
        fun area(): Float = max(0.0f, x2 - x1) * max(0.0f, y2 - y1)

        fun toMap(): Map<String, Any> = mapOf(
            "x1" to x1.toDouble(),
            "y1" to y1.toDouble(),
            "x2" to x2.toDouble(),
            "y2" to y2.toDouble(),
            "confidence" to confidence.toDouble()
        )
    }

    private fun decodeYolo(
        output: Array<FloatArray>,
        sourceWidth: Int,
        sourceHeight: Int,
        scale: Float,
        padX: Int,
        padY: Int,
        confidenceThreshold: Float,
        iouThreshold: Float,
        maxDetections: Int
    ): List<Detection> {
        val raw = mutableListOf<Detection>()
        val count = output[0].size
        for (i in 0 until count) {
            val score = output[4][i]
            if (score < confidenceThreshold) continue

            val cx = output[0][i]
            val cy = output[1][i]
            val w = output[2][i]
            val h = output[3][i]

            val x1 = ((cx - w / 2.0f - padX) / scale).coerceIn(0.0f, (sourceWidth - 1).toFloat())
            val y1 = ((cy - h / 2.0f - padY) / scale).coerceIn(0.0f, (sourceHeight - 1).toFloat())
            val x2 = ((cx + w / 2.0f - padX) / scale).coerceIn(0.0f, (sourceWidth - 1).toFloat())
            val y2 = ((cy + h / 2.0f - padY) / scale).coerceIn(0.0f, (sourceHeight - 1).toFloat())
            if (x2 <= x1 || y2 <= y1) continue
            raw.add(Detection(x1, y1, x2, y2, score))
        }

        val sorted = raw.sortedByDescending { it.confidence }
        val kept = mutableListOf<Detection>()
        for (candidate in sorted) {
            if (kept.any { iou(it, candidate) > iouThreshold }) continue
            kept.add(candidate)
            if (kept.size >= maxDetections) break
        }
        return kept
    }

    private fun iou(a: Detection, b: Detection): Float {
        val ix1 = max(a.x1, b.x1)
        val iy1 = max(a.y1, b.y1)
        val ix2 = min(a.x2, b.x2)
        val iy2 = min(a.y2, b.y2)
        val intersection = max(0.0f, ix2 - ix1) * max(0.0f, iy2 - iy1)
        val union = a.area() + b.area() - intersection
        return if (union <= 0.0f) 0.0f else intersection / union
    }
}
