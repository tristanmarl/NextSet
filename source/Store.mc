import Toybox.Application;
import Toybox.Lang;

module QueueLimits {
    const MAX_PENDING_UPLOADS = 4;
    const MAX_RETIRED_UPLOADS = 8;
}

class Store {
    private var _badRecord as Boolean = false;
    private var _futureRecord as Boolean = false;
    private var _recoveredRecord as Boolean = false;

    public function readKey(key as String) as Object? {
        return Application.Storage.getValue(key);
    }

    public function writeKey(key as String, value as Object) as Void {
        Application.Storage.setValue(key, value);
    }

    // Ordered ids of the routines stored under routine.<id>; ids are lowercase letters, digits, "-".
    private function validRoutineIds(value as Object?, allowEmpty as Boolean) as Boolean {
        if (!(value instanceof Array) || (!allowEmpty && (value as Array).size() < 1) ||
            (value as Array).size() > Model.MAX_TEMPLATES) {
            return false;
        }
        var ids = value as Array;
        for (var i = 0; i < ids.size(); i++) {
            if (!Model.validId(ids[i])) {
                return false;
            }
            for (var j = 0; j < i; j++) {
                if (Model.sameString(ids[j], ids[i])) {
                    return false;
                }
            }
        }
        return true;
    }

    private function validConfig(payload as Dictionary) as Boolean {
        var version = payload["schemaVersion"];
        if (version instanceof Number && version > 4) {
            _futureRecord = true;
            return false;
        }
        if ((version != null && !(version instanceof Number)) ||
            !Model.inRange(payload["nextSessionSeq"], 1, 2147483647, false)) {
            return false;
        }
        if (version != 4) {
            // An older schema is a readable record; SessionController starts fresh from defaults.
            return true;
        }
        if ((payload["settings"] != null && !(payload["settings"] instanceof Dictionary)) ||
            (payload["templateOverrides"] != null &&
             !(payload["templateOverrides"] instanceof Dictionary)) ||
            (payload["incrementOverrides"] != null &&
             !(payload["incrementOverrides"] instanceof Dictionary)) ||
            !validRoutineIds(payload["routineIds"], true) ||
            !Model.inRange(payload["routineSyncSeq"], 0, 2147483647, false) ||
            !Model.validText(payload["programId"], 64, true) ||
            !Model.validText(payload["programName"], 64, true) ||
            !Model.validText(payload["nextRoutineId"], 40, true)) {
            return false;
        }
        if (payload["settings"] instanceof Dictionary) {
            var settings = payload["settings"] as Dictionary;
            if ((settings["defaultRestSec"] != null &&
                 !Model.inRange(settings["defaultRestSec"], 0, Model.MAX_REST_SEC, false)) ||
                (settings["vibrationEnabled"] != null &&
                 !(settings["vibrationEnabled"] instanceof Boolean))) {
                return false;
            }
        }
        return true;
    }

