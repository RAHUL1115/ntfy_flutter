# Full-screen alert foundation

Tag-triggered alerts use Android's `USE_FULL_SCREEN_INTENT` capability because
the intended future UI is an urgent notification experience, not a window drawn
over other apps. The app does not request `SYSTEM_ALERT_WINDOW`.

This release only adds opt-in tag matching, capability/settings routing, and a
maximum-importance notification fallback. A dedicated full-screen alert UI and
attaching the full-screen intent are intentionally deferred.
