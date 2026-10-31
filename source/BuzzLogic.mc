import Toybox.Lang;

// Timing of the superset switch cue: two single-profile vibrations. Multi-profile patterns did
// not vibrate at all on a real FR965 (ColdStart 0.1.2), so the second buzz is fired by a later
// onTick instead of being part of one pattern. Pure, unit-tested.
module BuzzLogic {
    const REPEAT_GAP_MS = 400;
    const REPEAT_STALE_MS = 3000;

    // When the second buzz becomes due, given the time of the first (System.getTimer() ms).
    function repeatAt(firstMs as Number) as Number {
        return firstMs + REPEAT_GAP_MS;
    }

    // True when a tick at nowMs should fire the pending second buzz. `blocked` is true when the
    // tick already vibrates or writes storage; the buzz then waits for the next tick.
    function repeatDue(repeatAtMs as Number, nowMs as Number, blocked as Boolean) as Boolean {
        return repeatAtMs > 0 && nowMs >= repeatAtMs && !blocked &&
            nowMs - repeatAtMs <= REPEAT_STALE_MS;
    }

    // True when a pending second buzz is too old to be worth firing (dropped silently).
    function repeatStale(repeatAtMs as Number, nowMs as Number) as Boolean {
        return repeatAtMs > 0 && nowMs - repeatAtMs > REPEAT_STALE_MS;
    }
}
