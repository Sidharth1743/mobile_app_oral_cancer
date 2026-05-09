package com.example.oral_cancer

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val engineLock = Any()
    private var cachedEngine: Engine? = null
    private var cachedModelKey: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "oral_cancer/litert_lm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "infer" -> runLiteRtInference(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
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
                val engine = synchronized(engineLock) {
                    val modelKey = "$modelPath::$backendName"
                    if (cachedEngine == null || cachedModelKey != modelKey) {
                        Log.i("OralCancerLiteRT", "Initializing LiteRT-LM engine for $modelPath using $backendName")
                        cachedEngine?.close()
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
                        }
                    } else {
                        Log.i("OralCancerLiteRT", "Reusing cached LiteRT-LM engine")
                    }
                    cachedEngine!!
                }
                Log.i("OralCancerLiteRT", "Running inference with ${imagePaths.size} image(s)")
                synchronized(engineLock) {
                    engine.createConversation().use { conversation ->
                        val contents = Contents.of(
                            *(imagePaths.map { Content.ImageFile(it) } + Content.Text(prompt)).toTypedArray()
                        )
                        val response = conversation.sendMessage(contents)
                        val text = response.contents.contents
                            .filterIsInstance<Content.Text>()
                            .joinToString(separator = "") { it.text }
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
}
