import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Liftosaur API plumbing: routine sync, upload queue, key storage and key test. Owned by
// SessionController, which supplies the narrow host surface below (error code, workout-state
// queries and the config pivot). One request is in flight at a time; web and timer callbacks are
// public.
class LiftosaurSync {
    private var _store as Store;
    private var _host as SessionController;
    private var _requestInFlight as Boolean = false;
    private var _routineSyncRunning as Boolean = false;
    private var _uploadRequested as Boolean = false;
    private var _refreshAfterUploads as Boolean = false;
    private var _responsePurpose as String? = null;
    private var _responseUploadId as String? = null;
    private var _notice as String? = null;
    private var _storedKey as String? = null;
    private var _clientHeader as String? = null;
    private var _storedKeyLoaded as Boolean = false;
    private var _asyncTimer as Timer.Timer;
    private var _retryTimer as Timer.Timer;
    private var _retryAttempt as Number = 0;

    public function initialize(store as Store, host as SessionController) {
        _store = store;
        _host = host;
        _asyncTimer = new Timer.Timer();
        _retryTimer = new Timer.Timer();
    }

    public function clearNotice() as Void {
        _notice = null;
    }

    public function setNotice(text as String) as Void {
        _notice = text;
    }

    // The key entered on the watch is the only source. Never logged or drawn unmasked.
    private function liftosaurKey() as String? {
        if (!_storedKeyLoaded) {
            _storedKey = _store.loadApiKey();
            _storedKeyLoaded = true;
        }
        return _storedKey;
    }

    public function keyLabel() as String {
        var key = liftosaurKey();
        return key == null ? "Not set" : LiftosaurLogic.maskKey(key as String);
    }

    public function hasKey() as Boolean {
        return liftosaurKey() != null;
    }

    // Returns an error message, or null when the key was saved.
    public function saveKey(text as String?) as String? {
        var key = LiftosaurLogic.cleanKey(text);
        if (key == null) {
            return "Key is empty or invalid";
        }
        _storedKeyLoaded = false;
        return _store.saveApiKey(key as String) ? null : "Key not saved";
    }

    public function clearKey() as Boolean {
        _store.deleteApiKey();
        _storedKeyLoaded = false;
        return true;
    }

    // Read-only GET /programs/current; the result is shown from handleApiResponse.
    // Returns an error message, or null when the request started.
    public function testKey() as String? {
        if (_requestInFlight) {
            return "Busy, try again";
        }
        var saved = _host.errorCode();
        var started = makeApiRequest("/programs/current", Communications.HTTP_REQUEST_METHOD_GET,
            null, false, Liftosaur.REQ_KEY_TEST, null);
        var failure = _host.errorCode();
        var message = started ? null : (failure == Err.LIFTOSAUR_KEY_REQUIRED ?
            "Set Liftosaur key in Settings" : (failure == Err.PHONE_NOT_CONNECTED ?
                "Phone not connected" : "No connection"));
        _host.setErrorCode(saved);
        return message;
    }

    private function keyTestDone(responseCode as Number, data as Object?) as Void {
        var message = "No connection";
        if (responseCode >= 200 && responseCode < 300) {
            var body = responseBody(data);
            var program = body == null ? null : (body["program"] instanceof Dictionary ?
                body["program"] as Dictionary : body);
            var name = program == null ? null : program["name"];
            message = "Key OK" + (name instanceof String ? " · " + (name as String) : "");
        } else if (responseCode == 401 || responseCode == 403) {
            message = "Key rejected";
        } else if (LiftosaurLogic.transportError(responseCode) == Err.PHONE_NOT_CONNECTED) {
            message = "Phone not connected";
        }
        Navigator.replaceFeedback(message);
    }

