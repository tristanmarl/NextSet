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

    private function readGeneration(domain as String, generation as String) as Dictionary? {
        var raw = null;
        try {
            raw = readKey(domain + "." + generation);
        } catch (error) {
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

    private function equal(left as Object?, right as Object?) as Boolean {
        if (left == null || right == null) {
            return left == right;
        }
        if (left instanceof Dictionary && right instanceof Dictionary) {
            var a = left as Dictionary;
            var b = right as Dictionary;
            var keys = a.keys();
            if (keys.size() != b.keys().size()) {
                return false;
            }
            for (var i = 0; i < keys.size(); i++) {
                var key = keys[i];
                if (!b.hasKey(key) || !equal(a[key], b[key])) {
                    return false;
                }
            }
            return true;
        }
        if (left instanceof Array && right instanceof Array) {
            var a = left as Array;
            var b = right as Array;
            if (a.size() != b.size()) {
                return false;
            }
            for (var j = 0; j < a.size(); j++) {
                if (!equal(a[j], b[j])) {
                    return false;
                }
            }
            return true;
        }
        if (left instanceof String && right instanceof String) {
            return (left as String).equals(right as String);
        }
        return left == right;
    }

    public function commitPair(domain as String, payload as Dictionary) as Boolean {
        var current = loadPair(domain);
        if (_futureRecord || (_badRecord && current == null)) {
            return false;
        }
        var a = readGeneration(domain, "a");
        var b = readGeneration(domain, "b");
        if (_futureRecord) {
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
        } else if (b == null) {
            target = "b";
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
        var written = readGeneration(domain, target);
        if (written != null && written["rev"] == envelope["rev"] &&
            equal(written["payload"], payload)) {
            return true;
        }
        var recovered = loadPair(domain);
        return recovered != null && equal(recovered, payload);
    }
}
