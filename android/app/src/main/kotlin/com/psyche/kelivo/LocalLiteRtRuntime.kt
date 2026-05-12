package com.psyche.kelivo

import android.content.Context
import android.app.ActivityManager
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import java.io.File

object LocalLiteRtRuntime {
    class RuntimeExceptionWithCode(
        val code: String,
        override val message: String,
    ) : Exception(message)

    private const val e4bModelSizeBytes = 3_300_000_000L
    private const val e2bModelSizeBytes = 2_300_000_000L
    private const val e4bRequiredRamGb = 12
    private const val e2bRequiredRamGb = 8

    private var engine: Engine? = null
    private var currentModelPath: String? = null
    private var currentBackendLabel: String? = null
    private var forceCpu = false

    @Synchronized
    fun sendMessage(
        context: Context,
        modelPath: String,
        systemPrompt: String,
        prompt: String,
        temperature: Double,
        preferCpu: Boolean,
    ): String {
        require(modelPath.isNotBlank()) { "Missing LiteRT-LM model path." }
        val modelFile = File(modelPath)
        require(modelFile.isFile) { "LiteRT-LM model file does not exist." }
        require(prompt.isNotBlank()) { "Missing prompt." }
        validateDeviceCapacity(context, modelFile)

        val engine = getOrCreateEngine(context, modelPath, preferCpu)
        val conversation = engine.createConversation(
            ConversationConfig(
                systemInstruction = Contents.of(systemPrompt.ifBlank { "You are a helpful assistant." }),
                samplerConfig = SamplerConfig(
                    topK = 64,
                    topP = 0.95,
                    temperature = temperature,
                ),
            ),
        )

        return try {
            conversation.sendMessage(prompt, emptyMap()).contents?.toString()?.trim().orEmpty()
        } catch (error: Exception) {
            if (!forceCpu && isGpuBackendFailure(error)) {
                forceCpu = true
                closeEngine()
                val cpuEngine = getOrCreateEngine(context, modelPath, preferCpu = true)
                val cpuConversation = cpuEngine.createConversation(
                    ConversationConfig(
                        systemInstruction = Contents.of(systemPrompt.ifBlank { "You are a helpful assistant." }),
                        samplerConfig = SamplerConfig(
                            topK = 64,
                            topP = 0.95,
                            temperature = temperature,
                        ),
                    ),
                )
                try {
                    cpuConversation.sendMessage(prompt, emptyMap()).contents?.toString()?.trim().orEmpty()
                } finally {
                    cpuConversation.close()
                }
            } else {
                throw error
            }
        } finally {
            conversation.close()
        }
    }

    @Synchronized
    private fun getOrCreateEngine(context: Context, modelPath: String, preferCpu: Boolean): Engine {
        val backend = if (preferCpu || forceCpu) Backend.CPU() else Backend.GPU()
        val backendLabel = if (backend is Backend.CPU) "CPU" else "GPU"
        val existing = engine
        if (
            existing != null &&
            currentModelPath == modelPath &&
            currentBackendLabel == backendLabel
        ) {
            return existing
        }

        closeEngine()
        return try {
            Engine(
                EngineConfig(
                    modelPath = modelPath,
                    backend = backend,
                    maxNumTokens = 8192,
                    cacheDir = context.cacheDir.path,
                ),
            ).also {
                it.initialize()
                engine = it
                currentModelPath = modelPath
                currentBackendLabel = backendLabel
            }
        } catch (error: Exception) {
            if (!forceCpu && isGpuBackendFailure(error)) {
                forceCpu = true
                getOrCreateEngine(context, modelPath, preferCpu = true)
            } else {
                throw error
            }
        }
    }

    @Synchronized
    private fun closeEngine() {
        try {
            engine?.close()
        } finally {
            engine = null
            currentModelPath = null
            currentBackendLabel = null
        }
    }

    private fun isGpuBackendFailure(error: Throwable): Boolean {
        val message = error.message.orEmpty()
        return message.contains("OpenCL", ignoreCase = true) ||
            message.contains("GPU", ignoreCase = true) ||
            message.contains("nativeSendMessage", ignoreCase = true) ||
            message.contains("Failed to create engine", ignoreCase = true) ||
            message.contains("compiled model", ignoreCase = true)
    }

    private fun validateDeviceCapacity(context: Context, modelFile: File) {
        val requiredRamGb = requiredRamGbForModel(modelFile)
        if (requiredRamGb == null) return
        val deviceRamGb = getDeviceRamGb(context)
        if (deviceRamGb >= requiredRamGb) return
        throw RuntimeExceptionWithCode(
            "local_litert_model_too_large",
            "LiteRT-LM model requires ${requiredRamGb}GB RAM; this device reports ${deviceRamGb}GB.",
        )
    }

    private fun requiredRamGbForModel(modelFile: File): Int? {
        val name = modelFile.name.lowercase()
        if (name.contains("e4b")) return e4bRequiredRamGb
        if (name.contains("e2b")) return e2bRequiredRamGb
        val size = modelFile.length()
        return when {
            size >= e4bModelSizeBytes -> e4bRequiredRamGb
            size >= e2bModelSizeBytes -> e2bRequiredRamGb
            else -> null
        }
    }

    private fun getDeviceRamGb(context: Context): Int {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        return (memInfo.totalMem / (1024L * 1024L * 1024L)).toInt() + 1
    }
}