    private function deviceId() as String? {
        var existing = _store.loadDeviceId();
        if (existing != null) {
            return existing;
        }
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _host.setErrorCode(Err.SAVED_SETTINGS_ARE_DAMAGED);
            return null;
        }
        Math.srand((Time.now().value() % 1000000) * 1000 +
            (System.getTimer() % 1000));
        var alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
        var id = "nextset-";
        for (var i = 0; i < 24; i++) {
            var index = Math.rand() % alphabet.length();
            id += alphabet.substring(index, index + 1);
        }
        if (!_store.saveDeviceId(id)) {
            _host.setErrorCode(Err.SETTINGS_SAVE_FAILED);
            return null;
        }
        return id;
    }

    private function clientHeader() as String {
        if (_clientHeader == null) {
            _clientHeader = "nextset-watch/" +
                (WatchUi.loadResource($.Rez.Strings.AppVersion) as String);
        }
        return _clientHeader as String;
    }

    private function apiHeaders(write as Boolean) as Dictionary? {
        var key = liftosaurKey();
        if (key == null) {
            _host.setErrorCode(Err.LIFTOSAUR_KEY_REQUIRED);
            return null;
        }
        var headers = {
            "Authorization" => "Bearer " + (key as String),
            "X-Liftosaur-Client" => clientHeader(),
            "Content-Type" => "application/json"
        };
        if (write) {
            var id = deviceId();
            if (id == null) {
                return null;
            }
            headers["X-Liftosaur-Device-Id"] = id as String;
        }
        return headers;
    }

    private function online() as Boolean {
        var settings = System.getDeviceSettings();
        return LiftosaurLogic.isOnline(settings.phoneConnected,
            settings has :connectionAvailable ? settings.connectionAvailable : null);
    }

    // One-shot retry with backoff while the app is open; never during a workout or its save.
    private function scheduleRetry() as Void {
        if (_host.hasActiveSession() || _host.hasPendingFinalization() ||
            (pendingUploadCount() == 0 && _store.loadRoutineSync() == null)) {
            return;
        }
        _retryTimer.stop();
        _retryTimer.start(method(:retryNow), LiftosaurLogic.retryDelayMinutes(_retryAttempt) * 60000,
            false);
        _retryAttempt++;
    }

    // Timer target. A workout in progress is left alone; finalization calls retryUploads() later.
    public function retryNow() as Void {
        if (_host.hasActiveSession() || _host.hasPendingFinalization() || _requestInFlight) {
            return;
        }
        resumeWork();
    }

    private function transientFailure(code as Number) as Boolean {
        return code == Err.PHONE_NOT_CONNECTED || code == Err.NO_RESPONSE_WILL_RETRY;
    }

    private function makeApiRequest(path as String,
                                    httpMethod as Communications.HttpRequestMethod,
                                    params as Dictionary?, write as Boolean,
                                    purpose as String, uploadId as String?) as Boolean {
        if (_requestInFlight) {
            return false;
        }
        var headers = apiHeaders(write);
        if (headers == null) {
            return false;
        }
        if (!online()) {
            // Nothing is sent; the queue and journal stay as they are.
            _host.setErrorCode(Err.PHONE_NOT_CONNECTED);
            if (!Model.sameString(purpose, Liftosaur.REQ_KEY_TEST)) {
                scheduleRetry();
            }
            WatchUi.requestUpdate();
            return false;
        }
        _responsePurpose = purpose;
        _responseUploadId = uploadId;
        _requestInFlight = true;
        try {
            Communications.makeWebRequest("https://www.liftosaur.com/api/v1" + path,
                params, {
                    :method => httpMethod,
                    :headers => headers as Dictionary,
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                    :context => null,
                    :maxBandwidth => 0
                }, method(:onApiResponse));
            return true;
        } catch (error) {
            _requestInFlight = false;
            _responsePurpose = null;
            _responseUploadId = null;
            _host.setErrorCode(Model.sameString(purpose, Liftosaur.REQ_UPLOAD_START) ||
                Model.sameString(purpose, Liftosaur.REQ_UPLOAD_SETS) ||
                Model.sameString(purpose, Liftosaur.REQ_UPLOAD_FINISH) ? Err.WORKOUT_UPLOAD_FAILED :
                Err.ROUTINE_SYNC_REQUEST_FAILED);
            WatchUi.requestUpdate();
            return false;
        }
    }

    public function syncRoutines() as Boolean {
        if (liftosaurKey() == null) {
            _host.setErrorCode(Err.LIFTOSAUR_KEY_REQUIRED);
            WatchUi.requestUpdate();
            return false;
        }
        if (_routineSyncRunning && _requestInFlight) {
            return true;
        }
        var journal = _store.loadRoutineSync();
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
            return false;
        }
        // A manual sync always restarts: a journal that keeps failing must not be resumed forever.
        // Launch-time resume goes through retryUploads().
        if (journal != null) {
            var keep = _host.routineIds();
            var abandoned = journal["routineIds"] as Array;
            for (var i = 0; i < abandoned.size(); i++) {
                if (!UploadLogic.containsString(keep, abandoned[i])) {
                    _store.deletePair("routine." + (abandoned[i] as String));
                }
            }
            _store.deletePair("rsync");
            journal = null;
        }
        if (journal == null) {
            var config = _host.syncConfig();
            if (config == null) {
                return false;
            }
            var sequence = ((config as Dictionary)["routineSyncSeq"] as Number) + 1;
            journal = {
                "sequence" => sequence,
                "phase" => Liftosaur.PHASE_PROGRAM,
                "index" => 0,
                "days" => [],
                "routineIds" => []
            };
            if (!_store.commitPair("rsync", journal as Dictionary)) {
                _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
                return false;
            }
        }
        _host.setErrorCode(Err.NONE);
        _notice = null;
        _retryAttempt = 0;
        _refreshAfterUploads = false;
        _routineSyncRunning = true;
        _uploadRequested = true;
        WatchUi.requestUpdate();
        pumpAsyncWork();
        return true;
    }

    // Called on launch, after a saved workout, and after a manual routine sync.
    public function retryUploads() as Void {
        _retryAttempt = 0;
        resumeWork();
    }

    private function resumeWork() as Void {
        _uploadRequested = true;
        var journal = _store.loadRoutineSync();
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
        } else if (journal != null) {
            _routineSyncRunning = true;
        }
        pumpAsyncWork();
    }

    public function pendingUploadCount() as Number {
        var ids = _store.loadUploadQueue();
        return ids == null ? 0 : ids.size();
    }

    // True when the head upload has stopped on an error (blocked, mapping, program error...).
    public function hasStuckUpload() as Boolean {
        var ids = _store.loadUploadQueue();
        if (ids == null || ids.size() == 0) {
            return false;
        }
        var job = _store.loadUpload(ids[0] as String);
        return job != null && (Model.sameString(job["state"], Liftosaur.STATE_BLOCKED) ||
            job["lastError"] != null);
    }

    // Session id -> "done" | "skipped" | "pending" for the History screen (two small reads).
    public function uploadStatuses() as Dictionary {
        var result = _store.loadUploadStatus();
        var ids = _store.loadUploadQueue();
        for (var i = 0; ids != null && i < ids.size(); i++) {
            result[ids[i]] = Liftosaur.STATUS_PENDING;
        }
        return result;
    }

    public function uploadQueueDamaged() as Boolean {
        return _store.loadUploadQueue() == null;
    }

    // Retires the head upload; the local history of that workout is kept.
    public function skipUpload() as Boolean {
        var ids = _store.loadUploadQueue();
        if (_requestInFlight || ids == null || ids.size() == 0) {
            return false;
        }
        _store.markUploadStatus(ids[0] as String, Liftosaur.STATUS_SKIPPED);
        if (!_store.removeUploadFromQueue(ids[0] as String)) {
            return false;
        }
        _uploadRequested = false;
        _host.setErrorCode(Err.NONE);
        _notice = "Upload skipped";
        WatchUi.requestUpdate();
        return true;
    }

    public function clearUploadQueue() as Boolean {
        if (_requestInFlight) {
            return false;
        }
        _store.clearUploadQueue(true);
        _uploadRequested = false;
        _host.setErrorCode(Err.NONE);
        _notice = "Upload queue cleared";
        WatchUi.requestUpdate();
        return true;
    }

    // Home status while a request is in flight.
    public function activityLabel() as String? {
        if (_routineSyncRunning) {
            return "Syncing…";
        }
        return _uploadRequested && _requestInFlight ? "Uploading…" : null;
    }

    public function infoNotice() as String? {
        return _notice;
    }

    // One-shot timer target: continue sync/upload work outside the response callback.
    public function continueAsyncWork() as Void {
        pumpAsyncWork();
    }

    private function scheduleAsyncWork() as Void {
        _asyncTimer.stop();
        _asyncTimer.start(method(:continueAsyncWork), 150, false);
    }

    private function pumpAsyncWork() as Void {
        if (_requestInFlight) {
            return;
        }
        if (_routineSyncRunning) {
            advanceRoutineSync();
        } else if (_uploadRequested) {
            advanceUploadQueue();
        }
    }

    private function saveRoutineJournal(journal as Dictionary) as Boolean {
        if (!_store.commitPair("rsync", journal)) {
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
            _routineSyncRunning = false;
            WatchUi.requestUpdate();
            return false;
        }
        return true;
    }

    private function advanceRoutineSync() as Void {
        if (!_routineSyncRunning || _requestInFlight) {
            return;
        }
        var journal = _store.loadRoutineSync();
        if (journal == null || _store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _routineSyncRunning = false;
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        var settled = _host.settleRoutineSync(journal as Dictionary);
        if (settled < 0) {
            _routineSyncRunning = false;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        if (settled == 1) {
            _store.deletePair("rsync");
            _routineSyncRunning = false;
            _uploadRequested = true;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        var phase = journal["phase"] as String;
        if (Model.sameString(phase, Liftosaur.PHASE_PROGRAM)) {
            if (!makeApiRequest("/programs/current", Communications.HTTP_REQUEST_METHOD_GET,
                null, false, Liftosaur.REQ_SYNC_PROGRAM, null)) {
                _routineSyncRunning = false;
                pumpAsyncWork();
            }
            return;
        }
        if (Model.sameString(phase, Liftosaur.PHASE_NEXT)) {
            if (!makeApiRequest("/workout/next", Communications.HTTP_REQUEST_METHOD_GET,
                null, false, Liftosaur.REQ_SYNC_NEXT, null)) {
                _routineSyncRunning = false;
                pumpAsyncWork();
            }
            return;
        }
        var days = journal["days"] as Array;
        var index = journal["index"] as Number;
        if (index < days.size()) {
            var day = days[index] as Dictionary;
            var query = {
                "programId" => journal["programId"],
                "week" => day["week"],
                "dayInWeek" => day["dayInWeek"]
            };
            if (!makeApiRequest("/workout/next", Communications.HTTP_REQUEST_METHOD_GET,
                query, false, Liftosaur.REQ_SYNC_DAY, null)) {
                _routineSyncRunning = false;
                pumpAsyncWork();
            }
            return;
        }
        if (!_host.applyRoutineSync(journal as Dictionary)) {
            _routineSyncRunning = false;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        _store.deletePair("rsync");
        _routineSyncRunning = false;
        _host.setErrorCode(Err.NONE);
        _retryAttempt = 0;
        _notice = "Synced " + (journal["routineIds"] as Array).size().toString() +
            ((journal["routineIds"] as Array).size() == 1 ? " day" : " days");
        _uploadRequested = true;
        WatchUi.requestUpdate();
        pumpAsyncWork();
    }

    private function responseBody(data as Object?) as Dictionary? {
        if (!(data instanceof Dictionary)) {
            return null;
        }
        var body = data as Dictionary;
        if (body["data"] instanceof Dictionary) {
            body = body["data"] as Dictionary;
        }
        return body;
    }

    private function errorCodeFrom(data as Object?) as String? {
        var body = data instanceof Dictionary ? data as Dictionary : null;
        if (body != null && body["error"] instanceof Dictionary) {
            body = body["error"] as Dictionary;
        }
        return body != null && body["code"] instanceof String ? body["code"] as String : null;
    }

    private function syncRequestFailed(responseCode as Number, data as Object?) as Void {
        _routineSyncRunning = false;
        var transport = LiftosaurLogic.transportError(responseCode);
        _host.setErrorCode((responseCode == -402 || responseCode == -403) ?
            Err.ROUTINE_SYNC_RESPONSE_TOO_LARGE :
            ((responseCode == 401 || responseCode == 403) ? Err.LIFTOSAUR_UNAUTHORIZED :
                (transport != Err.NONE ? transport : Err.ROUTINE_SYNC_REQUEST_FAILED)));
        if (transport != Err.NONE) {
            scheduleRetry();
        }
        WatchUi.requestUpdate();
        pumpAsyncWork();
    }

    private function routineProgramReceived(data as Object?) as Boolean {
        var body = responseBody(data);
        if (body == null) {
            return false;
        }
        var program = body["program"] instanceof Dictionary ? body["program"] as Dictionary : body;
        var days = program["text"] instanceof String ?
            LiftosaurLogic.parseDays(program["text"] as String) : null;
        if (!Model.validId(program["id"]) || !Model.validNonblankText(program["name"], 64) ||
            days == null || (days as Array).size() == 0 ||
            (days as Array).size() > Model.MAX_PROGRAM_DAYS) {
            return false;
        }
        var journal = _store.loadRoutineSync();
        if (journal == null) {
            return false;
        }
        journal["phase"] = Liftosaur.PHASE_NEXT;
        journal["programId"] = program["id"];
        journal["programName"] = program["name"];
        journal["days"] = days;
        journal["index"] = 0;
        journal["routineIds"] = [];
        journal.remove("nextWeek");
        journal.remove("nextDay");
        return saveRoutineJournal(journal as Dictionary);
    }

    private function routineNextReceived(data as Object?) as Boolean {
        var coordinates = Catalog.nextRoutineCoordinates(data);
        var journal = _store.loadRoutineSync();
        if (coordinates == null || journal == null ||
            !Model.sameString((coordinates as Dictionary)["programId"], journal["programId"])) {
            return false;
        }
        // Only the current week is synced; the program text lists every week.
        var weekDays = LiftosaurLogic.daysForWeek(journal["days"] as Array,
            (coordinates as Dictionary)["week"] as Number);
        if (weekDays.size() == 0) {
            return false;
        }
        journal["days"] = weekDays;
        journal["phase"] = Liftosaur.PHASE_DAYS;
        journal["nextWeek"] = (coordinates as Dictionary)["week"];
        journal["nextDay"] = (coordinates as Dictionary)["dayInWeek"];
        return saveRoutineJournal(journal as Dictionary);
    }

    private function routineDayReceived(data as Object?) as Boolean {
        var journal = _store.loadRoutineSync();
        if (journal == null) {
            return false;
        }
        var index = journal["index"] as Number;
        var routine = Catalog.parseRoutine(data, journal["sequence"] as Number, index + 1);
        if (routine == null) {
            return false;
        }
        var day = (journal["days"] as Array)[index] as Dictionary;
        if (!Model.sameString((routine as Dictionary)["programId"], journal["programId"]) ||
            (routine as Dictionary)["week"] != day["week"] ||
            (routine as Dictionary)["dayInWeek"] != day["dayInWeek"] ||
            !Model.sameString((routine as Dictionary)["name"], day["name"])) {
            return false;
        }
        var id = (routine as Dictionary)["id"] as String;
        if (!_store.commitPair("routine." + id, routine as Dictionary)) {
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
            return false;
        }
        var ids = (journal["routineIds"] as Array).slice(0, null);
        ids.add(id);
        journal["routineIds"] = ids;
        journal["index"] = index + 1;
        return saveRoutineJournal(journal as Dictionary);
    }

    private function findQueuedUpload(id as String) as Dictionary? {
        return _store.loadUpload(id);
    }

    private function advanceUploadQueue() as Void {
        if (!_uploadRequested || _requestInFlight || _routineSyncRunning) {
            return;
        }
        var ids = _store.loadUploadQueue();
        if (ids == null || _store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
            return;
        }
        if (ids.size() == 0) {
            _uploadRequested = false;
            if (_refreshAfterUploads && !_host.hasPendingFinalization() && !_host.hasActiveSession() &&
                liftosaurKey() != null) {
                _refreshAfterUploads = false;
                syncRoutines();
                return;
            }
            if (_host.errorCode() == Err.WORKOUT_UPLOAD_FAILED || _host.errorCode() == Err.WORKOUT_UPLOAD_BLOCKED) {
                _host.setErrorCode(Err.NONE);
            }
            WatchUi.requestUpdate();
            return;
        }
        var id = ids[0] as String;
        var job = findQueuedUpload(id);
        if (job == null || _store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
            return;
        }
        if (Model.sameString(job["state"], Liftosaur.STATE_DONE)) {
            if (_store.removeUploadFromQueue(id)) {
                pumpAsyncWork();
            } else {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                WatchUi.requestUpdate();
            }
            return;
        }
        if (Model.sameString(job["state"], Liftosaur.STATE_BLOCKED)) {
            var unblocked = SessionLogic.copyDictionary(job as Dictionary);
            unblocked["state"] = unblocked["setsBody"] instanceof Dictionary ?
            Liftosaur.STATE_SETS : Liftosaur.STATE_START;
            unblocked.remove("lastError");
            if (!_store.saveUpload(unblocked)) {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                return;
            }
            job = unblocked;
        }
        var key = liftosaurKey();
        if (key == null) {
            _uploadRequested = false;
            _host.setErrorCode(Err.LIFTOSAUR_KEY_REQUIRED);
            WatchUi.requestUpdate();
            return;
        }
        if (_host.errorCode() == Err.WORKOUT_UPLOAD_FAILED || _host.errorCode() == Err.WORKOUT_UPLOAD_BLOCKED ||
            _host.errorCode() == Err.WORKOUT_UPLOAD_PROGRAM_ERROR || _host.errorCode() == Err.WORKOUT_UPLOAD_MAPPING) {
            _host.setErrorCode(Err.NONE);
        }
        _notice = null;
        var state = job["state"] as String;
        if (Model.sameString(state, Liftosaur.STATE_START)) {
            // Non-mutating check first: never open a Liftosaur workout that cannot be filled.
            var routine = (job as Dictionary)["routine"] as Dictionary;
            var query = {"programId" => routine["programId"], "week" => routine["week"],
                "dayInWeek" => routine["dayInWeek"]};
            if (!makeApiRequest("/workout/next", Communications.HTTP_REQUEST_METHOD_GET,
                query, false, Liftosaur.REQ_UPLOAD_PREVIEW, id)) {
                _uploadRequested = false;
            }
        } else if (Model.sameString(state, Liftosaur.STATE_SETS)) {
            var body = job["setsBody"];
            if (!(body instanceof Dictionary)) {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                return;
            }
            // Reacquire the server's current workout ids before resending the durable sets body.
            if (!makeApiRequest("/workout/start", Communications.HTTP_REQUEST_METHOD_POST,
                UploadLogic.startBody(job as Dictionary), true, Liftosaur.REQ_UPLOAD_RESUME_SETS, id)) {
                _uploadRequested = false;
            }
        } else if (Model.sameString(state, Liftosaur.STATE_FINISH)) {
            var body = UploadLogic.finishBody(job as Dictionary);
            if (!makeApiRequest("/workout/finish", Communications.HTTP_REQUEST_METHOD_POST,
                body, true, Liftosaur.REQ_UPLOAD_FINISH, id)) {
                _uploadRequested = false;
            }
        } else {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
        }
    }

    private function markUploadBlocked(id as String, job as Dictionary,
                                       detail as String?) as Void {
        var blocked = SessionLogic.copyDictionary(job);
        blocked["state"] = Liftosaur.STATE_BLOCKED;
        blocked["lastError"] = detail == null ? Liftosaur.ERR_ALREADY_ACTIVE : detail;
        if (!_store.saveUpload(blocked)) {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
            return;
        }
        _uploadRequested = false;
        _host.setErrorCode(Err.WORKOUT_UPLOAD_BLOCKED);
        WatchUi.requestUpdate();
    }

    // Permanent mismatch (program changed): stays queued but is not "blocked" by an open workout.
    private function markUploadMismatch(id as String, job as Dictionary) as Void {
        var failed = SessionLogic.copyDictionary(job);
        failed["lastError"] = Liftosaur.ERR_PROGRAM_CHANGED;
        _uploadRequested = false;
        _host.setErrorCode(_store.saveUpload(failed) ? Err.WORKOUT_UPLOAD_MAPPING :
            Err.UPLOAD_QUEUE_DAMAGED);
        WatchUi.requestUpdate();
    }

    private function markUploadDone(id as String, job as Dictionary) as Void {
        var done = SessionLogic.copyDictionary(job);
        done["state"] = Liftosaur.STATE_DONE;
        done.remove("setsBody");
        done.remove("lastError");
        _store.markUploadStatus(id, Liftosaur.STATE_DONE);
        _retryAttempt = 0;
        if (!_store.saveUpload(done) || !_store.removeUploadFromQueue(id)) {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
            return;
        }
        _host.setErrorCode(Err.NONE);
        _notice = "Workout uploaded";
        WatchUi.requestUpdate();
        var remaining = _store.loadUploadQueue();
        if (remaining != null && remaining.size() == 0 && !_routineSyncRunning) {
            _refreshAfterUploads = true;
        }
        pumpAsyncWork();
    }

    private function postUploadSets(id as String, job as Dictionary) as Void {
        var body = job["setsBody"];
        if (!(body instanceof Dictionary) ||
            !makeApiRequest("/workout/sets", Communications.HTTP_REQUEST_METHOD_POST,
                body as Dictionary, true, Liftosaur.REQ_UPLOAD_SETS, id)) {
            _uploadRequested = false;
            _host.setErrorCode(body instanceof Dictionary ? Err.WORKOUT_UPLOAD_FAILED :
                Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
        }
    }

    private function uploadFailed(responseCode as Number, data as Object?,
                                  uploadId as String?, job as Dictionary?) as Void {
        var code = errorCodeFrom(data);
        if (code != null && Model.sameString(code, Liftosaur.ERR_ALREADY_ACTIVE)) {
            if (uploadId != null && job != null) {
                markUploadBlocked(uploadId as String, job as Dictionary, code as String);
                return;
            }
        }
        if (uploadId != null && job != null) {
            var failed = SessionLogic.copyDictionary(job as Dictionary);
            failed["lastError"] = code != null && (code as String).length() <= 48 ?
                code as String : "http-" + responseCode.toString();
            if (!_store.saveUpload(failed)) {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                WatchUi.requestUpdate();
                return;
            }
        }
        _uploadRequested = false;
        var transport = LiftosaurLogic.transportError(responseCode);
        _host.setErrorCode((responseCode == 401 || responseCode == 403) ? Err.LIFTOSAUR_UNAUTHORIZED :
            (responseCode == 422 && code != null && Model.sameString(code, Liftosaur.ERR_PROGRAM_ERROR) ?
                Err.WORKOUT_UPLOAD_PROGRAM_ERROR :
                (transport != Err.NONE ? transport : Err.WORKOUT_UPLOAD_FAILED)));
        if (transport != Err.NONE) {
            scheduleRetry();
        }
        WatchUi.requestUpdate();
    }

    public function onApiResponse(responseCode as Number,
                                  data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        var purpose = _responsePurpose;
        var uploadId = _responseUploadId;
        _requestInFlight = false;
        _responsePurpose = null;
        _responseUploadId = null;
        handleApiResponse(purpose, uploadId, responseCode, data);
    }

    // Shared response handler keeps callback behavior directly testable without making requests.
    public function handleApiResponse(purpose as String?, uploadId as String?,
                                      responseCode as Number,
                                      data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        _requestInFlight = false;
        if (purpose == null) {
            pumpAsyncWork();
            return;
        }
        var ok = responseCode >= 200 && responseCode < 300;
        if (Model.sameString(purpose, Liftosaur.REQ_KEY_TEST)) {
            keyTestDone(responseCode, data);
            pumpAsyncWork();
            return;
        }
        if (Model.sameString(purpose, Liftosaur.REQ_SYNC_PROGRAM) || Model.sameString(purpose, Liftosaur.REQ_SYNC_NEXT) ||
            Model.sameString(purpose, Liftosaur.REQ_SYNC_DAY)) {
            if (!ok) {
                syncRequestFailed(responseCode, data);
                return;
            }
            var parseStart = System.getTimer();
            var accepted = Model.sameString(purpose, Liftosaur.REQ_SYNC_PROGRAM) ?
                routineProgramReceived(data) : (Model.sameString(purpose, Liftosaur.REQ_SYNC_NEXT) ?
                    routineNextReceived(data) : routineDayReceived(data));
            _host.noteSyncMs(System.getTimer() - parseStart);
            if (!accepted) {
                _routineSyncRunning = false;
                if (_host.errorCode() != Err.ROUTINE_SYNC_SAVE_FAILED) {
                    _host.setErrorCode(Err.ROUTINE_SYNC_INVALID_RESPONSE);
                }
                WatchUi.requestUpdate();
                pumpAsyncWork();
                return;
            }
            // The last day's continuation (pivot) is heavy: run it in its own callback.
            scheduleAsyncWork();
            return;
        }
        var job = uploadId == null ? null : _store.loadUpload(uploadId as String);
        if (job == null || _store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _uploadRequested = false;
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            WatchUi.requestUpdate();
            return;
        }
        if ((Model.sameString(purpose, Liftosaur.REQ_UPLOAD_START) ||
             Model.sameString(purpose, Liftosaur.REQ_UPLOAD_RESUME_SETS)) && responseCode == 409) {
            var code = errorCodeFrom(data);
            if (code != null && Model.sameString(code, Liftosaur.ERR_START_TIME_TAKEN)) {
                markUploadDone(uploadId as String, job as Dictionary);
                return;
            }
            if (code != null && Model.sameString(code, Liftosaur.ERR_ALREADY_ACTIVE)) {
                // Crash-resume: the open workout may be ours (same startTime); ask Liftosaur.
                if (!makeApiRequest("/workout/current", Communications.HTTP_REQUEST_METHOD_GET,
                    null, false, Model.sameString(purpose, Liftosaur.REQ_UPLOAD_START) ?
                        Liftosaur.REQ_UPLOAD_CURRENT : Liftosaur.REQ_UPLOAD_CURRENT_RESUME, uploadId)) {
                    markUploadBlocked(uploadId as String, job as Dictionary, code as String);
                }
                return;
            }
        }
        var currentCheck = Model.sameString(purpose, Liftosaur.REQ_UPLOAD_CURRENT) ||
            Model.sameString(purpose, Liftosaur.REQ_UPLOAD_CURRENT_RESUME);
        if (currentCheck && !ok) {
            markUploadBlocked(uploadId as String, job as Dictionary, Liftosaur.ERR_ALREADY_ACTIVE);
            return;
        }
        if (!ok) {
            uploadFailed(responseCode, data, uploadId,
                job instanceof Dictionary ? job as Dictionary : null);
            return;
        }
        if (Model.sameString(purpose, Liftosaur.REQ_UPLOAD_PREVIEW)) {
            if (!UploadLogic.previewMaps(job as Dictionary, data)) {
                markUploadMismatch(uploadId as String, job as Dictionary);
                return;
            }
            if (!makeApiRequest("/workout/start", Communications.HTTP_REQUEST_METHOD_POST,
                UploadLogic.startBody(job as Dictionary), true, Liftosaur.REQ_UPLOAD_START, uploadId)) {
                _uploadRequested = false;
                WatchUi.requestUpdate();
            }
            return;
        }
        if (Model.sameString(purpose, Liftosaur.REQ_UPLOAD_START) ||
            Model.sameString(purpose, Liftosaur.REQ_UPLOAD_RESUME_SETS) || currentCheck) {
            var started = UploadLogic.withStartedWorkout(job as Dictionary, data);
            if (started == null) {
                if (currentCheck) {
                    markUploadBlocked(uploadId as String, job as Dictionary,
                        Liftosaur.ERR_ALREADY_ACTIVE);
                } else {
                    markUploadMismatch(uploadId as String, job as Dictionary);
                }
                return;
            }
            if (Model.sameString(purpose, Liftosaur.REQ_UPLOAD_RESUME_SETS) ||
                Model.sameString(purpose, Liftosaur.REQ_UPLOAD_CURRENT_RESUME)) {
                var resumed = SessionLogic.copyDictionary(started as Dictionary);
                resumed["state"] = Liftosaur.STATE_SETS;
                resumed["setsBody"] = (job as Dictionary)["setsBody"];
                started = resumed;
            }
            (started as Dictionary).remove("lastError");
            if (!_store.saveUpload(started as Dictionary)) {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                return;
            }
            if (Model.sameString(started["state"], Liftosaur.STATE_SETS)) {
                postUploadSets(uploadId as String, started as Dictionary);
                return;
            }
            _host.setErrorCode(Err.NONE);
            pumpAsyncWork();
            return;
        } else if (Model.sameString(purpose, Liftosaur.REQ_UPLOAD_SETS)) {
            var done = UploadLogic.setsDone(job as Dictionary);
            (done as Dictionary).remove("lastError");
            if (!_store.saveUpload(done as Dictionary)) {
                _uploadRequested = false;
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                return;
            }
        } else if (Model.sameString(purpose, Liftosaur.REQ_UPLOAD_FINISH)) {
            markUploadDone(uploadId as String, job as Dictionary);
            return;
        }
        _host.setErrorCode(Err.NONE);
        WatchUi.requestUpdate();
        pumpAsyncWork();
    }

    public function enqueueFinalWorkout(ended as Dictionary) as Boolean {
        var made = UploadLogic.makeJob(ended);
        if (made == null) {
            return true; // Not a Liftosaur routine day, or no completed mapped sets.
        }
        var id = (made as Dictionary)["sessionId"] as String;
        var existing = _store.loadUpload(id);
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            return false;
        }
        var job = existing == null ? made as Dictionary : existing as Dictionary;
        var ids = _store.loadUploadQueue();
        if (ids == null) {
            if (_store.hasUnsupportedRecord()) {
                // Written by a newer app: leave it alone; the workout stays in local history only.
                _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
                return true;
            }
            // Corrupt manifest: reset it so finishing never depends on it.
            _store.clearUploadQueue(false);
            ids = [];
        } else if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            return false;
        }
        if (UploadLogic.containsString(ids as Array, id)) {
            return true;
        }
        if (ids.size() >= QueueLimits.MAX_PENDING_UPLOADS) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_FULL);
            return false;
        }
        var nextIds = UploadLogic.enqueue(ids, job as Dictionary);
        if (nextIds == null) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_FULL);
            return false;
        }
        // The job is durable before the queue manifest can reference it. If the manifest write
        // fails, finalization remains active and the same session id reuses the saved job.
        if (existing == null && !_store.saveUpload(job as Dictionary)) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            return false;
        }
        if (!_store.saveUploadQueue(nextIds as Array)) {
            _host.setErrorCode(Err.UPLOAD_QUEUE_DAMAGED);
            return false;
        }
        return true;
    }
}
