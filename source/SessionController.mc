import Toybox.Lang;
import Toybox.Time;

class SessionController {
    private var _store as Store;
    private var _session as Dictionary? = null;
    private var _error as String? = null;
    private var _recoveryBlocked as Boolean = false;
    private var _activeUnsupported as Boolean = false;
    private var _activeCorrupt as Boolean = false;

    public function initialize(store as Store) {
        _store = store;
        _session = _store.loadPair("active");
        _activeUnsupported = _store.hasUnsupportedRecord();
        _activeCorrupt = _session == null && _store.hasCorruptRecord();
        if (_session != null &&
            (Model.sameString(_session["status"], "completed") ||
             Model.sameString(_session["status"], "aborted"))) {
            _session = null;
        }
        if (_store.hasUnsupportedRecord()) {
            _error = "Update app to resume";
        } else if (_store.hasCorruptRecord() && _session == null) {
            _error = "Saved workout is damaged";
        } else if (_store.recoveredEarlierGeneration()) {
            _error = "Recovered earlier checkpoint";
        }
        if (_session != null && Model.sameString(_session["status"], "finalizing")) {
            finalizePending();
        } else if (isWorkoutRunning()) {
            recoverRunningSession(Time.now().value());
        }
    }

    public function session() as Dictionary? {
        return _session;
    }

    public function errorMessage() as String? {
        return _error;
    }

    public function configurationEditable() as Boolean {
        return !hasActiveSession() && !hasPendingFinalization() &&
            !_activeUnsupported && !_activeCorrupt;
    }

    private function defaultConfig() as Dictionary {
        var settings = {
            "defaultRestSec" => 90,
            "vibrationEnabled" => true
        };
        return {
            "schemaVersion" => 1,
            "nextSessionSeq" => 1,
            "settings" => settings,
            "templateOverrides" => {},
            "incrementOverrides" => {}
        };
    }

    private function readConfig() as Dictionary? {
        var stored = _store.loadPair("config");
        if (_store.hasUnsupportedRecord() || (_store.hasCorruptRecord() && stored == null)) {
            _error = "Saved settings are damaged";
            return null;
        }
        if (stored == null) {
            return defaultConfig();
        }
        var config = SessionLogic.copyDictionary(stored as Dictionary);
        if (!(config["nextSessionSeq"] instanceof Number) || config["nextSessionSeq"] < 1) {
            _error = "Saved settings are damaged";
            return null;
        }
        var schemaVersion = config["schemaVersion"];
        if (schemaVersion instanceof Number && schemaVersion > 1) {
            _error = "Update app to resume";
            return null;
        }
        if (schemaVersion != null && (!(schemaVersion instanceof Number) || schemaVersion < 1)) {
            _error = "Saved settings are damaged";
            return null;
        }
        config["schemaVersion"] = 1;
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
        if (!(config["templateOverrides"] instanceof Dictionary)) {
            config["templateOverrides"] = {};
        }
        if (!(config["incrementOverrides"] instanceof Dictionary)) {
            config["incrementOverrides"] = {};
        }
        return config;
    }

    private function saveConfig(config as Dictionary) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        if (!_store.commitPair("config", config)) {
            _error = "Settings save failed";
            return false;
        }
        _error = null;
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

