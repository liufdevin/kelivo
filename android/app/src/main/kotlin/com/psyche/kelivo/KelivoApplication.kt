package com.psyche.kelivo

import android.app.Application
import com.ryanheise.audioservice.AudioServicePlugin
import com.psyche.kelivo.background.BackgroundRuntime
import com.psyche.kelivo.workspace.WorkspacePlugin
import com.psyche.kelivo.scheduled.ScheduledTasks
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** One Dart isolate and database owner per process, independent of its UI. */
class KelivoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // AudioService can start without an Activity (e.g. a headset button).
        // All entry points must use our process-owned engine, and stopping
        // audio must not destroy the chat/database or background task isolate.
        AudioServicePlugin.setFlutterEngineProvider { engine }
    }
    val backgroundRuntime by lazy { BackgroundRuntime(this) }
    val scheduledTasks by lazy { ScheduledTasks(this) }
    val workspace by lazy { WorkspacePlugin(this) }
    val deviceTools by lazy { DeviceLocalToolsHandler(this) }

    private val engineHolder = lazy {
        FlutterEngine(this).also { engine ->
            val messenger = engine.dartExecutor.binaryMessenger
            backgroundRuntime.configure(messenger)
            scheduledTasks.configure(messenger)
            workspace.configure(messenger)
            deviceTools.configure(messenger)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }

    val hasEngine get() = engineHolder.isInitialized()
    val engine: FlutterEngine get() = engineHolder.value
}
