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
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
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
                beginSpeechRecognition(emptyMap<Any, Any>(), result)
            } else {
                pendingSpeechResult = null
                result.error("AUDIO_PERMISSION_DENIED", "Microphone permission was denied.", null)
            }
        }
    }

    private fun startSpeechRecognition(args: Map<*, *>?, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("SPEECH_UNAVAILABLE", "Speech recognition is not available on this device.", null)
            return
        }
        if (pendingSpeechResult != null) {
            result.error("SPEECH_BUSY", "Speech recognition is already running.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingSpeechResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                speechPermissionRequestCode
            )
            return
        }
        beginSpeechRecognition(args ?: emptyMap<Any, Any>(), result)
    }

    private fun beginSpeechRecognition(args: Map<*, *>, result: MethodChannel.Result) {
        pendingSpeechResult = result
        val languageTag = args["languageTag"] as? String ?: "en-IN"
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.destroy()
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.i("OralCancerSpeech", "ready language=$languageTag")
            }

            override fun onBeginningOfSpeech() {
                Log.i("OralCancerSpeech", "beginning")
            }

            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() {
                Log.i("OralCancerSpeech", "end")
            }

            override fun onError(error: Int) {
                val pending = pendingSpeechResult ?: return
                pendingSpeechResult = null
                recognizer.destroy()
                if (speechRecognizer == recognizer) {
                    speechRecognizer = null
                }
                val message = speechErrorMessage(error)
                Log.e("OralCancerSpeech", "error=$error message=$message")
                pending.error("SPEECH_RECOGNITION_FAILED", message, error)
            }

            override fun onResults(results: Bundle?) {
                val pending = pendingSpeechResult ?: return
                pendingSpeechResult = null
                recognizer.destroy()
                if (speechRecognizer == recognizer) {
                    speechRecognizer = null
                }
                val matches = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    .orEmpty()
                val text = matches.firstOrNull().orEmpty()
                Log.i("OralCancerSpeech", "result chars=${text.length} alternatives=${matches.size}")
                pending.success(
                    mapOf(
                        "text" to text,
                        "alternatives" to matches
                    )
                )
            }

            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak patient intake details")
        }
        recognizer.startListening(intent)
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
