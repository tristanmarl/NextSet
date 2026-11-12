import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Deterministic mutation fuzzing: a seeded LCG, value and text mutators, and failure logging.
// Every case starts with Fuzz.begin(seed); the same seed always rebuilds the same mutation, so a
// failure line ("FUZZ <label> seed=N ... | mutations") is enough to reproduce it.
module Fuzz {
    var _state as Long = 1l;
    // Mutations applied in the current case, newest last.
    var trail as Array = [];
    var failures as Number = 0;
    var seed as Number = 0;
    // Revision for hand-written stored envelopes: a new one defeats the store's validated-record cache.
    var rev as Number = 0;
    var _depth as Number = 0;

    function begin(newSeed as Number) as Void {
        seed = newSeed;
        _depth = 0;
        var seed2 = newSeed;
        _state = (seed2.toLong() * 2654435761l + 97l) & 2147483647l;
        trail = [];
        rand(7);
    }

    // 0 .. n-1
    function rand(n as Number) as Number {
        _state = (_state * 1103515245l + 12345l) & 2147483647l;
        return ((_state >> 12) % n.toLong()).toNumber();
    }

    function typeName(value as Object?) as String {
        if (value == null) {
            return "null";
        }
        if (value instanceof Number) {
            return "Number";
        }
        if (value instanceof Long) {
            return "Long";
        }
        if (value instanceof Float) {
            return "Float";
        }
        if (value instanceof Double) {
            return "Double";
        }
        if (value instanceof Boolean) {
            return "Boolean";
        }
        if (value instanceof String) {
            return "String";
        }
        if (value instanceof Array) {
            return "Array";
        }
        if (value instanceof Dictionary) {
            return "Dictionary";
        }
        return "other";
    }

    function rep(piece as String, length as Number) as String {
        var out = piece;
        while (out.length() < length) {
            out += out;
        }
        return out.substring(0, length) as String;
    }

    function nested(depth as Number) as Object? {
        var value = [1];
        for (var i = 0; i < depth; i++) {
            value = (i % 2 == 0) ? {"k" => value} : [value];
        }
        return value;
    }

    // 0.0/0.0 throws a fatal error in Monkey C, so the nearest tests are the float extremes.
    function nan() as Float {
        return 3.4e38f;
    }

    function copy(value as Object?) as Object? {
        if (value instanceof Dictionary) {
            var source = value as Dictionary;
            var out = {};
            var keys = source.keys();
            for (var i = 0; i < keys.size(); i++) {
                out[keys[i]] = copy(source[keys[i]]);
            }
            return out;
        }
        if (value instanceof Array) {
            var items = value as Array;
            var out = [];
            for (var i = 0; i < items.size(); i++) {
                out.add(copy(items[i]));
            }
            return out;
        }
        return value;
    }

    // A fresh random value of any JSON/storage type, biased to edge cases.
    function junk() as Object? {
        switch (rand(32)) {
            case 0: return null;
            case 1: return 0;
            case 2: return -1;
            case 3: return 2147483647;
            case 4: return -2147483647 - 1;
            case 5: return 1.5f;
            case 6: return nan();
            case 7: return -0.0f;
            case 8: return 4294967296l;
            case 9: return -1l;
            case 10: return 9223372036854775807l;
            case 11: return 1.0e300d;
            case 12: return "";
            case 13: return "x";
            case 14: return rep("long ", 400);
            case 15: return "Ä🦖💪€";
            case 16: return true;
            case 17: return false;
            case 18: return [];
            case 19: return {};
            case 20: return nested(5);
            case 21: return "60kg";
            case 22: return "-5kg";
            case 23: return "1e999lb";
            case 24: return [1, 2, 3];
            case 25: return {"a" => 1};
            case 26: return "60";
            case 27: return " ";
            case 28: return "\n";
            case 29: return rep("N", 70);
            case 30: return rep("€", 22);
            default: return rep("a", 130);
        }
    }

    // The same value in another type (calling a missing method is a fatal error, so by type).
    function convert(value as Object?) as Object? {
        var numeric = value instanceof Number || value instanceof Long || value instanceof Float ||
            value instanceof Double;
        var text = value instanceof String;
        switch (rand(10)) {
            case 0:
                if (numeric || text || value instanceof Boolean) {
                    return value.toString();
                }
                break;
            case 1:
                if (numeric || text) {
                    return value.toNumber();
                }
                break;
            case 2:
                if (numeric || text) {
                    return value.toFloat();
                }
                break;
            case 3:
                if (numeric || text) {
                    return value.toLong();
                }
                break;
            case 4: return null;
            case 5: return !(value == true);
            case 6: return [value];
            case 7: return {"k" => value};
            case 8:
                if (numeric || text) {
                    return value.toDouble();
                }
                break;
        }
        return junk();
    }

