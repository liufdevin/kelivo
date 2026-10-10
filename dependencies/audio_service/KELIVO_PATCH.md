# Kelivo audio_service patch

Based on audio_service 0.18.19 from pub.dev, licensed under the included LICENSE.
The Dart API and Darwin implementation are unchanged.

Android adds `AudioServicePlugin.setFlutterEngineProvider`. Kelivo registers its
Application-owned engine before any engine or audio service starts. Activity
attachment, service startup, and media button launches all use that provider.
The plugin never destroys a host-owned engine when the audio service stops.

Without this integration, the plugin starts a second root isolate and competes
for Kelivo's business data lease. Sharing only a cache entry is insufficient:
the plugin also destroys cached engines after the last Activity detaches.