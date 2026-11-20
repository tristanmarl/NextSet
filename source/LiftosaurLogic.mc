import Toybox.Application;
import Toybox.Lang;

module LiftosaurLogic {
    // Peak a reply adds while it is converted, measured in the simulator with a 10-exercise,
    // 4-set day (about 91 KB), plus margin; see docs/DEVICE_TESTS.md.
    const SYNC_NEED_DAY = 112640;

    function trim(text as String) as String {
        var start = 0;
        var end = text.length();
        while (start < end && isSpace(text.substring(start, start + 1) as String)) {
            start++;
        }
        while (end > start && isSpace(text.substring(end - 1, end) as String)) {
            end--;
        }
        return text.substring(start, end) as String;
    }

    function isSpace(character as String) as Boolean {
        return Model.sameString(character, " ") || Model.sameString(character, "\t") ||
            Model.sameString(character, "\r");
    }

    // Entered key: trimmed, non-empty, at most 128 bytes, printable ASCII without inner spaces.
    function cleanKey(text as String?) as String? {
        if (text == null) {
            return null;
        }
        var key = trim(text as String);
        // trim() ignores newlines; strip them from the ends too.
        var bytes = key.toUtf8Array();
        var from = 0;
        var to = bytes.size();
        while (from < to && (bytes[from] <= 32 || bytes[from] == 127)) {
            from++;
        }
        while (to > from && (bytes[to - 1] <= 32 || bytes[to - 1] == 127)) {
            to--;
        }
        if (from >= to || to - from > 128) {
            return null;
        }
        for (var i = from; i < to; i++) {
            if (bytes[i] <= 32 || bytes[i] >= 127) {
                return null;
            }
        }
        return key.substring(from, to) as String;
    }

    // Phone link or Wi-Fi available; connectionAvailable is null when the device does not report it.
    function isOnline(phoneConnected as Boolean, connectionAvailable as Boolean?) as Boolean {
        return phoneConnected || connectionAvailable == true;
    }

    // Failures worth trying again later: HTTP 408 / 429 / 5xx, and the Connect IQ transport codes
    // that say nothing about the request itself (-1 BLE_ERROR, -2 / -3 host and server timeout,
    // -4 no data, -5 cancelled by the system, -101 queue full, -103 unknown send error,
    // -300 request timed out, -1003 cancelled by the system, -1004 connection dropped).
    // Not retried: -102 request too large, -200..-202 bad request, -400 / -401 / -1002 unreadable
    // response, -402 / -403 response too large, -1000 storage full, and HTTP 400 / 401 / 403 /
    // 404 / 409 / 422 (the server will answer the same).
    function retryable(responseCode as Number) as Boolean {
        if (responseCode >= 500 && responseCode <= 599) {
            return true;
        }
        if (responseCode >= -5 && responseCode <= -1) {
            return true;
        }
        return responseCode == 408 || responseCode == 429 || responseCode == -101 ||
            responseCode == -103 || responseCode == -300 || responseCode == -1003 ||
            responseCode == -1004;
    }

    // Transient failure of a web request as an Err code (-104 phone not connected, or a retryable
    // code), Err.NONE for anything else.
    function transportError(responseCode as Number) as Number {
        if (responseCode == -104) {
            return Err.PHONE_NOT_CONNECTED;
        }
        return retryable(responseCode) ? Err.NO_RESPONSE_WILL_RETRY : Err.NONE;
    }

    // Response code as shown to the user: "HTTP 404" for a server reply, "CIQ -400" for a
    // Connect IQ / Garmin Connect error (0 and below).
    function codeLabel(responseCode as Number) as String {
        return (responseCode > 0 ? "HTTP " : "CIQ ") + responseCode.toString();
    }

    // Settings → Test key text for a reply that is neither a success nor 401 / 403.
    function keyTestFailure(responseCode as Number) as String {
        if (responseCode == -104) {
            return "Phone not connected";
        }
        return (retryable(responseCode) ? "No response · " : "Request failed · ") +
            codeLabel(responseCode);
    }

    // Home notice for Err.ROUTINE_SYNC_REQUEST_FAILED; label null = the request was never sent.
    function syncFailedNotice(label as String?) as String {
        return label == null ? "Sync request not sent" : "Sync failed · " + (label as String);
    }

    // Auto-retry backoff: 2, 5, then 10 minutes.
    function retryDelayMinutes(attempt as Number) as Number {
        return attempt <= 0 ? 2 : (attempt == 1 ? 5 : 10);
    }

    // Summary status line for the Liftosaur upload of the workout just saved; null when the
    // workout has no upload. icon: "check" | "arrow" | "clock" | "cross".
    function summaryUpload(state as String?, uploading as Boolean, errorText as String?) as Dictionary? {
        if (Model.sameString(state, Liftosaur.STATE_DONE)) {
            return {"icon" => "check", "text" => "Uploaded"};
        }
        if (Model.sameString(state, Liftosaur.STATUS_SKIPPED)) {
            return {"icon" => "cross", "text" => "Upload skipped"};
        }
        if (!Model.sameString(state, Liftosaur.STATUS_PENDING)) {
            return null;
        }
        if (uploading) {
            return {"icon" => "arrow", "text" => "Uploading…"};
        }
        return errorText != null ? {"icon" => "cross", "text" => errorText} :
            {"icon" => "clock", "text" => "Pending · next launch"};
    }

    // The summary offers "Sync to Liftosaur" (START uploads now) while this workout's upload is
    // waiting or failed: pending in the queue, not uploading right now, and a key is set. Not
    // when it is done, skipped, uploading, or has no job; nothing without a key.
    function syncActionable(state as String?, uploading as Boolean, hasKey as Boolean) as Boolean {
        return hasKey && !uploading && Model.sameString(state, Liftosaur.STATUS_PENDING);
    }

    // "lftsk_…ab12": prefix and last four characters only.
    function maskKey(key as String) as String {
        if (key.length() <= 10) {
            return "…" + key.substring(key.length() - 2, key.length());
        }
        return key.substring(0, 6) + "…" + key.substring(key.length() - 4, key.length());
    }

    // Free app memory a sync request needs before it is sent (its reply is held whole while it
    // is converted); 0 for requests that are not routine sync. Measured values: docs/DEVICE_TESTS.md.
    function syncMemoryNeed(purpose as String) as Number {
        return Model.sameString(purpose, Liftosaur.REQ_SYNC_DAY) ||
            Model.sameString(purpose, Liftosaur.REQ_SYNC_NEXT) ? SYNC_NEED_DAY : 0;
    }

    function enoughFree(purpose as String, free as Number) as Boolean {
        return free >= syncMemoryNeed(purpose);
    }

    // Reason of the last rejected sync, kept in the small storage key "diag.sync" (null = none).
    function saveSyncProblem(text as String?) as Void {
        try {
            if (text != null) {
                Application.Storage.setValue("diag.sync", text);
            } else if (Application.Storage.getValue("diag.sync") != null) {
                Application.Storage.deleteValue("diag.sync");
            }
        } catch (error) {
        }
    }

    function loadSyncProblem() as String? {
        try {
            var value = Application.Storage.getValue("diag.sync");
            return value instanceof String ? Model.fit(value as String, 80) : null;
        } catch (error) {
        }
        return null;
    }
}
