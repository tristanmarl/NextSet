import Toybox.Lang;
import Toybox.Time;

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

    public function initialize(store as Store) {
        _store = store;
        _recorder = new StrengthRecorder();
        _session = _store.loadPair("active");
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
        if (hasActiveSession()) {
            recoverRunningSession(Time.now().value());
        }
    }

    public function session() as Dictionary? {
        return _session;
    }

    public function errorMessage() as String? {
        return Err.message(_errorCode);
    }

    // Envelope-only history summary for Home; null when the slot is empty or unreadable.
    public function peekHistory(slot as Number) as Dictionary? {
        return _store.peekSession("history" + slot.toString());
    }

    public function errorCode() as Number {
        return _errorCode;
    }

    public function configurationEditable() as Boolean {
        return !hasActiveSession() && !hasPendingFinalization() &&
            !_activeUnsupported && !_activeCorrupt;
    }

    private var _config as Dictionary? = null;

    private function defaultRoutines() as Array {
        var routines = Catalog.routineTemplates(null);
        if (routines.size() == 0) {
            routines.add({"id" => "routine-1", "name" => "Routine 1",
                "revision" => 1, "entries" => []});
        }
        return routines;
    }

    private function defaultConfig() as Dictionary {
        var settings = {
            "defaultRestSec" => 90,
            "vibrationEnabled" => true
        };
        return {
            "schemaVersion" => 3,
            "nextSessionSeq" => 1,
            "settings" => settings,
            "templateOverrides" => {},
            "incrementOverrides" => {},
            "routines" => defaultRoutines(),
            "routineNextEntrySeq" => 1
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
        var schemaVersion = config["schemaVersion"];
        if (schemaVersion instanceof Number && schemaVersion > 3) {
            _errorCode = Err.UPDATE_APP_TO_RESUME;
            return null;
        }
        if (schemaVersion != null && (!(schemaVersion instanceof Number) || schemaVersion < 1)) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        var legacy = !(schemaVersion instanceof Number && schemaVersion >= 3);
        if (!legacy) {
            var routines = loadRoutines(config["routineIds"] as Array);
            config.remove("routineIds");
            if (routines.size() == 0) {
                _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
                return null;
            }
            config["routines"] = routines;
        }
        if (schemaVersion == null || schemaVersion < 2) {
            var routines = Catalog.routineTemplates(config as Dictionary);
            if (routines.size() == 0) {
                routines = defaultRoutines();
            }
            var seedFields = ["workingSetCount", "targetRepsMin", "targetRepsMax",
                "targetDurationSec", "startingLoad100", "restSec"];
            for (var t = 0; t < routines.size(); t++) {
                var routine = routines[t] as Dictionary;
                var entries = routine["entries"] as Array;
                var baseCounts = [];
                for (var e = 0; e < entries.size(); e++) {
                    var entry = entries[e] as Dictionary;
                    baseCounts.add(entry["workingSetCount"]);
                    var baseMinimum = entry["targetRepsMin"];
                    var baseMaximum = entry["targetRepsMax"];
                    var old = Catalog.overridesFor(config as Dictionary,
                        routine["id"] as String, entry["entryId"] as String);
                    var exercise = Catalog.exerciseForEntry(entry) as Dictionary;
                    var type = exercise["loadType"] as String;
                    for (var f = 0; f < seedFields.size(); f++) {
                        var field = seedFields[f] as String;
                        var value = Catalog.dictionaryValue(old, field);
                        var valid = (Model.sameString(field, "workingSetCount") &&
                            Model.inRange(value, 1, Model.MAX_SETS, false)) ||
                            (Model.sameString(field, "restSec") &&
                            Model.inRange(value, 0, Model.MAX_REST_SEC, false)) ||
                            ((Model.sameString(field, "targetRepsMin") ||
                              Model.sameString(field, "targetRepsMax")) &&
                            !Model.sameString(type, "timed") &&
                            Model.inRange(value, 1, Model.MAX_REPS, false)) ||
                            (Model.sameString(field, "targetDurationSec") &&
                            Model.sameString(type, "timed") &&
                            Model.inRange(value, 1, Model.MAX_DURATION_SEC, false)) ||
                            (Model.sameString(field, "startingLoad100") &&
                            (Model.sameString(type, "weight") ||
                             Model.sameString(type, "assistance")) &&
                            Model.inRange(value, 0, Model.MAX_LOAD100, false));
                        if (valid) {
                            entry[field] = value;
                        }
                    }
                    if (entry["targetRepsMin"] instanceof Number &&
                        entry["targetRepsMax"] instanceof Number &&
                        entry["targetRepsMin"] > entry["targetRepsMax"]) {
                        entry["targetRepsMin"] = baseMinimum;
                        entry["targetRepsMax"] = baseMaximum;
                    }
                }
                if (Catalog.totalSets(routine) > Model.MAX_SETS_PER_WORKOUT) {
                    for (var e = 0; e < entries.size(); e++) {
                        entries[e]["workingSetCount"] = baseCounts[e];
                    }
                }
            }
            config["routines"] = routines;
            config["templateOverrides"] = {};
            config["routineNextEntrySeq"] = 1;
            config["schemaVersion"] = 2;
        }
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
        if (!(config["routines"] instanceof Array) ||
            !(config["routineNextEntrySeq"] instanceof Number) ||
            config["routineNextEntrySeq"] < 1) {
            _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
            return null;
        }
        if (legacy) {
            if (!validRoutineList(config["routines"] as Array)) {
                _errorCode = Err.SAVED_SETTINGS_ARE_DAMAGED;
                return null;
            }
            // v1/v2 -> v3, safe during an active session. Routine keys are written first and the
            // v3 config last, so an interrupted run leaves the old config in place and is redone.
            config["schemaVersion"] = 3;
            if (!writeAll(config)) {
                _errorCode = Err.SETTINGS_MIGRATION_SAVE_FAILED;
                return null;
            }
        } else {
            _stored = true;
        }
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
        result["schemaVersion"] = 3;
        return result;
    }

    // Every routine, then the config; used for migration and the first save of a default config.
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

    // Persists only what changed. Order keeps storage consistent if interrupted: a new routine
    // is written before the config that references it, config before edits to an existing routine
    // (a skipped sequence number is harmless), and a deleted routine's keys are removed last.
    // On failure the cache is dropped so the next read reflects what is actually stored.
    private function writeParts(next as Dictionary, routineId as String?, writeConfig as Boolean) as Boolean {
        var routines = next["routines"] as Array;
        var previousRoutines = _config == null ? [] : (_config as Dictionary)["routines"] as Array;
        var previousIds = routineIdsOf(previousRoutines);
        var ids = routineIdsOf(routines);
        var ok = true;
        if (!_stored) {
            ok = writeAll(next);
        } else {
            var index = routineId == null ? -1 : routineIndexIn(routines, routineId as String);
            var isNew = index >= 0 && !containsId(previousIds, routineId as String);
            if (isNew) {
                ok = _store.commitPair("routine." + (routineId as String), routines[index] as Dictionary);
            }
            if (ok && writeConfig) {
                ok = _store.commitPair("config", configOnly(next, ids));
            }
            if (ok && index >= 0 && !isNew) {
                ok = _store.commitPair("routine." + (routineId as String), routines[index] as Dictionary);
            }
        }
        if (!ok) {
            _config = null;
            return false;
        }
        for (var i = 0; i < previousIds.size(); i++) {
            if (!containsId(ids, previousIds[i] as String)) {
                _store.deletePair("routine." + (previousIds[i] as String));
            }
        }
        _config = SessionLogic.copyDictionary(next);
        return true;
    }

    private function validRoutineName(name as String) as Boolean {
        return Model.validNonblankText(name, 64);
    }

    private function validRoutineList(routines as Array) as Boolean {
        if (routines.size() < 1 || routines.size() > Model.MAX_TEMPLATES) {
            return false;
        }
        for (var i = 0; i < routines.size(); i++) {
            if (!(routines[i] instanceof Dictionary)) {
                return false;
            }
            var routine = routines[i] as Dictionary;
            if (!Catalog.validRoutine(routine) || !validRoutineName(routine["name"] as String)) {
                return false;
            }
            for (var j = 0; j < i; j++) {
                if (Model.sameString((routines[j] as Dictionary)["id"], routine["id"])) {
                    return false;
                }
            }
        }
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

    private function routineDefinition(config as Dictionary, templateId as String) as Dictionary? {
        return Catalog.routineTemplate(config, templateId);
    }

    private function entryDefinition(config as Dictionary, templateId as String,
                                     entryId as String) as Dictionary? {
        var template = routineDefinition(config, templateId);
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
        var config = readConfig();
        var entry = config == null ? null : entryDefinition(config as Dictionary, templateId, entryId);
        return entry == null ? null : SessionLogic.copyDictionary(entry as Dictionary);
    }

    public function templateExercise(templateId as String, entryId as String) as Dictionary? {
        var entry = templateEntry(templateId, entryId);
        return entry == null ? null : Catalog.exerciseForEntry(entry as Dictionary);
    }

    public function templateTotalSets(templateId as String) as Number {
        var config = readConfig();
        var template = config == null ? null : routineDefinition(config as Dictionary, templateId);
        if (template == null || config == null) {
            return 0;
        }
        var total = 0;
        var entries = (template as Dictionary)["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            total += entries[i]["workingSetCount"] as Number;
        }
        return total;
    }

    private function entryOverride(config as Dictionary, templateId as String,
                                   entryId as String) as Dictionary? {
        return Catalog.overridesFor(config, templateId, entryId);
    }

    private function templateNumber(config as Dictionary, templateId as String,
                                    entryId as String, field as String) as Number? {
        var entry = entryDefinition(config, templateId, entryId);
        if (entry == null) {
            return null;
        }
        var configured = (entry as Dictionary)[field];
        if (configured instanceof Number) {
            return configured as Number;
        }
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
             Model.inRange(override, 0, Model.MAX_LOAD100, false)) &&
            (!Model.sameString(field, "increment100") ||
             (Model.inRange(override, 25, 10000, false) && (override as Number) % 25 == 0))) {
            return override as Number;
        }
        if (Model.sameString(field, "restSec")) {
            var definition = Catalog.exerciseForEntry(entry as Dictionary);
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
        if (Model.sameString(field, "increment100")) {
            var definition = Catalog.exerciseForEntry(entry as Dictionary);
            var increment = definition == null ? null : (definition as Dictionary)["increment100"];
            var global = Catalog.dictionaryValue(config["incrementOverrides"] as Dictionary,
                (entry as Dictionary)["exerciseId"] as String);
            if (Model.inRange(global, 25, 10000, false) && (global as Number) % 25 == 0) {
                return global as Number;
            }
            return Model.inRange(increment, 25, 10000, false) ? increment as Number : null;
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
        if (Model.sameString(kind, "template")) {
            return templateNumber(config, parentId, id, field);
        }
        return null;
    }

    private function validTemplateNumber(templateId as String, entryId as String,
                                         field as String, value as Number,
                                         config as Dictionary) as Boolean {
        var template = routineDefinition(config, templateId);
        var entry = entryDefinition(config, templateId, entryId);
        if (template == null || entry == null) {
            return false;
        }
        var definition = Catalog.exerciseForEntry(entry as Dictionary);
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
                // Raising the minimum past the maximum raises the maximum with it.
                if (maximum instanceof Number && maximum < value) {
                    maximum = value;
                }
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
        if (Model.sameString(field, "increment100")) {
            return (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) &&
                Model.inRange(value, 25, 10000, false) && (value % 25) == 0;
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
        if (!Model.sameString(kind, "template") ||
            !validTemplateNumber(parentId, id, field, value, next)) {
            return false;
        }
        var routines = copyRoutines(next);
        var routineIndex = routineIndexIn(routines, parentId);
        var entryIndex = routineIndex < 0 ? -1 : entryIndexIn(routines[routineIndex], id);
        if (entryIndex < 0) {
            return false;
        }
        var edited = routines[routineIndex]["entries"][entryIndex] as Dictionary;
        edited[field] = value;
        if (Model.sameString(field, "targetRepsMin") && edited["targetRepsMax"] instanceof Number &&
            edited["targetRepsMax"] < value) {
            edited["targetRepsMax"] = value;
        }
        return saveRoutines(next, routines, parentId, false);
    }

    private function copyRoutines(config as Dictionary) as Array {
        var result = [];
        var source = config["routines"] as Array;
        for (var i = 0; i < source.size(); i++) {
            var routine = SessionLogic.copyDictionary(source[i] as Dictionary);
            var entries = [];
            var sourceEntries = routine["entries"] as Array;
            for (var j = 0; j < sourceEntries.size(); j++) {
                entries.add(SessionLogic.copyDictionary(sourceEntries[j] as Dictionary));
            }
            routine["entries"] = entries;
            result.add(routine);
        }
        return result;
    }

    private function routineIndexIn(routines as Array, templateId as String) as Number {
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString(routines[i]["id"], templateId)) {
                return i;
            }
        }
        return -1;
    }

    private function entryIndexIn(routine as Dictionary, entryId as String) as Number {
        var entries = routine["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            if (Model.sameString(entries[i]["entryId"], entryId)) {
                return i;
            }
        }
        return -1;
    }

    // Validates only the changed routine (the list size and ids are cheap checks).
    private function saveRoutines(config as Dictionary, routines as Array, routineId as String,
                                  writeConfig as Boolean) as Boolean {
        var index = routineIndexIn(routines, routineId);
        var valid = routines.size() >= 1 && routines.size() <= Model.MAX_TEMPLATES;
        if (valid && index >= 0) {
            var routine = routines[index] as Dictionary;
            valid = Catalog.validRoutine(routine) && validRoutineName(routine["name"] as String);
        }
        if (!valid) {
            _errorCode = Err.ROUTINE_LIST_IS_INVALID;
            return false;
        }
        var next = SessionLogic.copyDictionary(config);
        next["routines"] = routines;
        return saveParts(next, routineId, writeConfig);
    }

    public function createRoutine(name as String) as String? {
        if (!configurationEditable()) {
            return null;
        }
        if (!validRoutineName(name)) {
            _errorCode = Err.ROUTINE_NAME_IS_REQUIRED_64_BYTES_MAX;
            return null;
        }
        var config = readConfig();
        if (config == null) {
            return null;
        }
        var routines = copyRoutines(config as Dictionary);
        if (routines.size() >= Model.MAX_TEMPLATES) {
            _errorCode = Err.ROUTINE_LIMIT_REACHED;
            return null;
        }
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString((routines[i] as Dictionary)["name"], name)) {
                _errorCode = Err.ROUTINE_NAME_ALREADY_EXISTS;
                return null;
            }
        }
        var sequence = config["routineNextEntrySeq"] as Number;
        var id = "routine-" + sequence.toString();
        while (routineIndexIn(routines, id) >= 0) {
            sequence++;
            id = "routine-" + sequence.toString();
        }
        var routine = {"id" => id, "name" => name, "revision" => 1, "entries" => []};
        if (!Model.validId(id) || !Catalog.validRoutine(routine)) {
            _errorCode = Err.ROUTINE_COULD_NOT_BE_CREATED;
            return null;
        }
        routines.add(routine);
        var next = SessionLogic.copyDictionary(config as Dictionary);
        next["routineNextEntrySeq"] = sequence + 1;
        if (!saveRoutines(next, routines, id, true)) {
            return null;
        }
        return id;
    }

    public function renameRoutine(templateId as String, name as String) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        if (!validRoutineName(name)) {
            _errorCode = Err.ROUTINE_NAME_IS_REQUIRED_64_BYTES_MAX;
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var routines = copyRoutines(config as Dictionary);
        var index = routineIndexIn(routines, templateId);
        if (index < 0) {
            _errorCode = Err.ROUTINE_NOT_FOUND;
            return false;
        }
        for (var i = 0; i < routines.size(); i++) {
            if (i != index && Model.sameString((routines[i] as Dictionary)["name"], name)) {
                _errorCode = Err.ROUTINE_NAME_ALREADY_EXISTS;
                return false;
            }
        }
        routines[index]["name"] = name;
        return saveRoutines(config as Dictionary, routines, templateId, false);
    }

    public function deleteRoutine(templateId as String) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var routines = copyRoutines(config as Dictionary);
        var index = routineIndexIn(routines, templateId);
        if (index < 0) {
            _errorCode = Err.ROUTINE_NOT_FOUND;
            return false;
        }
        if (routines.size() <= 1) {
            _errorCode = Err.AT_LEAST_ONE_ROUTINE_IS_KEPT;
            return false;
        }
        var kept = [];
        for (var i = 0; i < routines.size(); i++) {
            if (i != index) {
                kept.add(routines[i]);
            }
        }
        return saveRoutines(config as Dictionary, kept, templateId, true);
    }

    private function makeRoutineEntry(templateId as String, entryId as String,
                                      definition as Dictionary, loadType as String,
                                      previous as Dictionary?, defaultRest as Number) as Dictionary? {
        var exerciseId = definition["id"];
        var name = definition["name"];
        var category = definition["category"];
        var code = definition["code"];
        if (!Model.validId(exerciseId) || !Model.validText(name, 64, false) ||
            !Model.validText(category, 48, false) || !Model.validText(code, 64, false) ||
            !Model.validLoadType(loadType)) {
            return null;
        }
        var timed = Model.sameString(loadType, "timed");
        var loadable = Model.sameString(loadType, "weight") ||
            Model.sameString(loadType, "assistance");
        var entry = {
            "entryId" => entryId,
            "exerciseId" => exerciseId,
            "name" => name,
            "garminCategory" => category,
            "garminCode" => code,
            "isBodyWeight" => definition["isBodyWeight"],
            "loadType" => loadType,
            "unit" => loadable ? "kg" : null,
            "increment100" => loadable ? (previous != null &&
                Model.inRange(previous["increment100"], 25, 10000, false) ?
                previous["increment100"] : 500) : null,
            "defaultRestSec" => defaultRest,
            "workingSetCount" => previous != null && previous["workingSetCount"] instanceof Number ?
                previous["workingSetCount"] : 3,
            "targetRepsMin" => timed ? null : 10,
            "targetRepsMax" => timed ? null : 10,
            "targetDurationSec" => timed ? 30 : null,
            "startingLoad100" => loadable ? 0 : null,
            "restSec" => previous != null && previous["restSec"] instanceof Number ?
                previous["restSec"] : defaultRest,
            "notes" => previous == null ? null : previous["notes"]
        };
        if (previous != null && !timed && !Model.sameString(previous["loadType"], "timed") &&
            previous["targetRepsMin"] instanceof Number && previous["targetRepsMax"] instanceof Number) {
            entry["targetRepsMin"] = previous["targetRepsMin"];
            entry["targetRepsMax"] = previous["targetRepsMax"];
        }
        if (timed && previous != null && Model.sameString(previous["loadType"], "timed") &&
            previous["targetDurationSec"] instanceof Number) {
            entry["targetDurationSec"] = previous["targetDurationSec"];
        }
        if (loadable && previous != null &&
            (Model.sameString(previous["loadType"], "weight") ||
             Model.sameString(previous["loadType"], "assistance")) &&
            previous["startingLoad100"] instanceof Number) {
            entry["startingLoad100"] = previous["startingLoad100"];
        }
        return entry;
    }

    public function addRoutineExercise(templateId as String, definition as Dictionary,
                                       loadType as String) as String? {
        if (!configurationEditable()) {
            return null;
        }
        var config = readConfig();
        if (config == null) {
            return null;
        }
        var routines = copyRoutines(config as Dictionary);
        var index = routineIndexIn(routines, templateId);
        if (index < 0) {
            return null;
        }
        var routine = routines[index] as Dictionary;
        var entries = routine["entries"] as Array;
        var sets = Catalog.totalSets(routine);
        if (entries.size() >= Model.MAX_ENTRIES || sets + 3 > Model.MAX_SETS_PER_WORKOUT) {
            _errorCode = Err.ROUTINE_LIMIT_REACHED;
            return null;
        }
        var nextSeq = config["routineNextEntrySeq"] as Number;
        var entryId = templateId + "-new-" + nextSeq.toString();
        var added = makeRoutineEntry(templateId, entryId, definition, loadType, null,
            defaultRestSec());
        if (added == null) {
            return null;
        }
        entries.add(added);
        var nextConfig = SessionLogic.copyDictionary(config as Dictionary);
        nextConfig["routineNextEntrySeq"] = nextSeq + 1;
        if (!Catalog.validRoutine(routine)) {
            return null;
        }
        return saveRoutines(nextConfig, routines, templateId, true) ? entryId : null;
    }

    public function replaceRoutineExercise(templateId as String, entryId as String,
                                           definition as Dictionary,
                                           loadType as String) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var routines = copyRoutines(config as Dictionary);
        var routineIndex = routineIndexIn(routines, templateId);
        var index = routineIndex < 0 ? -1 : entryIndexIn(routines[routineIndex], entryId);
        if (index < 0) {
            return false;
        }
        var routine = routines[routineIndex] as Dictionary;
        var previous = (routine["entries"] as Array)[index] as Dictionary;
        var replacement = makeRoutineEntry(templateId, entryId, definition, loadType, previous,
            defaultRestSec());
        if (replacement == null) {
            return false;
        }
        routine["entries"][index] = replacement;
        var total = Catalog.totalSets(routine);
        if (total > Model.MAX_SETS_PER_WORKOUT || !Catalog.validRoutine(routine)) {
            return false;
        }
        return saveRoutines(config as Dictionary, routines, templateId, false);
    }

    public function moveRoutineEntry(templateId as String, entryId as String,
                                      direction as Number) as Boolean {
        if (!configurationEditable() || (direction != -1 && direction != 1)) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var routines = copyRoutines(config as Dictionary);
        var routineIndex = routineIndexIn(routines, templateId);
        var index = routineIndex < 0 ? -1 : entryIndexIn(routines[routineIndex], entryId);
        if (index < 0) {
            return false;
        }
        var entries = routines[routineIndex]["entries"] as Array;
        var target = index + direction;
        if (target < 0 || target >= entries.size()) {
            return false;
        }
        var swap = entries[index];
        entries[index] = entries[target];
        entries[target] = swap;
        return saveRoutines(config as Dictionary, routines, templateId, false);
    }

    public function removeRoutineEntry(templateId as String, entryId as String) as Boolean {
        if (!configurationEditable()) {
            return false;
        }
        var config = readConfig();
        if (config == null) {
            return false;
        }
        var routines = copyRoutines(config as Dictionary);
        var routineIndex = routineIndexIn(routines, templateId);
        var index = routineIndex < 0 ? -1 : entryIndexIn(routines[routineIndex], entryId);
        if (index < 0) {
            return false;
        }
        var source = routines[routineIndex]["entries"] as Array;
        var kept = [];
        for (var i = 0; i < source.size(); i++) {
            if (i != index) {
                kept.add(source[i]);
            }
        }
        routines[routineIndex]["entries"] = kept;
        return saveRoutines(config as Dictionary, routines, templateId, false);
    }

    public function recentGarminExercises() as Array {
        var saved = _store.loadPair("recent");
        if (saved == null || !(saved["items"] instanceof Array)) {
            return [];
        }
        return saved["items"] as Array;
    }

    public function usedGarminExercises() as Array {
        var result = [];
        var seen = {};
        var routines = routineTemplates();
        for (var r = 0; r < routines.size(); r++) {
            var entries = routines[r]["entries"] as Array;
            for (var e = 0; e < entries.size(); e++) {
                var entry = entries[e] as Dictionary;
                if (!(entry["garminCategory"] instanceof String) ||
                    !(entry["garminCode"] instanceof String) || seen[entry["exerciseId"]] == true) {
                    continue;
                }
                var definition = Catalog.exerciseForEntry(entry);
                if (definition == null) {
                    continue;
                }
                var item = SessionLogic.copyDictionary(definition as Dictionary);
                item["category"] = entry["garminCategory"];
                item["code"] = entry["garminCode"];
                item["pickerName"] = entry["name"];
                result.add(item);
                seen[entry["exerciseId"]] = true;
            }
        }
        return result;
    }

    public function rememberGarminExercise(definition as Dictionary,
                                           categoryIndex as Number) as Boolean {
        var category = definition["category"] instanceof String ? definition["category"] :
            definition["garminCategory"];
        var code = definition["code"] instanceof String ? definition["code"] :
            definition["garminCode"];
        if (!Model.validId(definition["id"]) || !(category instanceof String) ||
            !(code instanceof String) || categoryIndex < 0) {
            return false;
        }
        var items = [];
        var recent = recentGarminExercises();
        items.add({"id" => definition["id"],
            "name" => Catalog.garminName(category as String, code as String),
            "category" => category, "code" => code, "categoryIndex" => categoryIndex,
            "isBodyWeight" => definition["isBodyWeight"]});
        for (var i = 0; i < recent.size() && items.size() < 8; i++) {
            var item = recent[i] as Dictionary;
            if (!Model.sameString(item["id"], definition["id"])) {
                items.add(item);
            }
        }
        return _store.commitPair("recent", {"items" => items});
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
        if (_session == null || !_recorder.isRecording()) {
            return;
        }
        var index = SessionLogic.exerciseIndex(_session as Dictionary, entryId);
        if (index >= 0) {
            _recorder.recordSet(SessionLogic.lapPayload(
                (_session["exercises"] as Array)[index] as Dictionary, slot));
        }
    }

    private function commit(candidate as Dictionary) as Boolean {
        if (candidate["lastCheckpointAt"] instanceof Number) {
            candidate["lastCheckpointAt"] = Time.now().value();
        }
        if (!_store.commitPair("active", candidate)) {
            _errorCode = Err.SAVE_FAILED_RETRY_BEFORE_CONTINUING;
            return false;
        }
        _session = candidate;
        _errorCode = Err.NONE;
        return true;
    }

    private function recoverRunningSession(now as Number) as Void {
        var source = _session as Dictionary;
        var candidate = SessionLogic.copyDictionary(source);
        if (Model.sameString(candidate["status"], "paused")) {
            // Workout pause no longer exists; sessions saved as paused resume as active.
            var resumed = WorkoutClock.resume(candidate, now);
            if (resumed != null) {
                candidate = resumed as Dictionary;
            }
            var pausedRest = candidate["rest"];
            if (pausedRest instanceof Dictionary && Model.sameString(pausedRest["state"], "paused")) {
                candidate["rest"] = RestClock.resume(pausedRest as Dictionary, now);
            }
            candidate["status"] = "active";
        }
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
            // it as discarded (there is nothing left to discard).
            discarding["fitState"] = !_recorder.hasSession() || _recorder.discard() ?
                "discarded" : "discard_failed";
            if (!_store.commitPair("active", discarding)) {
                _errorCode = Err.ACTIVITY_STATE_SAVE_FAILED;
                return false;
            }
            _session = discarding;
            return false;
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
        _errorCode = Err.NONE;
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
        var config = _pendingStartConfig as Dictionary;
        var sequence = config["nextSessionSeq"] as Number;
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

    private function sessionAlternativeSnapshot(source as Dictionary,
                                                previousExercise as Dictionary,
                                                entryId as String,
                                                definition as Dictionary,
                                                loadType as String,
                                                setCount as Number) as Dictionary? {
        var previous = {
            "workingSetCount" => setCount,
            "restSec" => previousExercise["restSec"],
            "notes" => previousExercise["notes"],
            "targetRepsMin" => previousExercise["targetRepsMin"],
            "targetRepsMax" => previousExercise["targetRepsMax"],
            "targetDurationSec" => previousExercise["targetDurationSec"],
            "loadType" => previousExercise["loadType"],
            "increment100" => previousExercise["weightIncrement100"]
        };
        var nextSlot = SessionLogic.nextSlot(previousExercise);
        if (nextSlot >= 0) {
            var slots = previousExercise["slots"] as Array;
            var draft = slots[nextSlot]["draft"] as Dictionary;
            if (draft["load100"] instanceof Number) {
                previous["startingLoad100"] = draft["load100"];
            }
        }
        var entry = makeRoutineEntry(source["templateId"] as String, entryId,
            definition, loadType, previous, defaultRestSec());
        if (entry == null) {
            _errorCode = Err.EXERCISE_CHOICE_INVALID;
            return null;
        }
        var routine = {
            "id" => source["templateId"],
            "name" => source["templateName"],
            "revision" => source["templateRevision"],
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
        return (generated as Dictionary)["exercises"][0] as Dictionary;
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