    private function validUploadQueue(payload as Dictionary) as Boolean {
        var ids = payload["ids"];
        var retired = payload["retired"];
        if (!(ids instanceof Array) || (ids as Array).size() > QueueLimits.MAX_PENDING_UPLOADS ||
            (retired != null && (!(retired instanceof Array) ||
                (retired as Array).size() > QueueLimits.MAX_RETIRED_UPLOADS))) {
            return false;
        }
        var rows = ids as Array;
        for (var i = 0; i < rows.size(); i++) {
            if (!Model.validId(rows[i])) {
                return false;
            }
            for (var j = 0; j < i; j++) {
                if (Model.sameString(rows[i], rows[j])) {
                    return false;
                }
            }
        }
        if (retired instanceof Array) {
            var done = retired as Array;
            for (var i = 0; i < done.size(); i++) {
                if (!Model.validId(done[i])) {
                    return false;
                }
                for (var j = 0; j < i; j++) {
                    if (Model.sameString(done[i], done[j])) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    private function validRoutineSync(payload as Dictionary) as Boolean {
        var phase = payload["phase"];
        var days = payload["days"];
        var routineIds = payload["routineIds"];
        if (!Model.inRange(payload["sequence"], 1, 2147483647, false) ||
            !(phase instanceof String) ||
            !(Model.sameString(phase, "program") || Model.sameString(phase, "next") ||
              Model.sameString(phase, "days")) ||
            !Model.inRange(payload["index"], 0, Model.MAX_TEMPLATES, false) ||
            (days != null && (!(days instanceof Array) ||
                (days as Array).size() > Model.MAX_PROGRAM_DAYS ||
                (Model.sameString(phase, "days") &&
                    (days as Array).size() > Model.MAX_TEMPLATES))) ||
            !validRoutineIds(routineIds, true) ||
            (Model.sameString(phase, "program") &&
                (payload["programId"] != null || payload["programName"] != null)) ||
            (!Model.sameString(phase, "program") &&
                (!Model.validNonblankText(payload["programId"], 64) ||
                 !Model.validNonblankText(payload["programName"], 64)))) {
            return false;
        }
        if (days instanceof Array) {
            var rows = days as Array;
            for (var i = 0; i < rows.size(); i++) {
                if (!(rows[i] instanceof Dictionary)) {
                    return false;
                }
                var day = rows[i] as Dictionary;
                if (!Model.inRange(day["week"], 1, 1000, false) ||
                    !Model.inRange(day["dayInWeek"], 1, 1000, false) ||
                    !Model.validNonblankText(day["name"], 64)) {
                    return false;
                }
                for (var j = 0; j < i; j++) {
                    var prior = rows[j] as Dictionary;
                    if (prior["week"] == day["week"] &&
                        prior["dayInWeek"] == day["dayInWeek"]) {
                        return false;
                    }
                }
            }
        }
        if (payload["nextWeek"] != null || payload["nextDay"] != null) {
            if (!Model.inRange(payload["nextWeek"], 1, 1000, false) ||
                !Model.inRange(payload["nextDay"], 1, 1000, false)) {
                return false;
            }
        }
        return (days == null || payload["index"] <= (days as Array).size()) &&
            (routineIds as Array).size() == payload["index"];
    }

    private function validPayload(domain as String, payload as Dictionary) as Boolean {
        if (domain.length() > 8 && Model.sameString(domain.substring(0, 8), "routine.")) {
            return Catalog.validRoutine(payload) && Model.validNonblankText(payload["name"], 64);
        }
        if (Model.sameString(domain, "config")) {
            return validConfig(payload);
        }
        if (Model.sameString(domain, "uploadq")) {
            return validUploadQueue(payload);
        }
        if (Model.sameString(domain, "rsync")) {
            return validRoutineSync(payload);
        }
        if (Model.sameString(domain, "device")) {
            return Model.validId(payload["id"]);
        }
        if (domain.length() > 7 && Model.sameString(domain.substring(0, 7), "upload.")) {
            var id = domain.substring(7, domain.length());
            return Model.validId(id) && Model.sameString(payload["sessionId"], id) &&
                Model.validUpload(payload);
        }
        if (Model.sameString(domain, "active")) {
            return Model.validStoredSession(payload, false);
        }
        if (Model.sameString(domain, "last")) {
            return LastPerformance.validCache(payload);
        }
        for (var i = 0; i < 4; i++) {
            if (Model.sameString(domain, "history" + i.toString())) {
                return Model.validStoredSession(payload, true);
            }
        }
        return true;
    }

    private function readGeneration(domain as String, generation as String) as Dictionary? {
        var raw = null;
        try {
            raw = readKey(domain + "." + generation);
        } catch (error) {
            _badRecord = true;
            return null;
        }
        if (raw == null) {
            return null;
        }
        if (!(raw instanceof Dictionary)) {
            _badRecord = true;
            return null;
        }
        var record = raw as Dictionary;
        if (record["v"] != 1) {
            if (record["v"] instanceof Number && record["v"] > 1) {
                _futureRecord = true;
            } else {
                _badRecord = true;
            }
            return null;
        }
        if (!(record["rev"] instanceof Number) || record["rev"] < 1 ||
            !(record["payload"] instanceof Dictionary)) {
            _badRecord = true;
            return null;
        }
        var payload = record["payload"] as Dictionary;
        if (Model.sameString(domain, "last")) {
            var cleanCache = LastPerformance.sanitizeCache(payload);
            if (cleanCache.keys().size() != payload.keys().size()) {
                // A bad prefill entry is isolated; valid exercise entries stay usable.
                _badRecord = true;
            }
            record["payload"] = cleanCache;
        } else if (!validPayload(domain, payload)) {
            _badRecord = true;
            return null;
        }
        return record;
    }

    public function loadPair(domain as String) as Dictionary? {
        _badRecord = false;
        _futureRecord = false;
        _recoveredRecord = false;
        var a = readGeneration(domain, "a");
        var b = readGeneration(domain, "b");
        if (a == null && b == null) {
            return null;
        }
        if (a == null || b == null) {
            _recoveredRecord = true;
            return (a != null ? a : b)["payload"] as Dictionary;
        }
        return (a["rev"] >= b["rev"] ? a : b)["payload"] as Dictionary;
    }

    // The lower valid generation is retained as the config fallback after an atomic routine pivot.
    public function loadOlderPair(domain as String) as Dictionary? {
        _badRecord = false;
        _futureRecord = false;
        _recoveredRecord = false;
        var a = readGeneration(domain, "a");
        var b = readGeneration(domain, "b");
        if (a == null || b == null || a["rev"] == b["rev"]) {
            return null;
        }
        return (a["rev"] < b["rev"] ? a : b)["payload"] as Dictionary;
    }

    public function loadUploadQueue() as Array? {
        var payload = loadPair("uploadq");
        if (payload == null) {
            return hasCorruptRecord() || hasUnsupportedRecord() ? null : [];
        }
        if (hasUnsupportedRecord()) {
            return null;
        }
        return payload["ids"] as Array;
    }

    public function loadRoutineSync() as Dictionary? {
        var payload = loadPair("rsync");
        return hasCorruptRecord() || hasUnsupportedRecord() ? null : payload;
    }

    public function saveUploadQueue(ids as Array) as Boolean {
        var current = loadPair("uploadq");
        if (hasUnsupportedRecord() || hasCorruptRecord()) {
            return false;
        }
        var retired = current == null || !(current["retired"] instanceof Array) ? [] :
            (current["retired"] as Array).slice(0, null);
        if (!commitPair("uploadq", {"ids" => ids, "retired" => retired})) {
            return false;
        }
        cleanupRetiredUploads();
        return true;
    }

    public function removeUploadFromQueue(id as String) as Boolean {
        var current = loadPair("uploadq");
        if (hasUnsupportedRecord() || hasCorruptRecord()) {
            return false;
        }
        var ids = current == null ? [] : (current["ids"] as Array).slice(0, null);
        var retired = current == null || !(current["retired"] instanceof Array) ? [] :
            (current["retired"] as Array).slice(0, null);
        var older = loadOlderPair("uploadq");
        if (hasUnsupportedRecord() || hasCorruptRecord()) {
            return false;
        }
        if (older != null && older["retired"] instanceof Array) {
            var oldRetired = older["retired"] as Array;
            for (var i = 0; i < oldRetired.size(); i++) {
                if (!contains(retired, oldRetired[i])) {
                    retired.add(oldRetired[i]);
                }
            }
        }
        var kept = [];
        for (var i = 0; i < ids.size(); i++) {
            if (!Model.sameString(ids[i], id)) {
                kept.add(ids[i]);
            }
        }
        if (!contains(retired, id)) {
            if (retired.size() >= QueueLimits.MAX_RETIRED_UPLOADS) {
                cleanupRetiredUploads();
                return false;
            }
            retired.add(id);
        }
        if (!commitPair("uploadq", {"ids" => kept, "retired" => retired})) {
            return false;
        }
        cleanupRetiredUploads();
        return true;
    }

    // Small bounded map of finished uploads (newest 8) so History can show the outcome after the
    // queue has retired the job.
    public function loadUploadStatus() as Dictionary {
        var payload = loadPair("upstatus");
        var map = payload != null && payload["map"] instanceof Dictionary ?
            payload["map"] as Dictionary : {};
        var result = {};
        var keys = map.keys();
        for (var i = 0; i < keys.size(); i++) {
            result[keys[i]] = map[keys[i]];
        }
        return result;
    }

    public function markUploadStatus(id as String, state as String) as Void {
        var payload = loadPair("upstatus");
        var order = (payload != null && payload["order"] instanceof Array ?
            (payload["order"] as Array).slice(0, null) : []) as Array;
        var map = loadUploadStatus();
        if (!map.hasKey(id)) {
            order.add(id);
        }
        map[id] = state;
        while (order.size() > 8) {
            map.remove(order[0]);
            order = order.slice(1, null);
        }
        commitPair("upstatus", {"order" => order, "map" => map});
    }

    // Escape hatch for a damaged queue: drops the manifest and every upload record it lists.
    // Local workout history is untouched.
    public function clearUploadQueue(deleteJobs as Boolean) as Void {
        if (deleteJobs) {
            var found = [loadPair("uploadq"), loadOlderPair("uploadq")];
            for (var i = 0; i < found.size(); i++) {
                var payload = found[i];
                var lists = payload == null ? [] : [payload["ids"], payload["retired"]];
                for (var l = 0; l < lists.size(); l++) {
                    if (!(lists[l] instanceof Array)) {
                        continue;
                    }
                    var ids = lists[l] as Array;
                    for (var j = 0; j < ids.size(); j++) {
                        if (Model.validId(ids[j])) {
                            deleteUpload(ids[j] as String);
                        }
                    }
                }
            }
        }
        deletePair("uploadq");
    }

    private function contains(values as Array, value as Object?) as Boolean {
        for (var i = 0; i < values.size(); i++) {
            if (Model.sameString(values[i], value)) {
                return true;
            }
        }
        return false;
    }

    private function cleanupRetiredUploads() as Void {
        var latest = loadPair("uploadq");
        if (hasUnsupportedRecord() || hasCorruptRecord() || latest == null) {
            return;
        }
        var older = loadOlderPair("uploadq");
        if (hasUnsupportedRecord() || hasCorruptRecord()) {
            return;
        }
        var active = (latest["ids"] as Array).slice(0, null);
        if (older != null && older["ids"] instanceof Array) {
            var oldIds = older["ids"] as Array;
            for (var i = 0; i < oldIds.size(); i++) {
                if (!contains(active, oldIds[i])) {
                    active.add(oldIds[i]);
                }
            }
        }
        var retired = latest["retired"] instanceof Array ? latest["retired"] as Array : [];
        var kept = [];
        for (var i = 0; i < retired.size(); i++) {
            var id = retired[i] as String;
            if (contains(active, id)) {
                kept.add(id);
            } else {
                deleteUpload(id);
            }
        }
        if (kept.size() != retired.size()) {
            // Advance the second queue generation too; the older one may still hold only retired ids.
            commitPair("uploadq", {"ids" => latest["ids"], "retired" => kept});
        }
    }

    public function loadUpload(id as String) as Dictionary? {
        return loadPair("upload." + id);
    }

    public function loadDeviceId() as String? {
        var payload = loadPair("device");
        if (payload == null || hasUnsupportedRecord() || hasCorruptRecord() ||
            !Model.validId(payload["id"])) {
            return null;
        }
        return payload["id"] as String;
    }

    public function saveDeviceId(id as String) as Boolean {
        return Model.validId(id) && commitPair("device", {"id" => id});
    }

    public function saveUpload(payload as Dictionary) as Boolean {
        return Model.validId(payload["sessionId"]) &&
            commitPair("upload." + (payload["sessionId"] as String), payload);
    }

    public function deleteUpload(id as String) as Void {
        deletePair("upload." + id);
    }

    public function hasUnsupportedRecord() as Boolean {
        return _futureRecord;
    }

    public function hasCorruptRecord() as Boolean {
        return _badRecord;
    }

    public function recoveredEarlierGeneration() as Boolean {
        return _recoveredRecord || _badRecord;
    }

    // Envelope-only read: returns rev (0 if missing/unusable) without validating the payload.
    private function readEnvelope(domain as String, generation as String) as Dictionary? {
        var raw = null;
        try {
            raw = readKey(domain + "." + generation);
        } catch (error) {
            _badRecord = true;
            return null;
        }
        if (raw == null) {
            return null;
        }
        if (!(raw instanceof Dictionary)) {
            _badRecord = true;
            return null;
        }
        var record = raw as Dictionary;
        if (record["v"] != 1) {
            if (record["v"] instanceof Number && record["v"] > 1) {
                _futureRecord = true;
            } else {
                _badRecord = true;
            }
            return null;
        }
        if (!(record["rev"] instanceof Number) || record["rev"] < 1 ||
            !(record["payload"] instanceof Dictionary)) {
            _badRecord = true;
            return null;
        }
        return record;
    }

    private function readRevision(domain as String, generation as String) as Number {
        var record = readEnvelope(domain, generation);
        return record == null ? 0 : record["rev"] as Number;
    }

    // Newest valid-envelope generation's id, sessionSeq, templateId, endedAt and status, without validating the payload.
    // Returns null when nothing usable (or a non-session payload) is stored.
    public function peekSession(domain as String) as Dictionary? {
        _badRecord = false;
        _futureRecord = false;
        _recoveredRecord = false;
        var a = readEnvelope(domain, "a");
        var b = readEnvelope(domain, "b");
        var newest = a == null ? b : (b == null || a["rev"] >= b["rev"] ? a : b);
        if (newest == null) {
            return null;
        }
        var payload = newest["payload"] as Dictionary;
        if (!(payload["id"] instanceof String) || !(payload["sessionSeq"] instanceof Number)) {
            return null;
        }
        return {"id" => payload["id"], "sessionSeq" => payload["sessionSeq"],
            "templateId" => payload["templateId"], "endedAt" => payload["endedAt"],
            "status" => payload["status"]};
    }

    // Removes both generations of a domain (a leftover key is harmless, so failures are ignored).
    public function deletePair(domain as String) as Void {
        var generations = ["a", "b"];
        for (var i = 0; i < generations.size(); i++) {
            try {
                Application.Storage.deleteValue(domain + "." + generations[i]);
            } catch (error) {
            }
        }
    }

    public function commitPair(domain as String, payload as Dictionary) as Boolean {
        _badRecord = false;
        _futureRecord = false;
        _recoveredRecord = false;
        if (!validPayload(domain, payload)) {
            return false;
        }
        var a = readRevision(domain, "a");
        var b = readRevision(domain, "b");
        if (_futureRecord || (_badRecord && a == 0 && b == 0)) {
            return false;
        }
        var currentRevision = a > b ? a : b;
        var target = "a";
        if (a == 0) {
            target = "a";
            _recoveredRecord = b != 0;
        } else if (b == 0) {
            target = "b";
            _recoveredRecord = true;
        } else {
            target = a <= b ? "a" : "b";
        }
        var envelope = {};
        envelope["v"] = 1;
        envelope["rev"] = currentRevision + 1;
        envelope["payload"] = payload;
        try {
            writeKey(domain + "." + target, envelope);
        } catch (error) {
            return false;
        }
        return true;
    }
}
