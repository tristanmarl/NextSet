import Toybox.Lang;
import Toybox.Communications;
import Toybox.Math;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class SessionController {
    private var _store as Store;
    private var _recorder as StrengthRecorder;
    private var _session as Dictionary? = null;
    private var _errorCode as Number = Err.NONE;
    private var _stored as Boolean = false;
    private var _recoveryBlocked as Boolean = false;
    private var _activeUnsupported as Boolean = false;
    private var _activeCorrupt as Boolean = false;
    private var _fitSavedInMemory as Boolean = false;
    private var _pendingStartConfig as Dictionary? = null;
    private var _pendingStartSession as Dictionary? = null;
    private var _startSequenceReserved as Boolean = false;
    private var _historySaved as Boolean = false;
    private var _cacheSaved as Boolean = false;
    private var _historyAlreadyWritten as Boolean = false;
    private var _pendingRecorderState as Dictionary? = null;
    private var _pendingHistory as Dictionary? = null;
    private var _preAlertRestId as Number = -1;
    private var _sync as LiftosaurSync;
    private var _draftDirty as Boolean = false;
    private var _draftTimer as Timer.Timer;
    private var _maxCommitMs as Number = 0;
    private var _syncMs as Number = -1;

    public function initialize(store as Store) {
        _store = store;
        _sync = new LiftosaurSync(store, self);
        _draftTimer = new Timer.Timer();
        _recorder = new StrengthRecorder();
        _session = _store.loadPair("active");
        if (_session != null && _session["setRun"] != null) {
            // 0.3.1 kept a per-set clock; sets now log in one press, so a saved one is dropped.
            var cleaned = SessionLogic.copyDictionary(_session as Dictionary);
            cleaned.remove("setRun");
            _session = cleaned;
        }
        _activeUnsupported = _store.hasUnsupportedRecord();
        _activeCorrupt = _session == null && _store.hasCorruptRecord();
        if (_session != null &&
            (Model.sameString(_session["status"], "completed") ||
             Model.sameString(_session["status"], "aborted"))) {
            _session = null;
        }
        if (_store.hasUnsupportedRecord()) {
            _errorCode = Err.UPDATE_APP_TO_RESUME;
        } else if (_store.hasCorruptRecord() && _session == null) {
            _errorCode = Err.SAVED_WORKOUT_IS_DAMAGED;
        } else if (_store.recoveredEarlierGeneration()) {
            _errorCode = Err.RECOVERED_EARLIER_CHECKPOINT;
        }
        restoreUploadNotice();
        if (hasActiveSession()) {
            recoverRunningSession(Time.now().value());
        }
    }

    private function restoreUploadNotice() as Void {
        if (_errorCode != Err.NONE) {
            return;
        }
        var ids = _store.loadUploadQueue();
        if (ids == null || ids.size() == 0) {
            if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
                _errorCode = Err.UPLOAD_QUEUE_DAMAGED;
            }
            return;
        }
        var job = _store.loadUpload(ids[0] as String);
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord() || job == null) {
            _errorCode = Err.UPLOAD_QUEUE_DAMAGED;
            return;
        }
        var error = job["lastError"];
        if (Model.sameString(error, Liftosaur.ERR_PROGRAM_ERROR)) {
            _errorCode = Err.WORKOUT_UPLOAD_PROGRAM_ERROR;
        } else if (Model.sameString(error, Liftosaur.ERR_PROGRAM_CHANGED)) {
            _errorCode = Err.WORKOUT_UPLOAD_MAPPING;
        } else if (Model.sameString(job["state"], Liftosaur.STATE_BLOCKED)) {
            _errorCode = Err.WORKOUT_UPLOAD_BLOCKED;
        } else if (Model.sameString(error, "http-401") || Model.sameString(error, "http-403")) {
            _errorCode = Err.LIFTOSAUR_UNAUTHORIZED;
        } else if (error != null) {
            _errorCode = Err.WORKOUT_UPLOAD_FAILED;
        }
    }

    public function session() as Dictionary? {
        return _session;
    }

    public function errorMessage() as String? {
        return Err.message(_errorCode);
    }

    public function errorCode() as Number {
        return _errorCode;
    }

    public function configurationEditable() as Boolean {
        return !hasActiveSession() && !hasPendingFinalization() &&
            !_activeUnsupported && !_activeCorrupt;
    }

    private var _config as Dictionary? = null;

    private function defaultConfig() as Dictionary {
        var settings = {
            "defaultRestSec" => 90,
            "vibrationEnabled" => true
        };
        return {
            "schemaVersion" => 4,
            "nextSessionSeq" => 1,
            "settings" => settings,
            "incrementOverrides" => {},
            "routines" => [],
            "routineSyncSeq" => 0,
            "programId" => null,
            "programName" => null,
            "nextRoutineId" => null
        };
    }

    // Cached, validated config. Returns a shallow copy: callers may replace top-level
    // keys but must copy nested values (routines, settings, overrides) before mutating.
    private function readConfig() as Dictionary? {
        if (_config == null) {
            _config = loadConfig();
        }
        return _config == null ? null : SessionLogic.copyDictionary(_config as Dictionary);
    }

    private function loadConfig() as Dictionary? {
        var stored = _store.loadPair("config");
        if (_store.hasUnsupportedRecord() || (_store.hasCorruptRecord() && stored == null)) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        if (stored == null) {
            // Nothing stored yet: seed routines are written together with the config on the first save.
            _stored = false;
            return defaultConfig();
        }
        var config = SessionLogic.copyDictionary(stored as Dictionary);
        if (!(config["nextSessionSeq"] instanceof Number) || config["nextSessionSeq"] < 1) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        if (config["schemaVersion"] != 4) {
            // Beta: older schemas are not migrated. Start from the defaults, keeping only the
            // session counter so new session ids stay unique.
            var fresh = defaultConfig();
            fresh["nextSessionSeq"] = config["nextSessionSeq"];
            _stored = false;
            return fresh;
        }
        if (!(config["routineIds"] instanceof Array)) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        var routines = loadRoutines(config["routineIds"] as Array);
        config.remove("routineIds");
        config["routines"] = routines;
        if (!(config["settings"] instanceof Dictionary)) {
            config["settings"] = {"defaultRestSec" => 90, "vibrationEnabled" => true};
        } else {
            var settings = SessionLogic.copyDictionary(config["settings"] as Dictionary);
            if (!Model.inRange(settings["defaultRestSec"], 0, Model.MAX_REST_SEC, false)) {
                settings["defaultRestSec"] = 90;
            }
            if (!(settings["vibrationEnabled"] instanceof Boolean)) {
                settings["vibrationEnabled"] = true;
            }
            config["settings"] = settings;
        }
        if (!(config["incrementOverrides"] instanceof Dictionary)) {
            config["incrementOverrides"] = {};
        }
        if (!(config["routines"] instanceof Array) ||
            !(config["routineSyncSeq"] instanceof Number) ||
            config["routineSyncSeq"] < 0) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        _stored = true;
        return config;
    }

    // Routines listed by the config, each from its own pair. A missing or corrupt routine is
    // dropped and reported as damaged settings, so one bad record cannot block the others.
    private function loadRoutines(ids as Array) as Array {
        var routines = [];
        for (var i = 0; i < ids.size(); i++) {
            var routine = _store.loadPair("routine." + (ids[i] as String));
            if (routine == null || !Model.sameString(routine["id"], ids[i])) {
                _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
                continue;
            }
            routines.add(routine);
        }
        return routines;
    }

    private function routineIdsOf(routines as Array) as Array {
        var ids = [];
        for (var i = 0; i < routines.size(); i++) {
            ids.add((routines[i] as Dictionary)["id"]);
        }
        return ids;
    }

    private function containsId(ids as Array, id as String) as Boolean {
        for (var i = 0; i < ids.size(); i++) {
            if (Model.sameString(ids[i], id)) {
                return true;
            }
        }
        return false;
    }

    // The stored config: everything except the routines, plus their ordered ids.
    private function configOnly(config as Dictionary, ids as Array) as Dictionary {
        var result = SessionLogic.copyDictionary(config);
        result.remove("routines");
        result["routineIds"] = ids;
        result["schemaVersion"] = 4;
        return result;
    }

    // Every routine, then the config; used for the first save of a default config.
    private function writeAll(config as Dictionary) as Boolean {
        var routines = config["routines"] as Array;
        for (var i = 0; i < routines.size(); i++) {
            var routine = routines[i] as Dictionary;
            if (!_store.commitPair("routine." + (routine["id"] as String), routine)) {
                return false;
            }
        }
        if (!_store.commitPair("config", configOnly(config, routineIdsOf(routines)))) {
            return false;
        }
        _stored = true;
        return true;
    }

    // Config settings/session sequence are independent of routine domains. Routine changes use
    // the journaled atomic sync path below.
    private function writeParts(next as Dictionary, routineId as String?, writeConfig as Boolean) as Boolean {
        if (!_stored && !writeAll(next)) {
            _config = null;
            return false;
        }
        if (_stored && writeConfig &&
            !_store.commitPair("config", configOnly(next, routineIdsOf(next["routines"] as Array)))) {
            _config = null;
            return false;
        }
        _config = SessionLogic.copyDictionary(next);
        return true;
    }

    // Config-only save: settings, sequence numbers and overrides.
    private function saveConfig(config as Dictionary) as Boolean {
        return saveParts(config, null, true);
    }

    // routineId names the one routine that changed (or was created or deleted);
    // writeConfig is true when the config itself changed too.
    private function saveParts(config as Dictionary, routineId as String?, writeConfig as Boolean) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        if (!writeParts(config, routineId, writeConfig)) {
            _errorCode = Err.SETTINGS_SAVE_FAILED;
            return false;
        }
        _errorCode = Err.NONE;
        return true;
    }

    public function defaultRestSec() as Number {
        var config = readConfig();
        if (config == null) {
            return 90;
        }
        var settings = (config as Dictionary)["settings"] as Dictionary;
        return settings["defaultRestSec"] as Number;
    }

    public function vibrationEnabled() as Boolean {
        var config = readConfig();
        if (config == null) {
            return true;
        }
        var settings = (config as Dictionary)["settings"] as Dictionary;
        return settings["vibrationEnabled"] as Boolean;
    }

    public function setVibrationEnabled(enabled as Boolean) as Boolean {
        var config = readConfig();
        if (config == null || !configurationEditable()) {
            return false;
        }
        var next = config as Dictionary;
        var settings = SessionLogic.copyDictionary(next["settings"] as Dictionary);
        settings["vibrationEnabled"] = enabled;
        next["settings"] = settings;
        return saveConfig(next);
    }

    public function routineTemplates() as Array {
        var config = readConfig();
        return config == null ? [] : Catalog.routineTemplates(config as Dictionary);
    }

    public function programExercises() as Array {
        var config = readConfig();
        return config == null ? [] : Catalog.allRoutineExercises(config as Dictionary);
    }

    public function nextRoutineId() as String? {
        var config = readConfig();
        return config == null ? null : (config as Dictionary)["nextRoutineId"] as String?;
    }

    public function numericConfigValue(kind as String, parentId as String,
                                       id as String, field as String) as Number? {
        return Model.sameString(kind, "setting") && Model.sameString(field, "defaultRestSec") ?
            defaultRestSec() : null;
    }

    public function updateNumericConfig(kind as String, parentId as String,
                                        id as String, field as String,
                                        value as Number) as Boolean {
        if (!configurationEditable() || !Model.sameString(kind, "setting") ||
            !Model.sameString(field, "defaultRestSec") ||
            !Model.inRange(value, 0, Model.MAX_REST_SEC, false)) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var next = config as Dictionary;
        var settings = SessionLogic.copyDictionary(next["settings"] as Dictionary);
        settings["defaultRestSec"] = value;
        next["settings"] = settings;
        return saveConfig(next);
    }

    public function toggleVibration() as Boolean {
        return setVibrationEnabled(!vibrationEnabled());
    }

    // Thin forwarding for the UI; the work lives in LiftosaurSync.
    public function keyLabel() as String {
        return _sync.keyLabel();
    }

    // Liftosaur upload line for the summary of the session just saved (null: nothing queued).
    public function uploadSummary() as Dictionary? {
        if (_session == null) {
            return null;
        }
        var id = (_session as Dictionary)["id"];
        var state = id instanceof String ? uploadStatuses()[id] : null;
        var uploading = _sync.activityLabel() != null;
        return LiftosaurLogic.summaryUpload(state instanceof String ? state as String : null, uploading,
            _errorCode >= Err.LIFTOSAUR_KEY_REQUIRED ? Err.shortMessage(_errorCode) : null);
    }

    public function uploading() as Boolean {
        return _sync.activityLabel() != null;
    }

    public function hasKey() as Boolean {
        return _sync.hasKey();
    }

    public function saveKey(text as String?) as String? {
        return _sync.saveKey(text);
    }

    public function clearKey() as Boolean {
        return _sync.clearKey();
    }

    public function testKey() as String? {
        return _sync.testKey();
    }

    public function syncRoutines() as Boolean {
        return _sync.syncRoutines();
    }

    public function retryUploads() as Void {
        _sync.retryUploads();
    }

    public function pendingUploadCount() as Number {
        return _sync.pendingUploadCount();
    }

    public function hasStuckUpload() as Boolean {
        return _sync.hasStuckUpload();
    }

    public function uploadQueueDamaged() as Boolean {
        return _sync.uploadQueueDamaged();
    }

    public function skipUpload() as Boolean {
        return _sync.skipUpload();
    }

    public function clearUploadQueue() as Boolean {
        return _sync.clearUploadQueue();
    }

    public function uploadStatuses() as Dictionary {
        return _sync.uploadStatuses();
    }

    public function activityLabel() as String? {
        return _sync.activityLabel();
    }

    public function infoNotice() as String? {
        return _sync.infoNotice();
    }

    // Shared response handler keeps callbacks directly testable without making requests.
    public function handleApiResponse(purpose as String?, uploadId as String?, responseCode as Number,
                                      data as Dictionary or String or PersistedContent.Iterator or Null) as Void {
        _sync.handleApiResponse(purpose, uploadId, responseCode, data);
    }

    // -2: no readable config, -1: error (code set), 0: journal not yet committed, 1: it was
    // already committed and its superseded routine domains are reclaimed.
    public function settleRoutineSync(journal as Dictionary) as Number {
        var config = readConfig();
        if (config == null) {
            return -2;
        }
        if (!SessionLogic.routineSyncAlreadyCommitted(journal["sequence"] as Number,
            (config as Dictionary)["routineSyncSeq"] as Number)) {
            return 0;
        }
        var olderConfig = _store.loadOlderPair("config");
        if (_store.hasUnsupportedRecord() || _store.hasCorruptRecord()) {
            _errorCode = Err.ROUTINE_SYNC_SAVE_FAILED;
            return -1;
        }
        var currentIds = routineIdsOf((config as Dictionary)["routines"] as Array);
        var fallbackIds = olderConfig != null && olderConfig["routineIds"] instanceof Array ?
            olderConfig["routineIds"] as Array : [];
        reclaimPriorRoutineDomains(journal["sequence"] as Number, currentIds, fallbackIds);
        return 1;
    }

    // Ids of the stored routines (empty when the config is unreadable).
    public function routineIds() as Array {
        var config = readConfig();
        return config == null ? [] : routineIdsOf((config as Dictionary)["routines"] as Array);
    }

    public function syncConfig() as Dictionary? {
        return readConfig();
    }

    public function setErrorCode(code as Number) as Void {
        _errorCode = code;
    }

    public function applyRoutineSync(journal as Dictionary) as Boolean {
        var ids = journal["routineIds"] as Array;
        var nextRoutines = [];
        for (var i = 0; i < ids.size(); i++) {
            var routine = _store.loadPair("routine." + (ids[i] as String));
            if (routine == null || _store.hasUnsupportedRecord() || _store.hasCorruptRecord() ||
                !Model.sameString(routine["id"], ids[i])) {
                _errorCode = Err.ROUTINE_SYNC_SAVE_FAILED;
                return false;
            }
            nextRoutines.add(routine);
        }
        var nextId = Catalog.findRoutineId(nextRoutines,
            journal["nextWeek"] as Number, journal["nextDay"] as Number);
        if (nextId == null) {
            _errorCode = Err.ROUTINE_SYNC_INVALID_RESPONSE;
            return false;
        }
        var config = readConfig();
        if (config == null) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return false;
        }
        var priorFallback = _store.loadOlderPair("config");
        if (_store.hasUnsupportedRecord()) {
            _errorCode = Err.ROUTINE_SYNC_SAVE_FAILED;
            return false;
        }
        var oldIds = routineIdsOf((config as Dictionary)["routines"] as Array);
        var fallbackIds = priorFallback != null && priorFallback["routineIds"] instanceof Array ?
            priorFallback["routineIds"] as Array : [];
        var next = SessionLogic.copyDictionary(config as Dictionary);
        next["routines"] = nextRoutines;
        next["routineSyncSeq"] = journal["sequence"];
        next["programId"] = journal["programId"];
        next["programName"] = journal["programName"];
        next["nextRoutineId"] = nextId;
        if (!_store.commitPair("config", configOnly(next, ids))) {
            _errorCode = Err.ROUTINE_SYNC_SAVE_FAILED;
            _config = null;
            return false;
        }
        _stored = true;
        _config = next;
        // Keep domains used by both readable config generations. Older fallback domains are now
        // unreferenced and can be reclaimed after the new pivot is durable.
        for (var i = 0; i < fallbackIds.size(); i++) {
            var old = fallbackIds[i] as String;
            if (!containsId(ids, old) && !containsId(oldIds, old)) {
                _store.deletePair("routine." + old);
            }
        }
        var sequence = journal["sequence"] as Number;
        reclaimPriorRoutineDomains(sequence, ids, oldIds);
        return true;
    }

    private function reclaimPriorRoutineDomains(sequence as Number, currentIds as Array,
                                                fallbackIds as Array) as Void {
        if (sequence <= 2) {
            return;
        }
        for (var ordinal = 1; ordinal <= Model.MAX_TEMPLATES; ordinal++) {
            var stale = Catalog.routineId(sequence - 2, ordinal);
            if (!containsId(currentIds, stale) && !containsId(fallbackIds, stale)) {
                _store.deletePair("routine." + stale);
            }
        }
    }

    public function historySessions() as Array {
        var items = [];
        for (var i = 0; i < 4; i++) {
            var record = _store.loadPair("history" + i.toString());
            if (record != null) {
                items.add(record);
            } else if (_store.hasCorruptRecord() || _store.hasUnsupportedRecord()) {
                items.add({
                    "unavailable" => true,
                    "templateName" => "Workout unavailable",
                    "sessionSeq" => 0 - i,
                    "status" => "unavailable"
                });
            }
        }
        for (var first = 0; first < items.size(); first++) {
            for (var second = first + 1; second < items.size(); second++) {
                var left = items[first]["sessionSeq"] instanceof Number ?
                    items[first]["sessionSeq"] as Number : -1;
                var right = items[second]["sessionSeq"] instanceof Number ?
                    items[second]["sessionSeq"] as Number : -1;
                if (right > left) {
                    var swap = items[first];
                    items[first] = items[second];
                    items[second] = swap;
                }
            }
        }
        return items;
    }

    public function hasActiveSession() as Boolean {
        return _session != null &&
            Model.sameString(_session["status"], "active");
    }

    public function isWorkoutRunning() as Boolean {
        return !_recoveryBlocked && _session != null && Model.sameString(_session["status"], "active");
    }

    public function hasRecoverySaveFailure() as Boolean {
        return _recoveryBlocked;
    }

    public function retryRecovery(now as Number) as Boolean {
        if (!_recoveryBlocked) {
            return false;
        }
        recoverRunningSession(now);
        return !_recoveryBlocked;
    }

    private function persistRecorderState(candidate as Dictionary) as Boolean {
        if (!_store.commitPair("active", candidate)) {
            _pendingRecorderState = candidate;
            _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
            return false;
        }
        _pendingRecorderState = null;
        _session = candidate;
        _errorCode = Err.NONE;
        return true;
    }

    private function persistPendingRecorderState() as Boolean {
        return _pendingRecorderState == null ||
            persistRecorderState(_pendingRecorderState as Dictionary);
    }

    public function ensureRecordingSegment() as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        if (!persistPendingRecorderState()) {
            return false;
        }
        if (_recorder.isRecording()) {
            return true;
        }
        var candidate = SessionLogic.copyDictionary(_session as Dictionary);
        if (_recorder.hasSession()) {
            if (Model.sameString(candidate["fitState"], "paused") ||
                Model.sameString(candidate["fitState"], "recording")) {
                if (!_recorder.resume()) {
                    _errorCode = Err.ACTIVITY_RESUME_FAILED;
                    return false;
                }
                candidate["fitState"] = "recording";
                if (!_store.commitPair("active", candidate)) {
                    _recorder.pause();
                    _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
                    return false;
                }
                _session = candidate;
                _errorCode = Err.NONE;
                return true;
            }
            if (!Model.sameString(candidate["fitState"], "failed") || !saveRecording()) {
                _errorCode = Err.ACTIVITY_SAVE_FAILED;
                return false;
            }
            var savedCount = candidate["fitSegments"] instanceof Number ?
                candidate["fitSegments"] as Number : 0;
            candidate["fitSegments"] = savedCount + 1;
            candidate["fitState"] = "segment_saved";
            if (!persistRecorderState(candidate)) {
                return false;
            }
        }
        candidate = SessionLogic.copyDictionary(_session as Dictionary);
        if (Model.sameString(candidate["fitState"], "recording") ||
            Model.sameString(candidate["fitState"], "paused")) {
            var unknown = candidate["fitUnknownSegments"] instanceof Number ?
                candidate["fitUnknownSegments"] as Number : 0;
            candidate["fitUnknownSegments"] = unknown + 1;
            candidate["fitState"] = "interrupted";
            if (!_store.commitPair("active", candidate)) {
                _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
                return false;
            }
            _session = candidate;
        }
        if (!_recorder.start(candidate["templateName"] as String)) {
            candidate = SessionLogic.copyDictionary(_session as Dictionary);
            candidate["fitState"] = "failed";
            if (!persistRecorderState(candidate)) {
                _errorCode = Err.ACTIVITY_RECORDING_FAILED_TO_START_STATE_SAVE_FAILED;
                return false;
            }
            _errorCode = Err.ACTIVITY_RECORDING_FAILED_TO_START;
            return false;
        }
        candidate = SessionLogic.copyDictionary(_session as Dictionary);
        candidate["fitState"] = "recording";
        if (!_store.commitPair("active", candidate)) {
            if (!_recorder.discard()) {
                _errorCode = Err.ACTIVITY_STATE_SAVE_AND_DISCARD_FAILED;
                return false;
            }
            _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
            return false;
        }
        _session = candidate;
        _errorCode = Err.NONE;
        return true;
    }

    public function saveRecordingSegment() as Boolean {
        if (_pendingRecorderState != null) {
            return persistPendingRecorderState() &&
                Model.sameString((_session as Dictionary)["fitState"], "segment_saved");
        }
        if (!hasActiveSession() || !_recorder.hasSession()) {
            return false;
        }
        var candidate = SessionLogic.copyDictionary(_session as Dictionary);
        var saved = saveRecording();
        if (saved) {
            var count = candidate["fitSegments"] instanceof Number ?
                candidate["fitSegments"] as Number : 0;
            candidate["fitSegments"] = count + 1;
            candidate["fitState"] = "segment_saved";
        } else {
            candidate["fitState"] = "failed";
        }
        if (!_store.commitPair("active", candidate)) {
            if (saved) {
                _pendingRecorderState = candidate;
            }
            _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
            return false;
        }
        _session = candidate;
        _errorCode = Model.sameString(candidate["fitState"], "failed") ?
            Err.ACTIVITY_SAVE_FAILED : Err.NONE;
        return Model.sameString(candidate["fitState"], "segment_saved");
    }

    public function checkpoint(now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var last = _session["lastCheckpointAt"];
        if (last instanceof Number && now >= last && now - last < 30) {
            return true;
        }
        var candidate = WorkoutClock.checkpoint(_session as Dictionary, now);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function startTimed(entryId as String, slot as Number, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.startTimed(_session as Dictionary, entryId, slot, now);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function pauseTimed(entryId as String, slot as Number, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.pauseTimed(_session as Dictionary, entryId, slot, now);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function pauseTimedForEntry(entryId as String, now as Number) as Boolean {
        if (!isWorkoutRunning() || !(_session["timedRun"] instanceof Dictionary)) {
            return false;
        }
        var run = _session["timedRun"] as Dictionary;
        return Model.sameString(run["entryId"], entryId) &&
            pauseTimed(entryId, run["slot"] as Number, now);
    }

    public function cancelTimed(entryId as String, slot as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.cancelTimed(_session as Dictionary, entryId, slot);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function completeTimed(entryId as String, slot as Number, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.completeTimed(_session as Dictionary, entryId, slot, now);
        if (candidate == null || !commit(candidate as Dictionary)) {
            return false;
        }
        recordSetLap(entryId, slot);
        return true;
    }

    public function timedElapsed(now as Number) as Number {
        if (_session != null && _session["timedRun"] instanceof Dictionary) {
            return SessionLogic.timedElapsedSec(_session["timedRun"] as Dictionary, now);
        }
        return 0;
    }

    public function hasPendingFinalization() as Boolean {
        return _session != null && Model.sameString(_session["status"], "finalizing");
    }

    public function retryFinalization() as Boolean {
        if (!hasPendingFinalization()) {
            return false;
        }
        _errorCode = Err.NONE;
        return true;
    }

    public function hasRunningRest() as Boolean {
        return isWorkoutRunning() && _session["rest"] instanceof Dictionary &&
            Model.sameString(_session["rest"]["state"], "running");
    }

    // A running or overtime (expired, waiting for the next set) rest is on screen.
    public function hasRestShown() as Boolean {
        return isWorkoutRunning() && _session["rest"] instanceof Dictionary &&
            (Model.sameString(_session["rest"]["state"], "running") ||
             Model.sameString(_session["rest"]["state"], "expired"));
    }

    public function hasRunningTimed() as Boolean {
        return isWorkoutRunning() && _session["timedRun"] instanceof Dictionary;
    }

    public function onTick(now as Number, canVibrate as Boolean) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        _recorder.flush();
        var candidate = null;
        var restAlert = false;
        var timedAlert = false;
        if (_session["rest"] instanceof Dictionary) {
            var rest = RestClock.expire(_session["rest"] as Dictionary, now);
            if (rest != null) {
                candidate = SessionLogic.copyDictionary(_session as Dictionary);
                candidate["rest"] = rest;
                restAlert = true;
            }
        }
        var run = _session["timedRun"];
        if (run instanceof Dictionary && run["targetAlertConsumed"] != true) {
            var index = SessionLogic.exerciseIndex(_session as Dictionary, run["entryId"] as String);
            if (index >= 0) {
                var exercise = (_session["exercises"] as Array)[index] as Dictionary;
                var target = exercise["targetDurationSec"];
                var plans = exercise["planTargets"];
                var runSlot = run["slot"] instanceof Number ?
                    Model.slotAt(exercise, run["slot"] as Number) : null;
                if (runSlot != null && (run["slot"] as Number) >= Model.WARMUP_BASE) {
                    target = ((runSlot as Dictionary)["draft"] as Dictionary)["durationSec"];
                } else if (plans instanceof Array && run["slot"] instanceof Number &&
                    (run["slot"] as Number) < (plans as Array).size()) {
                    target = (plans as Array)[run["slot"] as Number]["durationSec"];
                }
                if (target instanceof Number &&
                    SessionLogic.timedElapsedSec(run as Dictionary, now) >= (target as Number)) {
                    if (candidate == null) {
                        candidate = SessionLogic.copyDictionary(_session as Dictionary);
                    }
                    var nextRun = SessionLogic.copyDictionary(run as Dictionary);
                    nextRun["targetAlertConsumed"] = true;
                    candidate["timedRun"] = nextRun;
                    timedAlert = true;
                }
            }
        }
        if (candidate != null) {
            return commit(candidate as Dictionary) && (restAlert || (timedAlert && canVibrate));
        }
        checkpoint(now);
        return false;
    }

    // True once per rest (in memory only, no write) when the 10 s warning is due and the caller
    // may vibrate; a due warning is still consumed silently when it may not (app just resumed).
    public function takePreRestAlert(now as Number, canVibrate as Boolean) as Boolean {
        if (!isWorkoutRunning() || !(_session["rest"] instanceof Dictionary)) {
            return false;
        }
        var rest = _session["rest"] as Dictionary;
        if (rest["id"] == _preAlertRestId || !RestClock.preAlertDue(rest, now)) {
            return false;
        }
        _preAlertRestId = rest["id"] as Number;
        return canVibrate;
    }

    // Persists a weight step for the exercise name (survives re-sync) and applies it to this
    // workout's exercise. Config is written directly: the editable-configuration gate is closed
    // during a workout.
    public function setWeightStep(entryId as String, increment100 as Number) as Boolean {
        if (!isWorkoutRunning() || !Model.inRange(increment100, 25, 10000, false) ||
            increment100 % 25 != 0) {
            return false;
        }
        var index = SessionLogic.exerciseIndex(_session as Dictionary, entryId);
        var config = readConfig();
        if (index < 0 || config == null) {
            return false;
        }
        var exercise = ((_session as Dictionary)["exercises"] as Array)[index] as Dictionary;
        if (!Model.sameString(exercise["loadType"], "weight")) {
            return false;
        }
        var overrides = SessionLogic.copyDictionary(
            (config as Dictionary)["incrementOverrides"] as Dictionary);
        if (!overrides.hasKey(exercise["name"]) && overrides.size() >= 32) {
            return false;
        }
        overrides[exercise["name"]] = increment100;
        var next = SessionLogic.copyDictionary(config as Dictionary);
        next["incrementOverrides"] = overrides;
        if (!writeParts(next, null, true)) {
            return false;
        }
        var state = SessionLogic.exerciseCandidate(_session as Dictionary, index);
        var changed = state["exercise"] as Dictionary;
        changed["weightIncrement100"] = increment100;
        return commit(state["session"] as Dictionary);
    }

    public function restAction(action as String, now as Number) as Boolean {
        if (!isWorkoutRunning() || !(_session["rest"] instanceof Dictionary)) {
            return false;
        }
        var current = _session["rest"] as Dictionary;
        if (!Model.sameString(current["state"], "running")) {
            return false;
        }
        var next = null;
        if (Model.sameString(action, "skip")) {
            next = RestClock.skip(current);
        } else if (Model.sameString(action, "add")) {
            next = RestClock.adjust(current, now, 30);
        } else if (Model.sameString(action, "remove")) {
            next = RestClock.adjust(current, now, -30);
        }
        if (next == null) {
            return false;
        }
        var candidate = SessionLogic.copyDictionary(_session as Dictionary);
        candidate["rest"] = next;
        candidate["restGeneration"] = next["id"];
        return commit(candidate as Dictionary);
    }

    // Saves the recording with the FIT session summary of the current session.
    private function saveRecording() as Boolean {
        return _recorder.save(_session == null ? null : SessionLogic.fitSummary(_session as Dictionary));
    }

    // One FIT lap per logged set while recording; never affects the logged set.
    private function recordSetLap(entryId as String, slot as Number) as Void {
        var payload = lapFor(entryId, slot);
        if (payload != null) {
            _recorder.recordSet(payload);
        }
    }

    private function lapFor(entryId as String, slot as Number) as Dictionary? {
        if (_session == null || !_recorder.isRecording()) {
            return null;
        }
        var index = SessionLogic.exerciseIndex(_session as Dictionary, entryId);
        return index < 0 ? null : SessionLogic.lapPayload(
            (_session["exercises"] as Array)[index] as Dictionary, slot);
    }

    private function commit(candidate as Dictionary) as Boolean {
        if (candidate["lastCheckpointAt"] instanceof Number) {
            candidate["lastCheckpointAt"] = Time.now().value();
        }
        var started = System.getTimer();
        var stored = _store.commitPair("active", candidate);
        var took = System.getTimer() - started;
        if (took > _maxCommitMs) {
            _maxCommitMs = took;
        }
        if (!stored) {
            _errorCode = Err.SAVE_FAILED_RETRY_BEFORE_CONTINUING;
            return false;
        }
        _draftDirty = false;
        _session = candidate;
        _errorCode = Err.NONE;
        return true;
    }

    private function recoverRunningSession(now as Number) as Void {
        var source = _session as Dictionary;
        var candidate = SessionLogic.copyDictionary(source);
        var run = candidate["timedRun"];
        if (run instanceof Dictionary) {
            var savedAt = candidate["lastCheckpointAt"] instanceof Number ?
                candidate["lastCheckpointAt"] as Number :
                (run["startedAt"] instanceof Number ? run["startedAt"] as Number :
                    source["startedAt"] as Number);
            var pausedTimed = SessionLogic.pauseTimed(candidate, run["entryId"] as String,
                run["slot"] as Number, savedAt);
            if (pausedTimed == null) {
                _errorCode = Err.TIMED_SET_RECOVERY_FAILED;
                _recoveryBlocked = true;
                return;
            }
            candidate = pausedTimed as Dictionary;
        }
        var recovered = WorkoutClock.recover(candidate, now);
        if (!_store.commitPair("active", recovered)) {
            _errorCode = Err.RECOVERY_SAVE_FAILED;
            _recoveryBlocked = true;
            return;
        }
        _session = recovered;
        _recoveryBlocked = false;
    }

    private function historySlot(ended as Dictionary) as Number {
        _historyAlreadyWritten = false;
        var empty = -1;
        var oldest = -1;
        var oldestSequence = 2147483647;
        for (var i = 0; i < 4; i++) {
            var record = _store.peekSession("history" + i.toString());
            if (_store.hasUnsupportedRecord()) {
                continue;
            }
            if (record == null) {
                if (empty < 0) {
                    empty = i;
                }
                continue;
            }
            if (Model.sameString(record["id"], ended["id"])) {
                _historyAlreadyWritten = true;
                return i;
            }
            var sequence = record["sessionSeq"];
            if (sequence instanceof Number && sequence < oldestSequence) {
                oldest = i;
                oldestSequence = sequence;
            }
        }
        return empty >= 0 ? empty : oldest;
    }

    private function readLastCache() as Dictionary? {
        var cache = _store.loadPair("last");
        if (_store.hasUnsupportedRecord() || cache != null) {
            return cache;
        }
        var rebuilt = {};
        for (var i = 0; i < 4; i++) {
            var ended = _store.loadPair("history" + i.toString());
            if (ended != null && Model.sameString(ended["status"], "completed")) {
                rebuilt = LastPerformance.merge(rebuilt, ended);
            }
        }
        return rebuilt;
    }

    public function advanceFinalization() as Boolean {
        if (!hasPendingFinalization()) {
            return false;
        }
        _errorCode = Err.NONE;
        var frozen = _session as Dictionary;
        var outcome = frozen["finishOutcome"];
        if (!(Model.sameString(outcome, "completed") || Model.sameString(outcome, "aborted"))) {
            _errorCode = Err.SAVED_WORKOUT_IS_DAMAGED;
            return false;
        }
        if (Model.sameString(outcome, "completed")) {
            var recording = SessionLogic.copyDictionary(frozen);
            var state = recording["fitState"];
            if (Model.sameString(state, "saving") || Model.sameString(state, "segment_saved")) {
                if (Model.sameString(state, "segment_saved")) {
                    recording["fitState"] = "saved";
                } else if (_fitSavedInMemory) {
                    recording["fitState"] = "saved";
                } else if (_recorder.hasSession()) {
                    if (saveRecording()) {
                        var count = recording["fitSegments"] instanceof Number ?
                            recording["fitSegments"] as Number : 0;
                        recording["fitSegments"] = count + 1;
                        recording["fitState"] = "saved";
                        _fitSavedInMemory = true;
                    } else {
                        recording["fitState"] = "failed";
                    }
                } else {
                    // The process restarted during save; the SDK has no way to
                    // query whether this segment reached the FIT file system.
                    recording["fitState"] = "unknown";
                }
                if (!_store.commitPair("active", recording)) {
                    _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
                    return false;
                }
                _session = recording;
                _errorCode = Err.NONE;
                return false;
            }
        }
        if (Model.sameString(outcome, "aborted") &&
            Model.sameString(frozen["fitState"], "discarding")) {
            var discarding = SessionLogic.copyDictionary(frozen);
            // No recorder session in memory means the process restarted after the
            // discard commit began; a restart drops the in-memory session, so treat
            // it as discarded (there is nothing left to discard). The result goes straight
            // into the tombstone below; a crash before it resumes here and discards nothing.
            discarding["fitState"] = !_recorder.hasSession() || _recorder.discard() ?
                "discarded" : "discard_failed";
            frozen = discarding;
        }
        var ended = SessionLogic.copyDictionary(frozen);
        ended["status"] = outcome;
        // A cancelled workout is discarded, not archived: no history, no last-performance update.
        if (Model.sameString(outcome, "completed") && !_historySaved) {
            var target = historySlot(ended);
            if (target < 0) {
                _errorCode = Err.HISTORY_NEEDS_NEWER_APP;
                return false;
            }
            if (!_historyAlreadyWritten &&
                !_store.commitPair("history" + target.toString(), SessionLogic.archivedSession(ended))) {
                _errorCode = Err.HISTORY_SAVE_FAILED;
                return false;
            }
            _historySaved = true;
            _errorCode = Err.NONE;
            return false;
        }

        if (Model.sameString(outcome, "completed") && !_cacheSaved) {
            var cache = readLastCache();
            if (!_store.hasUnsupportedRecord()) {
                var nextCache = LastPerformance.merge(cache, SessionLogic.archivedSession(ended));
                if (!_store.commitPair("last", nextCache)) {
                    _errorCode = Err.PREVIOUS_PERFORMANCE_SAVE_FAILED;
                    return false;
                }
            }
            _cacheSaved = true;
            _errorCode = Err.NONE;
            return false;
        }

        if (Model.sameString(outcome, "completed") && !_sync.enqueueFinalWorkout(ended)) {
            return false;
        }

        var tombstone = {
            "id" => frozen["id"],
            "sessionSeq" => frozen["sessionSeq"],
            "status" => outcome,
            "endedAt" => frozen["endedAt"]
        };
        if (!_store.commitPair("active", tombstone)) {
            _errorCode = Err.WORKOUT_ARCHIVE_SAVED_RETRY_FINISH;
            return false;
        }
        _session = ended;
        if (Model.sameString(ended["fitState"], "failed")) {
            _errorCode = Err.ACTIVITY_SAVE_FAILED;
        } else if (Model.sameString(ended["fitState"], "unknown")) {
            _errorCode = Err.ACTIVITY_RESULT_UNKNOWN;
        } else if (Model.sameString(ended["fitState"], "discard_failed")) {
            _errorCode = Err.ACTIVITY_DISCARD_FAILED;
        } else {
            _errorCode = Err.NONE;
        }
        return true;
    }

    public function prepareWorkoutStart(templateId as String, now as Number) as Boolean {
        if (_pendingStartConfig != null || _pendingStartSession != null) {
            _errorCode = Err.WORKOUT_IS_ALREADY_STARTING;
            return false;
        }
        if (hasActiveSession() || hasPendingFinalization() || _activeUnsupported || _activeCorrupt) {
            _errorCode = _activeUnsupported ? Err.UPDATE_APP_TO_RESUME :
                (_activeCorrupt ? Err.SAVED_WORKOUT_IS_DAMAGED : Err.WORKOUT_CANNOT_START);
            return false;
        }
        // A damaged queue must not brick workouts; it is reset when the workout is finalized.
        var queued = _store.loadUploadQueue();
        if (queued != null && queued.size() >= QueueLimits.MAX_PENDING_UPLOADS) {
            _errorCode = Err.UPLOAD_QUEUE_FULL;
            return false;
        }
        _errorCode = queued == null ? Err.UPLOAD_QUEUE_DAMAGED : Err.NONE;
        _sync.clearNotice();
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var sequence = (config as Dictionary)["nextSessionSeq"] as Number;
        var routine = Catalog.routineTemplate(config as Dictionary, templateId);
        if (routine == null) {
            _errorCode = Err.ROUTINE_NOT_FOUND;
            return false;
        }
        if (((routine as Dictionary)["entries"] as Array).size() == 0) {
            _errorCode = Err.ROUTINE_HAS_NO_EXERCISES;
            return false;
        }
        var sessionId = "session-" + sequence.toString();
        var cache = readLastCache();
        var candidate = Catalog.createSession(templateId, sessionId, sequence, now, cache,
            config as Dictionary);
        if (candidate == null) {
            _errorCode = Err.WORKOUT_COULD_NOT_BE_CREATED;
            return false;
        }
        _pendingStartConfig = config as Dictionary;
        _pendingStartSession = candidate as Dictionary;
        _startSequenceReserved = false;
        return true;
    }

    public function reserveWorkoutStart() as Boolean {
        if (_pendingStartConfig == null || _pendingStartSession == null ||
            _startSequenceReserved) {
            _errorCode = Err.WORKOUT_COULD_NOT_BE_CREATED;
            cancelWorkoutStart();
            return false;
        }
        // Re-read the config: a routine sync may have replaced it since prepareWorkoutStart.
        var config = readConfig();
        var sequence = config == null ? 0 : (config as Dictionary)["nextSessionSeq"] as Number;
        if (config == null ||
            sequence != (_pendingStartSession as Dictionary)["sessionSeq"]) {
            _errorCode = Err.COULD_NOT_RESERVE_WORKOUT_ID;
            cancelWorkoutStart();
            return false;
        }
        var nextConfig = SessionLogic.copyDictionary(config as Dictionary);
        nextConfig["nextSessionSeq"] = sequence + 1;
        if (!writeParts(nextConfig, null, true)) {
            _errorCode = Err.COULD_NOT_RESERVE_WORKOUT_ID;
            cancelWorkoutStart();
            return false;
        }
        _pendingStartConfig = null;
        _startSequenceReserved = true;
        _errorCode = Err.NONE;
        return true;
    }

    public function commitWorkoutStart(now as Number) as Boolean {
        if (_pendingStartSession == null || !_startSequenceReserved) {
            _errorCode = Err.WORKOUT_COULD_NOT_BE_CREATED;
            cancelWorkoutStart();
            return false;
        }
        var fresh = _pendingStartSession as Dictionary;
        fresh["startedAt"] = now;
        var clock = WorkoutClock.start(now);
        var clockKeys = clock.keys();
        for (var i = 0; i < clockKeys.size(); i++) {
            fresh[clockKeys[i]] = clock[clockKeys[i]];
        }
        fresh["timedRun"] = null;
        fresh["fitState"] = "recording";
        fresh["fitSegments"] = 0;
        fresh["fitUnknownSegments"] = 0;
        _fitSavedInMemory = false;
        _historySaved = false;
        _cacheSaved = false;
        _pendingHistory = null;
        _pendingRecorderState = null;
        if (!_recorder.start(fresh["templateName"] as String)) {
            _errorCode = Err.ACTIVITY_RECORDING_FAILED_TO_START;
            cancelWorkoutStart();
            return false;
        }
        if (!commit(fresh)) {
            if (!_recorder.discard()) {
                _errorCode = Err.ACTIVITY_DISCARD_FAILED;
            }
            cancelWorkoutStart();
            return false;
        }
        cancelWorkoutStart();
        return true;
    }

    public function cancelWorkoutStart() as Void {
        _pendingStartConfig = null;
        _pendingStartSession = null;
        _startSequenceReserved = false;
    }

    public function addSet(entryId as String) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.addSet(_session as Dictionary, entryId);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function updateDraft(entryId as String, slot as Number, field as String, value as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.updateDraft(_session as Dictionary, entryId, slot, field, value);
        if (candidate == null) {
            return false;
        }
        // UP/DOWN edits stay in memory; any later commit includes them, else the timer saves them.
        _session = candidate;
        _draftDirty = true;
        _draftTimer.stop();
        _draftTimer.start(method(:flushDraft), 2000, false);
        return true;
    }

    // Timer target and app-stop hook: persists pending draft edits once.
    public function flushDraft() as Void {
        _draftTimer.stop();
        if (_draftDirty && isWorkoutRunning()) {
            commit(_session as Dictionary);
        }
    }

    public function hasPendingDraft() as Boolean {
        return _draftDirty;
    }

    public function noteSyncMs(ms as Number) as Void {
        _syncMs = ms;
    }

    public function setNotice(text as String) as Void {
        _sync.setNotice(text);
    }

    // Settings → Diagnostics text.
    public function diagnostics() as String {
        return "Max commit " + _maxCommitMs.toString() + " ms · Last sync parse " +
            (_syncMs < 0 ? "n/a" : _syncMs.toString() + " ms") + " · Free " +
            (System.getSystemStats().freeMemory / 1024).toString() + " KB";
    }

    public function completeDraft(entryId as String, slot as Number, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var session = _session as Dictionary;
        var index = SessionLogic.exerciseIndex(session, entryId);
        if (index < 0) {
            return false;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var found = Model.slotAt(exercise, slot);
        if (found == null) {
            return false;
        }
        var draft = (found as Dictionary)["draft"] as Dictionary;
        if (Model.sameString(exercise["loadType"], "timed")) {
            var run = session["timedRun"];
            if (run instanceof Dictionary && Model.sameString(run["entryId"], entryId) &&
                run["slot"] == slot) {
                return completeTimed(entryId, slot, now);
            }
            if (draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
                return completeTimed(entryId, slot, now);
            }
        }
        var candidate = SessionLogic.completeSet(session, entryId, slot, draft, now);
        if (candidate == null || !commit(candidate as Dictionary)) {
            return false;
        }
        recordSetLap(entryId, slot);
        return true;
    }

    public function correctSet(entryId as String, slot as Number, actual as Dictionary, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.correctSet(_session as Dictionary, entryId, slot, actual, now);
        if (candidate == null || !commit(candidate as Dictionary)) {
            return false;
        }
        recordSetLap(entryId, slot);  // corrected values; the NAS keeps the last lap per set
        return true;
    }

    public function undoSet(entryId as String, slot as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.undoSet(_session as Dictionary, entryId, slot);
        if (candidate == null) {
            return false;
        }
        var retract = lapFor(entryId, slot);  // read before the set is cleared
        if (!commit(candidate as Dictionary)) {
            return false;
        }
        if (retract != null) {
            (retract as Dictionary)["void"] = 1;
            _recorder.recordSet(retract);
        }
        return true;
    }

    public function skipWarmups(entryId as String) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.skipWarmups(_session as Dictionary, entryId);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function closeExercise(entryId as String, closed as Boolean) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.closeExercise(_session as Dictionary, entryId, closed);
        return candidate != null && commit(candidate as Dictionary);
    }

    private function sessionAlternativeSnapshot(source as Dictionary,
                                                previousExercise as Dictionary,
                                                entryId as String,
                                                definition as Dictionary,
                                                loadType as String,
                                                setCount as Number) as Dictionary? {
        var sourceTargets = definition["setTargets"];
        if (!(sourceTargets instanceof Array) || (sourceTargets as Array).size() == 0 ||
            !Model.validLoadType(loadType)) {
            _errorCode = Err.EXERCISE_CHOICE_INVALID;
            return null;
        }
        var targets = [];
        for (var i = 0; i < setCount; i++) {
            var target = (sourceTargets as Array)[i < (sourceTargets as Array).size() ?
                i : (sourceTargets as Array).size() - 1] as Dictionary;
            targets.add(SessionLogic.copyDictionary(target));
        }
        var entry = SessionLogic.copyDictionary(definition);
        entry["entryId"] = entryId;
        entry["exerciseId"] = definition["id"];
        entry["liftosaurEntryId"] = null;
        entry["workingSetCount"] = setCount;
        entry["setTargets"] = targets;
        var routine = {
            "id" => source["templateId"], "name" => source["templateName"],
            "revision" => source["templateRevision"], "programId" => source["programId"],
            "week" => source["week"], "dayInWeek" => source["dayInWeek"],
            "entries" => [entry]
        };
        var config = readConfig();
        if (config == null) {
            return null;
        }
        var sessionConfig = SessionLogic.copyDictionary(config as Dictionary);
        sessionConfig["routines"] = [routine];
        var generated = Catalog.createSession(source["templateId"] as String,
            source["id"] as String, source["sessionSeq"] as Number,
            source["startedAt"] as Number, readLastCache(), sessionConfig);
        if (generated == null) {
            _errorCode = Err.EXERCISE_CHOICE_INVALID;
            return null;
        }
        var alternative = SessionLogic.copyDictionary(
            (generated as Dictionary)["exercises"][0] as Dictionary);
        alternative["liftosaurEntryId"] = null;
        alternative["liftosaurPlannedSetCount"] = null;
        return alternative;
    }

    private function substitutionSnapshot(source as Dictionary, from as String,
                                          to as String) as Array? {
        var existing = source["substitutions"];
        var changes = existing instanceof Array ? (existing as Array).slice(0, null) : [];
        for (var i = 0; i < changes.size(); i++) {
            var change = changes[i] as Dictionary;
            if (Model.sameString(change["from"], from) && Model.sameString(change["to"], to)) {
                return changes;
            }
        }
        if (changes.size() >= Model.MAX_ENTRIES) {
            return null;
        }
        changes.add({"from" => from, "to" => to});
        return changes;
    }

    public function replaceSessionExercise(entryId as String,
                                           definition as Dictionary,
                                           loadType as String) as Boolean {
        if (!isWorkoutRunning() || !(definition["id"] instanceof String) ||
            !Model.validLoadType(loadType)) {
            return false;
        }
        var source = _session as Dictionary;
        var index = SessionLogic.exerciseIndex(source, entryId);
        var exercises = source["exercises"] as Array;
        if (index < 0 || SessionLogic.completedCount(exercises[index] as Dictionary) > 0 ||
            source["timedRun"] instanceof Dictionary) {
            _errorCode = Err.FINISH_OR_PAUSE_THE_CURRENT_SET_FIRST;
            return false;
        }
        var old = exercises[index] as Dictionary;
        var substitutions = substitutionSnapshot(source, old["name"] as String,
            definition["name"] as String);
        if (substitutions == null) {
            _errorCode = Err.EXERCISE_CHOICE_INVALID;
            return false;
        }
        var replacement = sessionAlternativeSnapshot(source, old, entryId, definition,
            loadType, old["plannedSetCount"] as Number);
        if (replacement == null) {
            return false;
        }
        var candidate = SessionLogic.copyDictionary(source);
        var nextExercises = [];
        for (var i = 0; i < exercises.size(); i++) {
            nextExercises.add(i == index ? replacement : exercises[i]);
        }
        candidate["exercises"] = nextExercises;
        candidate["substitutions"] = substitutions;
        var rest = candidate["rest"];
        if (rest instanceof Dictionary && Model.sameString(rest["entryId"], entryId)) {
            candidate["rest"] = null;
        }
        candidate["nextSetSequence"] = (candidate["nextSetSequence"] as Number) + 1;
        return commit(candidate);
    }

    public function addSessionAlternative(entryId as String,
                                          definition as Dictionary,
                                          loadType as String) as Boolean {
        if (!isWorkoutRunning() || !(definition["id"] instanceof String) ||
            !Model.validLoadType(loadType)) {
            return false;
        }
        var source = _session as Dictionary;
        var index = SessionLogic.exerciseIndex(source, entryId);
        var oldExercises = source["exercises"] as Array;
        if (index < 0 || source["timedRun"] instanceof Dictionary) {
            _errorCode = Err.FINISH_OR_PAUSE_THE_CURRENT_SET_FIRST;
            return false;
        }
        var old = oldExercises[index] as Dictionary;
        var completed = SessionLogic.completedCount(old);
        var remaining = (old["plannedSetCount"] as Number) - completed;
        if (completed == 0 || remaining < 1 || oldExercises.size() >= Model.MAX_ENTRIES) {
            _errorCode = Err.ROUTINE_LIMIT_REACHED;
            return false;
        }
        var substitutions = substitutionSnapshot(source, old["name"] as String,
            definition["name"] as String);
        if (substitutions == null) {
            _errorCode = Err.EXERCISE_CHOICE_INVALID;
            return false;
        }
        var seq = 1;
        var entryIdNew = "alt-" + source["sessionSeq"].toString() + "-" + seq.toString();
        while (SessionLogic.exerciseIndex(source, entryIdNew) >= 0) {
            seq++;
            entryIdNew = "alt-" + source["sessionSeq"].toString() + "-" + seq.toString();
        }
        var alternative = sessionAlternativeSnapshot(source, old, entryIdNew,
            definition, loadType, remaining);
        if (alternative == null) {
            return false;
        }
        var closed = SessionLogic.copyDictionary(old);
        closed["closedEarly"] = true;
        var nextExercises = [];
        for (var i = 0; i < oldExercises.size(); i++) {
            nextExercises.add(i == index ? closed : oldExercises[i]);
            if (i == index) {
                nextExercises.add(alternative);
            }
        }
        var candidate = SessionLogic.copyDictionary(source);
        candidate["exercises"] = nextExercises;
        candidate["substitutions"] = substitutions;
        var rest = candidate["rest"];
        if (rest instanceof Dictionary && Model.sameString(rest["entryId"], entryId)) {
            candidate["rest"] = null;
        }
        candidate["nextSetSequence"] = (candidate["nextSetSequence"] as Number) + 1;
        if (SessionLogic.totals(candidate)["planned"] > Model.MAX_SETS_PER_WORKOUT) {
            _errorCode = Err.ROUTINE_LIMIT_REACHED;
            return false;
        }
        return commit(candidate);
    }

    public function finish(outcome as String, now as Number) as Boolean {
        if (hasPendingFinalization()) {
            _errorCode = Err.WORKOUT_IS_ALREADY_FINISHING;
            return false;
        }
        if (!hasActiveSession() ||
            (!Model.sameString(outcome, "completed") && !Model.sameString(outcome, "aborted"))) {
            return false;
        }
        if (!persistPendingRecorderState()) {
            return false;
        }
        var candidate = SessionLogic.copyDictionary(_session as Dictionary);
        var run = candidate["timedRun"];
        if (run instanceof Dictionary) {
            var pausedTimed = SessionLogic.pauseTimed(candidate, run["entryId"] as String,
                run["slot"] as Number, now);
            if (pausedTimed == null) {
                return false;
            }
            candidate = pausedTimed as Dictionary;
        }
        var totals = SessionLogic.totals(candidate);
        if (Model.sameString(outcome, "completed") && totals["done"] == 0) {
            _errorCode = Err.LOG_A_SET_BEFORE_SAVING;
            return false;
        }
        candidate["status"] = "finalizing";
        candidate["finishOutcome"] = outcome;
        var skipped = false;
        var exercises = candidate["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (exercise["closedEarly"] == true &&
                SessionLogic.completedCount(exercise) < exercise["plannedSetCount"]) {
                skipped = true;
                break;
            }
        }
        candidate["completionKind"] = Model.sameString(outcome, "aborted") ? null :
            (totals["done"] == totals["planned"] && !skipped ? "full" : "partial");
        candidate["endedAt"] = now;
        candidate["elapsedSec"] = WorkoutClock.elapsed(candidate, now);
        candidate["activeSec"] = WorkoutClock.active(candidate, now);
        candidate["rest"] = null;
        if (Model.sameString(outcome, "completed")) {
            candidate["fitState"] = _recorder.hasSession() ? "saving" :
                (candidate["fitSegments"] instanceof Number && candidate["fitSegments"] > 0 ?
                    "segment_saved" : "unknown");
        } else if (_recorder.hasSession()) {
            // The recorder is discarded in advanceFinalization, after this commit is durable.
            candidate["fitState"] = "discarding";
        }
        if (!commit(candidate)) {
            return false;
        }
        _historySaved = false;
        _cacheSaved = false;
        _historyAlreadyWritten = false;
        return true;
    }

    public function canRetryActivitySave() as Boolean {
        return _pendingHistory != null || (_session != null &&
            Model.sameString(_session["status"], "completed") &&
            Model.sameString(_session["fitState"], "failed") && _recorder.hasSession());
    }

    public function retryActivitySave() as Boolean {
        if (!canRetryActivitySave()) {
            return false;
        }
        if (_pendingHistory != null) {
            var target = historySlot(_pendingHistory as Dictionary);
            if (target < 0 || !_store.commitPair("history" + target.toString(),
                SessionLogic.archivedSession(_pendingHistory as Dictionary))) {
                _errorCode = Err.ACTIVITY_SAVED_HISTORY_UPDATE_FAILED;
                return false;
            }
            _session = _pendingHistory;
            _pendingHistory = null;
            _errorCode = Err.NONE;
            return true;
        }
        if (!saveRecording()) {
            _errorCode = Err.ACTIVITY_SAVE_FAILED;
            return false;
        }
        var ended = SessionLogic.copyDictionary(_session as Dictionary);
        var count = ended["fitSegments"] instanceof Number ? ended["fitSegments"] as Number : 0;
        ended["fitSegments"] = count + 1;
        ended["fitState"] = "saved";
        var target = historySlot(ended);
        if (target < 0 || !_store.commitPair("history" + target.toString(),
            SessionLogic.archivedSession(ended))) {
            _pendingHistory = ended;
            _fitSavedInMemory = true;
            _errorCode = Err.ACTIVITY_SAVED_HISTORY_UPDATE_FAILED;
            return false;
        }
        _fitSavedInMemory = true;
        _session = ended;
        _errorCode = Err.NONE;
        return true;
    }

    public function keepLocalLogAndCloseActivity() as Boolean {
        if (_session == null || !Model.sameString(_session["status"], "completed") ||
            (!Model.sameString(_session["fitState"], "failed") &&
             !Model.sameString(_session["fitState"], "unknown"))) {
            return false;
        }
        if (_recorder.hasSession() && !_recorder.discard()) {
            _errorCode = Err.ACTIVITY_DISCARD_FAILED;
            return false;
        }
        return true;
    }
}
