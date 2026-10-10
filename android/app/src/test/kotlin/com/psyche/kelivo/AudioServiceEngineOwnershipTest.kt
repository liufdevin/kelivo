package com.psyche.kelivo

import android.app.Activity
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = KelivoApplication::class,
    shadows = [AudioServiceEngineOwnershipTest.EngineShadow::class])
class AudioServiceEngineOwnershipTest {
    @Implements(FlutterEngine::class, callThroughByDefault = false)
    class EngineShadow {
        var destroyCount = 0

        // These tests exercise ownership without loading native Flutter.
        @Implementation fun destroy() { destroyCount++ }
    }

    @After fun resetPlugin() {
        AudioServicePlugin.setFlutterEngineProvider(null)
        FlutterEngineCache.getInstance().clear()
    }

    private fun installAppEngine(): FlutterEngine {
        val app = RuntimeEnvironment.getApplication() as KelivoApplication
        val engine = FlutterEngine(app)
        ReflectionHelpers.setField(app, "engineHolder", lazyOf(engine))
        return engine
    }

    @Test fun activityAndHeadlessServiceUseTheApplicationEngine() {
        val engine = installAppEngine()
        val app = RuntimeEnvironment.getApplication() as KelivoApplication
        assertTrue(app.hasEngine)
        // No audio_service cache entry is needed. Both plugin entry points
        // resolve the same engine that MainActivity receives from Application.
        assertNull(FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId()))
        assertSame(engine, AudioServicePlugin.getFlutterEngine(Activity()))
        assertSame(engine, AudioServicePlugin.getFlutterEngine(app))
        assertSame(engine, app.engine)
    }

    @Test fun stoppingAudioWithoutAnActivityPreservesTheEngineOnReentry() {
        val engine = installAppEngine()
        val app = RuntimeEnvironment.getApplication() as KelivoApplication
        // Even if cached by a caller, audio service teardown must not destroy
        // the engine that also owns chat data and background generation.
        val cache = FlutterEngineCache.getInstance()
        cache.put(AudioServicePlugin.getFlutterEngineId(), engine)
        repeat(3) {
            AudioServicePlugin.disposeFlutterEngine()
            assertSame(engine, AudioServicePlugin.getFlutterEngine(app))
            assertSame(engine, AudioServicePlugin.getFlutterEngine(Activity()))
        }
        assertEquals(0, Shadow.extract<EngineShadow>(engine).destroyCount)
        assertSame(engine, cache.get(AudioServicePlugin.getFlutterEngineId()))
    }

    @Test fun pluginStillDisposesAnEngineItOwns() {
        val engine = installAppEngine()
        AudioServicePlugin.setFlutterEngineProvider(null)
        val cache = FlutterEngineCache.getInstance()
        cache.put(AudioServicePlugin.getFlutterEngineId(), engine)
        AudioServicePlugin.disposeFlutterEngine()
        assertEquals(1, Shadow.extract<EngineShadow>(engine).destroyCount)
        assertNull(cache.get(AudioServicePlugin.getFlutterEngineId()))
    }
}