    private function entryDefinition(templateId as String, entryId as String) as Dictionary? {
        var template = Catalog.template(templateId);
        if (template == null) {
            return null;
        }
        var entries = (template as Dictionary)["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            if (Model.sameString(entry["entryId"], entryId)) {
                return entry;
            }
        }
        return null;
    }

    public function templateEntry(templateId as String, entryId as String) as Dictionary? {
        return entryDefinition(templateId, entryId);
    }

    public function templateTotalSets(templateId as String) as Number {
        var template = Catalog.template(templateId);
        var config = readConfig();
        if (template == null || config == null) {
            return 0;
        }
        var total = 0;
        var entries = (template as Dictionary)["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var count = templateNumber(config as Dictionary, templateId,
                entry["entryId"] as String, "workingSetCount");
            if (count instanceof Number) {
                total += count as Number;
            }
        }
        return total;
    }

    private function entryOverride(config as Dictionary, templateId as String,
                                   entryId as String) as Dictionary? {
        return Catalog.overridesFor(config, templateId, entryId);
    }

    private function templateNumber(config as Dictionary, templateId as String,
                                    entryId as String, field as String) as Number? {
        var override = Catalog.dictionaryValue(entryOverride(config, templateId, entryId), field);
        if (override instanceof Number &&
            (!Model.sameString(field, "workingSetCount") ||
             Model.inRange(override, 1, Model.MAX_SETS, false)) &&
            (!Model.sameString(field, "restSec") ||
             Model.inRange(override, 0, Model.MAX_REST_SEC, false)) &&
            ((!Model.sameString(field, "targetRepsMin") && !Model.sameString(field, "targetRepsMax")) ||
             Model.inRange(override, 1, Model.MAX_REPS, false)) &&
            (!Model.sameString(field, "targetDurationSec") ||
             Model.inRange(override, 1, Model.MAX_DURATION_SEC, false)) &&
            (!Model.sameString(field, "startingLoad100") ||
             Model.inRange(override, 0, Model.MAX_LOAD100, false))) {
            return override as Number;
        }
        var entry = entryDefinition(templateId, entryId);
        if (entry == null) {
            return null;
        }
        var seed = (entry as Dictionary)[field];
        if (seed instanceof Number) {
            return seed as Number;
        }
        if (Model.sameString(field, "restSec")) {
            var definition = Catalog.exercise((entry as Dictionary)["exerciseId"] as String);
            if (definition != null && (definition as Dictionary)["defaultRestSec"] instanceof Number) {
                return (definition as Dictionary)["defaultRestSec"] as Number;
            }
            var settings = Catalog.dictionaryValue(config, "settings");
            var configuredDefault = Catalog.dictionaryValue(
                settings instanceof Dictionary ? settings as Dictionary : null,
                "defaultRestSec"
            );
            return Model.inRange(configuredDefault, 0, Model.MAX_REST_SEC, false) ?
                configuredDefault as Number : 90;
        }
        return null;
    }

    public function numericConfigValue(kind as String, parentId as String,
                                       id as String, field as String) as Number? {
        var config = readConfig();
        if (config == null) {
            return null;
        }
        if (Model.sameString(kind, "setting")) {
            return Model.sameString(field, "defaultRestSec") ? defaultRestSec() : null;
        }
        if (Model.sameString(kind, "increment")) {
            var definition = Catalog.exercise(id);
            if (definition == null) {
                return null;
            }
            var override = Catalog.dictionaryValue(config["incrementOverrides"] as Dictionary, id);
            return override instanceof Number ? override as Number :
                (definition as Dictionary)["increment100"] as Number?;
        }
        if (Model.sameString(kind, "template")) {
            return templateNumber(config, parentId, id, field);
        }
        return null;
    }

    private function validTemplateNumber(templateId as String, entryId as String,
                                         field as String, value as Number,
                                         config as Dictionary) as Boolean {
        var template = Catalog.template(templateId);
        var entry = entryDefinition(templateId, entryId);
        if (template == null || entry == null) {
            return false;
        }
        var definition = Catalog.exercise((entry as Dictionary)["exerciseId"] as String);
        if (definition == null) {
            return false;
        }
        var type = (definition as Dictionary)["loadType"] as String;
        if (Model.sameString(field, "workingSetCount")) {
            if (!Model.inRange(value, 1, Model.MAX_SETS, false)) {
                return false;
            }
            var entries = (template as Dictionary)["entries"] as Array;
            var total = 0;
            for (var i = 0; i < entries.size(); i++) {
                var row = entries[i] as Dictionary;
                var count = templateNumber(config, templateId, row["entryId"] as String,
                    "workingSetCount");
                total += Model.sameString(row["entryId"], entryId) ? value :
                    (count instanceof Number ? count as Number : 0);
            }
            return total <= Model.MAX_SETS_PER_WORKOUT;
        }
        if (Model.sameString(field, "targetRepsMin") || Model.sameString(field, "targetRepsMax")) {
            if (Model.sameString(type, "timed") || !Model.inRange(value, 1, Model.MAX_REPS, false)) {
                return false;
            }
            var minimum = templateNumber(config, templateId, entryId, "targetRepsMin");
            var maximum = templateNumber(config, templateId, entryId, "targetRepsMax");
            if (Model.sameString(field, "targetRepsMin")) {
                minimum = value;
            } else {
                maximum = value;
            }
            return minimum instanceof Number && maximum instanceof Number && minimum <= maximum;
        }
        if (Model.sameString(field, "targetDurationSec")) {
            return Model.sameString(type, "timed") &&
                Model.inRange(value, 1, Model.MAX_DURATION_SEC, false);
        }
        if (Model.sameString(field, "restSec")) {
            return Model.inRange(value, 0, Model.MAX_REST_SEC, false);
        }
        if (Model.sameString(field, "startingLoad100")) {
            return (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) &&
                Model.inRange(value, 0, Model.MAX_LOAD100, false);
        }
        return false;
    }

    public function updateNumericConfig(kind as String, parentId as String,
                                        id as String, field as String,
                                        value as Number) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var next = config as Dictionary;
        if (Model.sameString(kind, "setting") && Model.sameString(field, "defaultRestSec")) {
            if (!Model.inRange(value, 0, Model.MAX_REST_SEC, false)) {
                return false;
            }
            var settings = SessionLogic.copyDictionary(next["settings"] as Dictionary);
            settings["defaultRestSec"] = value;
            next["settings"] = settings;
            return saveConfig(next);
        }
        if (Model.sameString(kind, "increment") && Model.sameString(field, "increment100")) {
            var definition = Catalog.exercise(id);
            if (definition == null ||
                (!Model.sameString((definition as Dictionary)["loadType"], "weight") &&
                 !Model.sameString((definition as Dictionary)["loadType"], "assistance")) ||
                !Model.inRange(value, 25, 10000, false) || (value % 25) != 0) {
                return false;
            }
            var increments = SessionLogic.copyDictionary(next["incrementOverrides"] as Dictionary);
            increments[id] = value;
            next["incrementOverrides"] = increments;
            return saveConfig(next);
        }
        if (!Model.sameString(kind, "template") ||
            !validTemplateNumber(parentId, id, field, value, next)) {
            return false;
        }
        var allOverrides = SessionLogic.copyDictionary(next["templateOverrides"] as Dictionary);
        var perTemplate = Catalog.dictionaryValue(allOverrides, parentId);
        var templateOverrides = perTemplate instanceof Dictionary ?
            SessionLogic.copyDictionary(perTemplate as Dictionary) : {};
        var perEntry = Catalog.dictionaryValue(templateOverrides, id);
        var entryOverrides = perEntry instanceof Dictionary ?
            SessionLogic.copyDictionary(perEntry as Dictionary) : {};
        entryOverrides[field] = value;
        templateOverrides[id] = entryOverrides;
        allOverrides[parentId] = templateOverrides;
        next["templateOverrides"] = allOverrides;
        return saveConfig(next);
    }

    public function toggleVibration() as Boolean {
        return setVibrationEnabled(!vibrationEnabled());
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
            (Model.sameString(_session["status"], "active") ||
             Model.sameString(_session["status"], "paused"));
    }

    public function isWorkoutPaused() as Boolean {
        return _session != null && Model.sameString(_session["status"], "paused");
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

    public function pauseWorkout(now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = WorkoutClock.pause(_session as Dictionary, now);
        if (candidate == null) {
            return false;
        }
        var next = candidate as Dictionary;
        var run = next["timedRun"];
        if (run instanceof Dictionary) {
            var pausedTimed = SessionLogic.pauseTimed(next, run["entryId"] as String,
                run["slot"] as Number, now);
            if (pausedTimed == null) {
                return false;
            }
            next = pausedTimed as Dictionary;
        }
        var rest = next["rest"];
        if (rest instanceof Dictionary && Model.sameString(rest["state"], "running")) {
            next["rest"] = RestClock.pause(rest as Dictionary, now);
        }
        next["status"] = "paused";
        return commit(next);
    }

    public function resumeWorkout(now as Number) as Boolean {
        if (!isWorkoutPaused()) {
            return false;
        }
        var candidate = WorkoutClock.resume(_session as Dictionary, now);
        if (candidate == null) {
            return false;
        }
        var next = candidate as Dictionary;
        var rest = next["rest"];
        if (rest instanceof Dictionary && Model.sameString(rest["state"], "paused")) {
            var resumedRest = RestClock.resume(rest as Dictionary, now);
            if (resumedRest == null) {
                return false;
            }
            next["rest"] = resumedRest;
        }
        next["status"] = "active";
        return commit(next);
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
        return candidate != null && commit(candidate as Dictionary);
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
        return hasPendingFinalization() && finalizePending();
    }

    public function hasRest() as Boolean {
        return _session != null && _session["rest"] instanceof Dictionary &&
            (Model.sameString(_session["rest"]["state"], "running") ||
             Model.sameString(_session["rest"]["state"], "expired"));
    }

    public function hasRunningRest() as Boolean {
        return isWorkoutRunning() && _session["rest"] instanceof Dictionary &&
            Model.sameString(_session["rest"]["state"], "running");
    }

    public function hasRunningTimed() as Boolean {
        return isWorkoutRunning() && _session["timedRun"] instanceof Dictionary;
    }

    public function onTick(now as Number, canVibrate as Boolean) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = null;
        var shouldAlert = false;
        if (_session["rest"] instanceof Dictionary) {
            var rest = RestClock.expire(_session["rest"] as Dictionary, now);
            if (rest != null) {
                candidate = SessionLogic.copyDictionary(_session as Dictionary);
                candidate["rest"] = rest;
                shouldAlert = true;
            }
        }
        var run = _session["timedRun"];
        if (run instanceof Dictionary && run["targetAlertConsumed"] != true) {
            var index = SessionLogic.exerciseIndex(_session as Dictionary, run["entryId"] as String);
            if (index >= 0) {
                var exercise = (_session["exercises"] as Array)[index] as Dictionary;
                var target = exercise["targetDurationSec"];
                if (target instanceof Number &&
                    SessionLogic.timedElapsedSec(run as Dictionary, now) >= (target as Number)) {
                    if (candidate == null) {
                        candidate = SessionLogic.copyDictionary(_session as Dictionary);
                    }
                    var nextRun = SessionLogic.copyDictionary(run as Dictionary);
                    nextRun["targetAlertConsumed"] = true;
                    candidate["timedRun"] = nextRun;
                    shouldAlert = true;
                }
            }
        }
        if (candidate != null) {
            return commit(candidate as Dictionary) && shouldAlert && canVibrate;
        }
        checkpoint(now);
        return false;
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

    private function commit(candidate as Dictionary) as Boolean {
        if (candidate["lastCheckpointAt"] instanceof Number) {
            candidate["lastCheckpointAt"] = Time.now().value();
        }
        if (!_store.commitPair("active", candidate)) {
            _error = "Save failed. Retry before continuing.";
            return false;
        }
        _session = candidate;
        _error = null;
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
                _error = "Timed set recovery failed";
                _recoveryBlocked = true;
                return;
            }
            candidate = pausedTimed as Dictionary;
        }
        var recovered = WorkoutClock.recover(candidate, now);
        if (!_store.commitPair("active", recovered)) {
            _error = "Recovery save failed";
            _recoveryBlocked = true;
            return;
        }
        _session = recovered;
        _recoveryBlocked = false;
    }

    private function historySlot(ended as Dictionary) as Number {
        var empty = -1;
        var oldest = -1;
        var oldestSequence = 2147483647;
        for (var i = 0; i < 4; i++) {
            var record = _store.loadPair("history" + i.toString());
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

    private function finalizePending() as Boolean {
        if (!hasPendingFinalization()) {
            return false;
        }
        var frozen = _session as Dictionary;
        var outcome = frozen["finishOutcome"] as String;
        var ended = SessionLogic.copyDictionary(frozen);
        ended["status"] = outcome;
        var target = historySlot(ended);
        if (target < 0) {
            _error = "History needs newer app";
            return false;
        }
        if (!_store.commitPair("history" + target.toString(), ended)) {
            _error = "History save failed";
            return false;
        }

        if (Model.sameString(outcome, "completed")) {
            var cache = readLastCache();
            if (!_store.hasUnsupportedRecord()) {
                var nextCache = LastPerformance.merge(cache, ended);
                if (!_store.commitPair("last", nextCache)) {
                    _error = "Previous performance save failed";
                    return false;
                }
            }
        }

        var tombstone = {
            "id" => frozen["id"],
            "sessionSeq" => frozen["sessionSeq"],
            "status" => outcome,
            "endedAt" => frozen["endedAt"]
        };
        if (!_store.commitPair("active", tombstone)) {
            _error = "Workout archive saved; retry finish";
            return false;
        }
        _session = ended;
        _error = null;
        return true;
    }

    public function startWorkout(templateId as String, now as Number) as Boolean {
        if (hasActiveSession() || hasPendingFinalization() || _activeUnsupported || _activeCorrupt) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var sequence = (config as Dictionary)["nextSessionSeq"] as Number;
        var nextConfig = SessionLogic.copyDictionary(config as Dictionary);
        nextConfig["nextSessionSeq"] = sequence + 1;
        if (!_store.commitPair("config", nextConfig)) {
            _error = "Could not reserve workout ID";
            return false;
        }
        var sessionId = "session-" + sequence.toString();
        var cache = readLastCache();
        var candidate = Catalog.createSession(templateId, sessionId, sequence, now, cache, nextConfig);
        if (candidate == null) {
            return false;
        }
        var fresh = candidate as Dictionary;
        var clock = WorkoutClock.start(now);
        var clockKeys = clock.keys();
        for (var i = 0; i < clockKeys.size(); i++) {
            fresh[clockKeys[i]] = clock[clockKeys[i]];
        }
        fresh["timedRun"] = null;
        return commit(fresh);
    }

    public function updateDraft(entryId as String, slot as Number, field as String, value as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.updateDraft(_session as Dictionary, entryId, slot, field, value);
        return candidate != null && commit(candidate as Dictionary);
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
        var slots = exercise["slots"] as Array;
        if (slot < 0 || slot >= slots.size()) {
            return false;
        }
        var draft = slots[slot]["draft"] as Dictionary;
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
        return candidate != null && commit(candidate as Dictionary);
    }

    public function correctSet(entryId as String, slot as Number, actual as Dictionary, now as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.correctSet(_session as Dictionary, entryId, slot, actual, now);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function undoSet(entryId as String, slot as Number) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.undoSet(_session as Dictionary, entryId, slot);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function closeExercise(entryId as String, closed as Boolean) as Boolean {
        if (!isWorkoutRunning()) {
            return false;
        }
        var candidate = SessionLogic.closeExercise(_session as Dictionary, entryId, closed);
        return candidate != null && commit(candidate as Dictionary);
    }

    public function finish(outcome as String, now as Number) as Boolean {
        if (hasPendingFinalization()) {
            return finalizePending();
        }
        if (!hasActiveSession() ||
            (!Model.sameString(outcome, "completed") && !Model.sameString(outcome, "aborted"))) {
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
            _error = "Log a set before saving";
            return false;
        }
        candidate["status"] = "finalizing";
        candidate["finishOutcome"] = outcome;
        candidate["completionKind"] = Model.sameString(outcome, "aborted") ? null :
            (totals["done"] == totals["planned"] ? "full" : "partial");
        candidate["endedAt"] = now;
        candidate["elapsedSec"] = WorkoutClock.elapsed(candidate, now);
        candidate["activeSec"] = WorkoutClock.active(candidate, now);
        candidate["rest"] = null;
        if (!commit(candidate)) {
            return false;
        }
        return finalizePending();
    }
}