    function note(path as String, what as String) as Void {
        trail.add(path + " " + what);
    }

    // Applies one mutation somewhere inside value and returns the (possibly new) value. Monkey C's
    // call stack is only about a dozen frames deep, so the walk down is a loop, not recursion.
    // Containers on the way keep the changed child; value should be a private copy.
    function mutate(value as Object?, label as String) as Object? {
        var parents = [];
        var keys = [];
        var node = value;
        var path = "$";
        while (parents.size() < 12 && (node instanceof Dictionary || node instanceof Array) && rand(4) != 0) {
            var key = null;
            if (node instanceof Dictionary) {
                var names = (node as Dictionary).keys();
                if (names.size() == 0) {
                    break;
                }
                key = names[rand(names.size())];
            } else {
                if ((node as Array).size() == 0) {
                    break;
                }
                key = rand((node as Array).size());
            }
            parents.add(node);
            keys.add(key);
            path += "." + key.toString();
            node = (node as Object)[key];
        }
        var replaced = mutateHere(node, path);
        if (parents.size() == 0) {
            return replaced;
        }
        var last = parents.size() - 1;
        parents[last][keys[last]] = replaced;
        return value;
    }

    function mutateHere(value as Object?, path as String) as Object? {
        if (value instanceof Dictionary) {
            var dict = value as Dictionary;
            var names = dict.keys();
            var key = names.size() == 0 || rand(2) == 0 ? "extra" + rand(5).toString() : names[rand(names.size())];
            switch (rand(3)) {
                case 0:
                    dict.remove(key);
                    note(path, "drop " + key.toString());
                    break;
                case 1:
                    dict[key] = junk();
                    note(path, "set " + key.toString() + " junk " + typeName(dict[key]));
                    break;
                default:
                    dict[key] = nested(5);
                    note(path, "nest " + key.toString());
                    break;
            }
            return dict;
        }
        if (value instanceof Array) {
            var items = value as Array;
            var size = items.size();
            var out = [];
            switch (rand(7)) {
                case 0:
                    note(path, "empty array");
                    return out;
                case 1:
                    // duplicate every element (twice)
                    for (var r = 0; r < 2; r++) {
                        for (var i = 0; i < size; i++) {
                            out.add(copy(items[i]));
                        }
                    }
                    note(path, "double array");
                    return out;
                case 2:
                    var keep = size == 0 ? 0 : rand(size);
                    note(path, "truncate to " + keep.toString());
                    return items.slice(0, keep);
                case 3:
                    // repeat one element up to 12 times
                    var at = size == 0 ? 0 : rand(size);
                    var times = 2 + rand(11);
                    for (var i = 0; i < size; i++) {
                        out.add(items[i]);
                        if (i == at) {
                            for (var t = 0; t < times; t++) {
                                out.add(copy(items[i]));
                            }
                        }
                    }
                    note(path, "repeat [" + at.toString() + "] x" + times.toString());
                    return out;
                case 4:
                    var drop = size == 0 ? 0 : rand(size);
                    for (var i = 0; i < size; i++) {
                        if (i != drop) {
                            out.add(items[i]);
                        }
                    }
                    note(path, "remove [" + drop.toString() + "]");
                    return out;
                case 5:
                    out = items.slice(0, null);
                    out.add(junk());
                    note(path, "append junk");
                    return out;
                default:
                    note(path, "wrap in array");
                    return [items];
            }
        }
        // A leaf: another type, an extreme number, or a stretched string.
        var before = typeName(value);
        var next = null;
        var roll = rand(8);
        if (roll == 0 && value instanceof String) {
            next = (value as String) + rep("🦖é", 200 + rand(900));
        } else if (roll == 1) {
            next = junk();
        } else if (roll == 2 && (value instanceof Number || value instanceof Float)) {
            next = [0, -1, 2147483647, -2147483647 - 1, 0.0f, -1.0f, 3.0e38f, 1.0e-30f][rand(8)];
        } else {
            next = convert(value);
        }
        note(path, before + " -> " + typeName(next));
        return next;
    }

