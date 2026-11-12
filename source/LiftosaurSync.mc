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
    // Created on first use (a device allows few timers; test controllers never start any).
    private var _asyncTimer as Timer.Timer? = null;
    private var _retryTimer as Timer.Timer? = null;
    private var _retryAttempt as Number = 0;
    // The journal while a sync runs (loaded once, then replaced by each committed step); only
    // trusted while _routineSyncRunning or a step is staged, else the store is read again.
    private var _journal as Dictionary? = null;
    // A day/program reply is handled in three steps so no callback holds the raw reply together
    // with storage work: the web callback validates and projects (STAGE_ROUTINE or STAGE_JOURNAL
    // follows), then the 150 ms timer commits the routine, then the journal and sends the next
    // request. A relaunch before the journal commit resumes at the same day (the routine is
    // rewritten under the same id).
    private var _stage as Number = 0;
    private var _pendingRoutine as Dictionary? = null;
    private var _pendingJournal as Dictionary? = null;
    private var _pendingReply as Object? = null;
    private var _pendingTag as String = "";
    const STAGE_NONE = 0;
    const STAGE_ROUTINE = 1;
    const STAGE_JOURNAL = 2;
    const STAGE_PROJECT = 3;

    public function initialize(store as Store, host as SessionController) {
        _store = store;
        _host = host;
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
            (pendingUploadCount() == 0 && _journal == null && _store.loadRoutineSync() == null)) {
            return;
        }
        if (_retryTimer == null) {
            _retryTimer = new Timer.Timer();
        }
        (_retryTimer as Timer.Timer).stop();
        (_retryTimer as Timer.Timer).start(method(:retryNow), LiftosaurLogic.retryDelayMinutes(_retryAttempt) * 60000,
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
        if (!enoughMemory(purpose)) {
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

    // A sync reply is held whole while it is converted; with too little free memory the request
    // would end in a crash, so stop first with a recoverable error and a reason in Diagnostics.
    private function enoughMemory(purpose as String) as Boolean {
        var need = LiftosaurLogic.syncMemoryNeed(purpose);
        if (need == 0) {
            return true;
        }
        var free = System.getSystemStats().freeMemory;
        if (LiftosaurLogic.enoughFree(purpose, free)) {
            return true;
        }
        // The loaded routines are the big resident part: drop them and look again.
        _host.releaseConfigCache();
        free = System.getSystemStats().freeMemory;
        if (LiftosaurLogic.enoughFree(purpose, free)) {
            return true;
        }
        _host.setErrorCode(Err.SYNC_LOW_MEMORY);
        LiftosaurLogic.saveSyncProblem("Low memory: " + (free / 1024).toString() + " KB free, " +
            (need / 1024).toString() + " KB needed");
        WatchUi.requestUpdate();
        return false;
    }

    // The journal of the running sync: the in-memory copy, else one read from the store.
    private function syncJournal() as Dictionary? {
        if (_journal == null) {
            _journal = _store.loadRoutineSync();
        }
        return _journal;
    }

    private function dropStaged() as Void {
        if (_asyncTimer != null) {
            (_asyncTimer as Timer.Timer).stop();
        }
        _stage = STAGE_NONE;
        _pendingRoutine = null;
        _pendingJournal = null;
        _pendingReply = null;
    }

    // Steps staged by a reply handler; the host (tests) may run them without the timer.
    public function pendingSteps() as Number {
        return _stage == STAGE_PROJECT ? 3 : (_stage == STAGE_ROUTINE ? 2 :
            (_stage == STAGE_JOURNAL ? 1 : 0));
    }

    // Runs the next staged commit (no request is sent). A failed commit ends the sync with
    // ROUTINE_SYNC_SAVE_FAILED; the journal in the store is then still the last committed one.
    public function runPendingStep() as Void {
        Breadcrumb.enter(_stage == STAGE_PROJECT ? Breadcrumb.STEP_SYNC_DAY :
            (_stage == STAGE_ROUTINE ? Breadcrumb.STEP_ROUTINE_COMMIT : Breadcrumb.STEP_JOURNAL_COMMIT),
            Breadcrumb.week, Breadcrumb.day);
        runPendingStepBody();
        Breadcrumb.leave();
    }

    private function runPendingStepBody() as Void {
        if (_stage == STAGE_PROJECT) {
            stepProjectRoutine();
        } else if (_stage == STAGE_ROUTINE) {
            stepValidateAndCommitRoutine();
        } else if (_stage == STAGE_JOURNAL) {
            var journal = _pendingJournal as Dictionary;
            dropStaged();
            if (!_store.commitPair("rsync", journal)) {
                stageFailed();
                return;
            }
            _journal = journal;
        }
    }

    // Step one b (day replies with exercises): the projection of the checked reply into the
    // compact routine; the raw reply is dropped here.
    private function stepProjectRoutine() as Void {
        var reply = _pendingReply;
        _pendingReply = null;
        var journal = _pendingJournal as Dictionary;
        var routine = Catalog.projectChecked(reply, journal["sequence"] as Number,
            journal["index"] as Number);
        reply = null;
        if (routine == null) {
            // Exercises NextSet cannot run: the day is skipped, the reason goes to Diagnostics.
            journal["skipCount"] = (journal["skipCount"] instanceof Number ?
                journal["skipCount"] as Number : 0) + 1;
            journal["skipNote"] = Catalog.lastProblem == null ? _pendingTag + ": not supported" :
                Catalog.lastProblem as String;
            _stage = STAGE_JOURNAL;
            return;
        }
        var ids = (journal["routineIds"] as Array).slice(0, null);
        ids.add((routine as Dictionary)["id"]);
        journal["routineIds"] = ids;
        _pendingRoutine = routine;
        _stage = STAGE_ROUTINE;
    }

    // Step two: the single validation of the projected routine, then its commit. A routine
    // NextSet cannot run is skipped like an unsupported day (the journal step records it).
    private function stepValidateAndCommitRoutine() as Void {
        var routine = _pendingRoutine as Dictionary;
        _pendingRoutine = null;
        if (!Catalog.validRoutine(routine) ||
            !Model.validNonblankText(routine["name"], Model.MAX_DAY_NAME_BYTES)) {
            var journal = _pendingJournal as Dictionary;
            // The id was appended by the reply step: drop it again.
            var all = journal["routineIds"] as Array;
            journal["routineIds"] = all.slice(0, all.size() - 1);
            journal["skipCount"] = (journal["skipCount"] instanceof Number ?
                journal["skipCount"] as Number : 0) + 1;
            journal["skipNote"] = "W" + routine["week"].toString() + " D" +
                routine["dayInWeek"].toString() + ": routine rejected";
            _stage = STAGE_JOURNAL;
            return;
        }
        if (!_store.commitPairChecked("routine." + (routine["id"] as String), routine)) {
            stageFailed();
            return;
        }
        _stage = STAGE_JOURNAL;
    }

    private function stageFailed() as Void {
        dropStaged();
        _journal = null;
        _routineSyncRunning = false;
        _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
        WatchUi.requestUpdate();
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
        dropStaged();
        _journal = null;
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
                "phase" => Liftosaur.PHASE_FIRST,
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
        if (_stage != STAGE_NONE) {
            runPendingStep();
            if (_stage != STAGE_NONE) {
                scheduleAsyncWork();
                return;
            }
        }
        pumpAsyncWork();
    }

    private function scheduleAsyncWork() as Void {
        if (_asyncTimer == null) {
            _asyncTimer = new Timer.Timer();
        }
        (_asyncTimer as Timer.Timer).stop();
        (_asyncTimer as Timer.Timer).start(method(:continueAsyncWork), 150, false);
    }

    private function pumpAsyncWork() as Void {
        if (_requestInFlight || _stage != STAGE_NONE) {
            return;
        }
        if (_routineSyncRunning) {
            advanceRoutineSync();
        } else if (_uploadRequested) {
            advanceUploadQueue();
        }
    }

    private function advanceRoutineSync() as Void {
        if (!_routineSyncRunning || _requestInFlight) {
            return;
        }
        var journal = syncJournal();
        if (journal == null) {
            _routineSyncRunning = false;
            _host.setErrorCode(Err.ROUTINE_SYNC_SAVE_FAILED);
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        var settled = _host.settleRoutineSync(journal as Dictionary);
        if (settled < 0) {
            _routineSyncRunning = false;
            _journal = null;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        if (settled == 1) {
            _store.deletePair("rsync");
            _journal = null;
            _routineSyncRunning = false;
            _uploadRequested = true;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        var phase = journal["phase"] as String;
        var path = null;
        var query = null;
        var purpose = Liftosaur.REQ_SYNC_DAY;
        if (Model.sameString(phase, Liftosaur.PHASE_PROGRAM) ||
            Model.sameString(phase, Liftosaur.PHASE_WEEK)) {
            path = "/programs/current";
            purpose = Liftosaur.REQ_SYNC_PROGRAM;
        } else if (Model.sameString(phase, Liftosaur.PHASE_NEXT) ||
            Model.sameString(phase, Liftosaur.PHASE_FIRST)) {
            path = "/workout/next";
            purpose = Liftosaur.REQ_SYNC_NEXT;
        } else {
            var days = journal["days"] as Array;
            var index = journal["index"] as Number;
            if (index < days.size()) {
                var day = days[index] as Dictionary;
                Breadcrumb.at(day["week"] as Number, day["dayInWeek"] as Number);
                path = "/workout/next";
                query = {
                    "programId" => journal["programId"],
                    "week" => day["week"],
                    "dayInWeek" => day["dayInWeek"]
                };
            }
        }
        if (path != null) {
            if (!makeApiRequest(path as String, Communications.HTTP_REQUEST_METHOD_GET,
                query as Dictionary?, false, purpose, null)) {
                _routineSyncRunning = false;
                _journal = null;
                pumpAsyncWork();
            }
            return;
        }
        Breadcrumb.enter(Breadcrumb.STEP_SYNC_PIVOT, 0, 0);
        var applied = _host.applyRoutineSync(journal as Dictionary);
        Breadcrumb.leave();
        if (!applied) {
            if (_host.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE) {
                LiftosaurLogic.saveSyncProblem(journal["skipNote"] instanceof String ?
                    journal["skipNote"] as String : "No day with exercises this week");
            }
            _routineSyncRunning = false;
            _journal = null;
            WatchUi.requestUpdate();
            pumpAsyncWork();
            return;
        }
        _store.deletePair("rsync");
        // A day skipped as unsupported keeps its reason in Diagnostics; a clean sync clears it.
        LiftosaurLogic.saveSyncProblem(journal["skipNote"] instanceof String ?
            journal["skipNote"] as String : null);
        _routineSyncRunning = false;
        _journal = null;
        _host.setErrorCode(Err.NONE);
        Breadcrumb.clearLast();
        _retryAttempt = 0;
        var skipped = journal["skipCount"] instanceof Number ? journal["skipCount"] as Number : 0;
        _notice = "Synced " + (journal["routineIds"] as Array).size().toString() +
            ((journal["routineIds"] as Array).size() == 1 ? " day" : " days") +
            (skipped > 0 ? ", " + skipped.toString() + " skipped" : "");
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
        _journal = null;
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

    // Short reason of the rejection being reported; saved by handleApiResponse.
    private var _problem as String? = null;

    private function reject(text as String) as Boolean {
        _problem = Model.fit(text, 60);
        return false;
    }

    // Step one of a reply: the next journal is only built here and committed later.
    private function stageJournal(journal as Dictionary, routine as Dictionary?) as Boolean {
        _pendingRoutine = routine;
        _pendingJournal = journal;
        _stage = routine == null ? STAGE_JOURNAL : STAGE_ROUTINE;
        return true;
    }

    // A week with more than eight days syncs the first eight; the rest is noted.
    private function noteSkippedDays(journal as Dictionary, week as Number, named as Number) as Void {
        if (named > Model.MAX_TEMPLATES) {
            journal["skipCount"] = named - Model.MAX_TEMPLATES;
            journal["skipNote"] = "Week " + week.toString() + ": days " +
                (Model.MAX_TEMPLATES + 1).toString() + "-" + named.toString() + " skipped (max " +
                Model.MAX_TEMPLATES.toString() + ")";
        }
    }

    private function routineProgramReceived(data as Object?) as Boolean {
        var body = responseBody(data);
        if (body == null) {
            return reject("/programs/current reply invalid");
        }
        var program = body["program"] instanceof Dictionary ? body["program"] as Dictionary : body;
        if (!(program["text"] instanceof String)) {
            return reject("Program has no text");
        }
        var journal = syncJournal();
        if (journal == null) {
            return reject("Sync journal unreadable");
        }
        var week = Model.sameString(journal["phase"], Liftosaur.PHASE_WEEK) ?
            journal["nextWeek"] as Number : 0;
        var weeks = LiftosaurLogic.parseDaysFor(program["text"] as String, week);
        if (weeks == null) {
            return reject(LiftosaurLogic.parseProblem == null ? "Program text rejected" :
                LiftosaurLogic.parseProblem as String);
        }
        if (!Model.validId(program["id"]) || !Model.validNonblankText(program["name"], 64)) {
            return reject("Program id or name invalid");
        }
        var next = SessionLogic.copyDictionary(journal);
        next["programName"] = program["name"];
        next["index"] = 0;
        next["routineIds"] = [];
        if (week > 0) {
            // Week already known from /workout/next: keep only its days.
            if (!Model.sameString(program["id"], journal["programId"])) {
                return reject("Program changed during sync");
            }
            var rows = LiftosaurLogic.weekDayRows(weeks, week);
            if (rows == null) {
                return reject(LiftosaurLogic.parseProblem as String);
            }
            noteSkippedDays(next, week, ((weeks[week - 1]) as Array).size());
            next["days"] = rows;
            next["phase"] = Liftosaur.PHASE_DAYS;
            return stageJournal(next, null);
        }
        // Older flow (journal written by a version that asked /programs/current first).
        next["phase"] = Liftosaur.PHASE_NEXT;
        next["programId"] = program["id"];
        next["weeks"] = weeks;
        next.remove("days");
        next.remove("nextWeek");
        next.remove("nextDay");
        return stageJournal(next, null);
    }

    private function routineNextReceived(data as Object?) as Boolean {
        var coordinates = Catalog.dayCoordinates(data);
        var journal = syncJournal();
        if (coordinates == null) {
            var why = Model.liftosaurWorkoutProblem(data);
            return reject(why == null ? "/workout/next reply invalid" : why);
        }
        if (journal == null) {
            return reject("Sync journal unreadable");
        }
        var next = SessionLogic.copyDictionary(journal);
        var week = (coordinates as Dictionary)["week"] as Number;
        if (Model.sameString(journal["phase"], Liftosaur.PHASE_FIRST)) {
            // Which week is current is known now; /programs/current is parsed for that week only.
            next["phase"] = Liftosaur.PHASE_WEEK;
            next["programId"] = (coordinates as Dictionary)["programId"];
            next["nextWeek"] = week;
            next["nextDay"] = (coordinates as Dictionary)["dayInWeek"];
            next["index"] = 0;
            next["routineIds"] = [];
            next.remove("days");
            next.remove("skipCount");
            next.remove("skipNote");
            return stageJournal(next, null);
        }
        if (!Model.sameString((coordinates as Dictionary)["programId"], journal["programId"])) {
            return reject("Program changed during sync");
        }
        // Only the current week is synced; the program text lists every week.
        var weekDays = null;
        if (journal["weeks"] instanceof Array) {
            weekDays = LiftosaurLogic.weekDayRows(journal["weeks"] as Array, week);
            if (weekDays == null) {
                return reject(LiftosaurLogic.parseProblem as String);
            }
            noteSkippedDays(next, week, ((journal["weeks"] as Array)[week - 1] as Array).size());
        } else if (journal["days"] instanceof Array) {
            // Journal written before weeks were stored by position.
            weekDays = LiftosaurLogic.daysForWeek(journal["days"] as Array, week);
            if (weekDays.size() == 0 || weekDays.size() > Model.MAX_TEMPLATES) {
                return reject("Week " + week.toString() + " not usable in program text");
            }
        } else {
            return reject("Sync journal has no days");
        }
        next["days"] = weekDays;
        next.remove("weeks");
        next["phase"] = Liftosaur.PHASE_DAYS;
        next["nextWeek"] = (coordinates as Dictionary)["week"];
        next["nextDay"] = (coordinates as Dictionary)["dayInWeek"];
        return stageJournal(next, null);
    }

    private function routineDayReceived(data as Object?) as Boolean {
        var journal = syncJournal();
        if (journal == null) {
            return reject("Sync journal unreadable");
        }
        var index = journal["index"] as Number;
        var days = journal["days"];
        // A stray reply (journal not at the day step, or all days done) must not index past the list.
        if (!(days instanceof Array) || index >= (days as Array).size()) {
            return reject("Day reply does not match the sync step");
        }
        var expected = (days as Array)[index] as Dictionary;
        var tag = "W" + expected["week"].toString() + " D" + expected["dayInWeek"].toString();
        var coordinates = Catalog.dayCoordinates(data);
        if (coordinates == null) {
            var why = Model.liftosaurWorkoutProblem(data);
            return reject(why == null ? tag + ": day reply invalid" : why);
        }
        if (!Model.sameString((coordinates as Dictionary)["programId"], journal["programId"])) {
            return reject(tag + ": program differs from API");
        }
        if ((coordinates as Dictionary)["week"] != expected["week"] ||
            (coordinates as Dictionary)["dayInWeek"] != expected["dayInWeek"]) {
            return reject(tag + ": API sent another week or day");
        }
        if (!LiftosaurLogic.dayNameMatches((coordinates as Dictionary)["name"], expected["name"])) {
            return reject(tag + ": day name differs from API");
        }
        var hasExercises = (coordinates as Dictionary)["exercises"] != 0;
        var next = SessionLogic.copyDictionary(journal);
        next["index"] = index + 1;
        if (hasExercises && Catalog.checkReply(data)) {
            // The projection runs in the next step; the reply is kept until then.
            _pendingReply = data;
            _pendingTag = tag;
            _pendingJournal = next;
            _pendingRoutine = null;
            _stage = STAGE_PROJECT;
            return true;
        }
        if (hasExercises) {
            // A day with exercises NextSet cannot run is skipped: the other days still sync.
            // The reason of an unsupported day goes to Diagnostics.
            next["skipCount"] = (journal["skipCount"] instanceof Number ?
                journal["skipCount"] as Number : 0) + 1;
            next["skipNote"] = Catalog.lastProblem == null ? tag + ": not supported" :
                Catalog.lastProblem as String;
        }
        return stageJournal(next, null);
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
        Breadcrumb.enterForPurpose(purpose);
        handleApiResponseBody(purpose, uploadId, responseCode, data);
        Breadcrumb.leave();
    }

    private function handleApiResponseBody(purpose as String?, uploadId as String?,
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
            if (_stage != STAGE_NONE) {
                // Defensive: finish an earlier reply's commits before taking this one.
                while (_stage != STAGE_NONE) {
                    runPendingStep();
                }
            } else if (!_routineSyncRunning) {
                _journal = null;
            }
            _host.releaseConfigCache();
            var parseStart = System.getTimer();
            var accepted = Model.sameString(purpose, Liftosaur.REQ_SYNC_PROGRAM) ?
                routineProgramReceived(data) : (Model.sameString(purpose, Liftosaur.REQ_SYNC_NEXT) ?
                    routineNextReceived(data) : routineDayReceived(data));
            _host.noteSyncMs(System.getTimer() - parseStart);
            if (!accepted) {
                _routineSyncRunning = false;
                _journal = null;
                if (_host.errorCode() != Err.ROUTINE_SYNC_SAVE_FAILED) {
                    _host.setErrorCode(Err.ROUTINE_SYNC_INVALID_RESPONSE);
                    LiftosaurLogic.saveSyncProblem(_problem == null ? "Reply rejected" : _problem);
                }
                _problem = null;
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
