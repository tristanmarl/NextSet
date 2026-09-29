import Toybox.Application;
import Toybox.Lang;

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

    private function validConfig(payload as Dictionary) as Boolean {
        var version = payload["schemaVersion"];
        if (version instanceof Number && version > 2) {
            _futureRecord = true;
            return false;
        }
        if ((version != null && !(version == 1 || version == 2)) ||
            !Model.inRange(payload["nextSessionSeq"], 1, 2147483647, false) ||
            (payload["settings"] != null && !(payload["settings"] instanceof Dictionary)) ||
            (payload["templateOverrides"] != null &&
             !(payload["templateOverrides"] instanceof Dictionary)) ||
            (payload["incrementOverrides"] != null &&
             !(payload["incrementOverrides"] instanceof Dictionary)) ||
            (payload["routineNextEntrySeq"] != null &&
             !Model.inRange(payload["routineNextEntrySeq"], 1, 2147483647, false))) {
            return false;
        }
        if (version == 2 && !(payload["routines"] instanceof Array)) {
            return false;
        }
        if (payload["routines"] != null) {
            if (!(payload["routines"] instanceof Array)) {
                return false;
            }
            var routines = payload["routines"] as Array;
            if (routines.size() < 1 || routines.size() > Model.MAX_TEMPLATES) {
                return false;
            }
            for (var i = 0; i < routines.size(); i++) {
                if (!(routines[i] instanceof Dictionary)) {
                    return false;
                }
                var routine = routines[i] as Dictionary;
                if (!Catalog.validRoutine(routine) ||
                    !Model.validNonblankText(routine["name"], 64)) {
                    return false;
                }
                for (var j = 0; j < i; j++) {
                    if (Model.sameString((routines[j] as Dictionary)["id"], routine["id"])) {
                        return false;
                    }
                }
            }
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

    private function validRecent(payload as Dictionary) as Boolean {
        var items = payload["items"];
        if (!(items instanceof Array) || (items as Array).size() > 8) {
            return false;
        }
        var rows = items as Array;
        for (var i = 0; i < rows.size(); i++) {
            if (!(rows[i] instanceof Dictionary)) {
                return false;
            }
            var item = rows[i] as Dictionary;
            if (!Model.validId(item["id"]) || !Model.validNonblankText(item["name"], 64) ||
                !Model.validText(item["category"], 48, false) ||
                !Model.validText(item["code"], 64, false) ||
                !Model.inRange(item["categoryIndex"], 0, 46, false) ||
                (item["isBodyWeight"] != null && !(item["isBodyWeight"] instanceof Boolean))) {
                return false;
            }
        }
        return true;
    }

    private function validPayload(domain as String, payload as Dictionary) as Boolean {
        if (Model.sameString(domain, "config")) {
            return validConfig(payload);
        }
        if (Model.sameString(domain, "active")) {
            return Model.validStoredSession(payload, false);
        }
        if (Model.sameString(domain, "last")) {
            return LastPerformance.validCache(payload);
        }
        if (Model.sameString(domain, "recent")) {
            return validRecent(payload);
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

    public function hasUnsupportedRecord() as Boolean {
        return _futureRecord;
    }

    public function hasCorruptRecord() as Boolean {
        return _badRecord;
    }

    public function recoveredEarlierGeneration() as Boolean {
        return _recoveredRecord || _badRecord;
    }

    public function commitPair(domain as String, payload as Dictionary) as Boolean {
        _badRecord = false;
        _futureRecord = false;
        _recoveredRecord = false;
        if (!validPayload(domain, payload)) {
            return false;
        }
        var a = readGeneration(domain, "a");
        var b = readGeneration(domain, "b");
        if (_futureRecord || (_badRecord && a == null && b == null)) {
            return false;
        }
        var currentRevision = 0;
        if (a != null && a["rev"] > currentRevision) {
            currentRevision = a["rev"];
        }
        if (b != null && b["rev"] > currentRevision) {
            currentRevision = b["rev"];
        }
        var target = "a";
        if (a == null) {
            target = "a";
            _recoveredRecord = b != null;
        } else if (b == null) {
            target = "b";
            _recoveredRecord = true;
        } else {
            target = a["rev"] <= b["rev"] ? "a" : "b";
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