    // A copy of fixture with 'rounds' mutations.
    function mutated(fixture as Object?, rounds as Number) as Object? {
        var value = copy(fixture);
        for (var i = 0; i < rounds; i++) {
            value = mutate(value, "$");
        }
        return value;
    }

    // Like mutated, but the result is still a Dictionary (else the unmutated copy), for APIs that
    // take one.
    function mutatedDict(fixture as Dictionary, rounds as Number) as Dictionary {
        var value = mutated(fixture, rounds);
        if (value instanceof Dictionary) {
            return value as Dictionary;
        }
        trail.add("root replaced: unmutated copy used");
        return copy(fixture) as Dictionary;
    }

    // ---- Liftoscript text ----

    function programLine(n as Number) as String {
        switch (rand(20)) {
            case 0: return "# Week " + n.toString();
            case 1: return "#";
            case 2: return "##";
            case 3: return "## Day " + n.toString();
            case 4: return "// comment " + rep("c", rand(60));
            case 5: return "Squat / 3x5 100kg / 90s";
            case 6: return "";
            case 7: return "   ## Spaced Day";
            case 8: return "\t# Tabbed week";
            case 9: return "## Día 🦖 " + n.toString();
            case 10: return "// " + rep("x", 1000 + rand(2200));
            case 11: return "## " + rep("N", 60 + rand(20));
            case 12: return "## " + rep("€", 20 + rand(4));
            case 13: return "### Triple";
            case 14: return "##Day";
            case 15: return "# " + rep("W", 1018 + rand(12));
            case 16: return "## " + rep("D", 1018 + rand(12));
            case 17: return "# Week " + n.toString() + " - Deload";
            case 18: return "## Day\t" + n.toString();
            default: return "##  Two spaces";
        }
    }

    // A random program of up to maxLines lines. mode 0 plain; 1 padded with ASCII to about the
    // 16 KiB cap; 2 padded with 4-byte characters (few characters, over the cap in bytes).
    function programText(maxLines as Number, mode as Number) as String {
        var seps = ["\n", "\r\n", "\r", "\n\n", "\n", "\n"];
        var out = "";
        var lines = 1 + rand(maxLines);
        for (var i = 0; i < lines; i++) {
            out += programLine(i + 1) + seps[rand(seps.size())];
        }
        if (mode == 1) {
            var target = 16384 - 300 + rand(600);
            while (out.length() < target) {
                out += "// " + rep("f", 60 + rand(40)) + "\n";
            }
        } else if (mode == 2) {
            var target = 4000 + rand(400);
            while (out.length() < target) {
                out += "## 💪💪💪💪" + rep("💪", rand(40)) + "\n";
            }
        }
        trail.add("generated program mode " + mode.toString() + " length " + out.length().toString());
        return out;
    }

    // One random edit of an existing text: insert a header-like line, truncate, or repeat.
    function mutateText(text as String) as String {
        var length = text.length();
        var at = length == 0 ? 0 : rand(length);
        switch (rand(5)) {
            case 0:
            case 1:
                var inserted = programLine(rand(9));
                trail.add("insert " + inserted.length().toString() + " chars at " + at.toString());
                return text.substring(0, at) + "\n" + inserted + "\r\n" + text.substring(at, length);
            case 2:
                trail.add("truncate at " + at.toString());
                return text.substring(0, at) as String;
            case 3:
                trail.add("swap line endings to CR");
                return text.substring(0, at) + "\r" + text.substring(at, length);
            default:
                trail.add("repeat text");
                return text + text;
        }
    }

    // ---- failure reporting ----

    // Breadcrumb printed before each target call: a fatal Monkey C error (a missing method on a
    // value of the wrong type, "Failed invoking <symbol>") cannot be caught, so the last
    // "fz" line before its stack trace names the seed and mutations that caused it.
    function go(label as String) as Void {
        System.println("fz " + label + " seed=" + seed.toString() + " | " + summary());
    }

    function summary() as String {
        var out = "";
        for (var i = 0; i < trail.size(); i++) {
            out += (i == 0 ? "" : "; ") + (trail[i] as String);
        }
        return out.length() > 400 ? out.substring(0, 400) as String : out;
    }

    function caught(logger as Test.Logger, label as String, caseSeed as Number, ex as Lang.Exception) as Void {
        failures++;
        if (failures <= 6) {
            logger.error("FUZZ " + label + " seed=" + caseSeed.toString() + " threw " +
                ex.getErrorMessage() + " | " + summary());
            ex.printStackTrace();
        }
    }
}
