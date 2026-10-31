import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

module UiFormat {
    var _captionFont as Graphics.FontType? = null;

    function captionFont() as Graphics.FontType {
        if (_captionFont == null) {
            // Many MIP watches (e.g. fr255s) have no vector fonts: calling it there is a Symbol Not Found crash.
            if (Graphics has :getVectorFont) {
                _captionFont = Graphics.getVectorFont({:font => Graphics.FONT_XTINY, :scale => 0.75});
            }
            if (_captionFont == null) {
                _captionFont = Graphics.FONT_XTINY;
            }
        }
        return _captionFont as Graphics.FontType;
    }

    // "65 kg × 8" with the focused part yellow and underlined (reps when loadText is null).
    // Returns the bottom of the line like drawLine.
    function drawSetValue(dc as Dc, loadText as String?, repsText as String, loadFocused as Boolean,
                          y as Number, font as Graphics.FontType) as Number {
        var height = dc.getFontHeight(font);
        var parts = loadText == null ? [repsText] : [loadText as String, " × ", repsText];
        var focused = loadText == null ? 0 : (loadFocused ? 0 : 2);
        var total = 0;
        for (var i = 0; i < parts.size(); i++) {
            total += dc.getTextWidthInPixels(parts[i] as String, font);
        }
        var x = (dc.getWidth() - total) / 2;
        for (var i = 0; i < parts.size(); i++) {
            var width = dc.getTextWidthInPixels(parts[i] as String, font);
            var color = i == focused ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
            dc.setColor(color, Graphics.COLOR_BLACK);
            dc.drawText(x, y, font, parts[i] as String, Graphics.TEXT_JUSTIFY_LEFT);
            if (i == focused) {
                dc.setPenWidth(2);
                dc.drawLine(x, y + height - 2, x + width, y + height - 2);
                dc.setPenWidth(1);
            }
            x += width;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        return y + height;
    }

    // Return the bottom of the font box so the next row cannot erase this one.
    function drawLine(dc as Dc, value as String, y as Number,
                      font as Graphics.FontType) as Number {
        dc.drawText(dc.getWidth() / 2, y, font, safeText(dc, value, y, font),
            Graphics.TEXT_JUSTIFY_CENTER);
        return y + dc.getFontHeight(font);
    }

    function safeText(dc as Dc, value as String, y as Number,
                      font as Graphics.FontType) as String {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var radius = (width < height ? width : height) / 2 - 12;
        var topOffset = (y - height / 2).abs();
        var bottomOffset = (y + dc.getFontHeight(font) - height / 2).abs();
        var offset = topOffset > bottomOffset ? topOffset : bottomOffset;
        var remaining = radius * radius - offset * offset;
        if (remaining <= 0) {
            return "";
        }
        return fitText(dc, value, font, 2 * Math.sqrt(remaining) - 16);
    }

    function fitText(dc as Dc, value as String, font as Graphics.FontType,
                     maxWidth as Numeric) as String {
        if (maxWidth < dc.getTextWidthInPixels("...", font)) {
            return "";
        }
        var text = value;
        while (text.length() > 3 && dc.getTextWidthInPixels(text, font) > maxWidth) {
            text = text.substring(0, text.length() - 4) + "...";
        }
        return text;
    }

    function wrapTitle(dc as Dc, value as String, font as Graphics.FontType,
                       maxWidth as Numeric) as Array {
        if (dc.getTextWidthInPixels(value, font) <= maxWidth) {
            return [value];
        }
        var splitAt = -1;
        var bestDifference = 999999;
        for (var i = 1; i < value.length() - 1; i++) {
            if (!Model.sameString(value.substring(i, i + 1), " ")) {
                continue;
            }
            var first = value.substring(0, i);
            var second = value.substring(i + 1, value.length());
            var firstWidth = dc.getTextWidthInPixels(first, font);
            var secondWidth = dc.getTextWidthInPixels(second, font);
            if (firstWidth <= maxWidth && secondWidth <= maxWidth) {
                var difference = (firstWidth - secondWidth).abs();
                if (difference < bestDifference) {
                    splitAt = i;
                    bestDifference = difference;
                }
            }
        }
        if (splitAt < 0) {
            return [fitText(dc, value, font, maxWidth)];
        }
        return [value.substring(0, splitAt), value.substring(splitAt + 1, value.length())];
    }

    function load100(value as Number) as String {
        var whole = value / 100;
        var fraction = value % 100;
        if (fraction == 0) {
            return whole.toString();
        }
        if (fraction % 10 == 0) {
            return whole.toString() + "." + (fraction / 10).toString();
        }
        return whole.toString() + "." + (fraction < 10 ? "0" : "") + fraction.toString();
    }

    function exercise(session as Dictionary, entryId as String) as Dictionary? {
        var index = SessionLogic.exerciseIndex(session, entryId);
        return index < 0 ? null : (session["exercises"] as Array)[index] as Dictionary;
    }

    function progress(exercise as Dictionary) as String {
        var done = SessionLogic.completedCount(exercise);
        var planned = exercise["plannedSetCount"] as Number;
        var suffix = Model.sameString(SessionLogic.exerciseStatus(exercise), "closed") ? " closed" : "";
        return done.toString() + "/" + planned.toString() + suffix;
    }

    // "1 set", "12 sets".
    function plural(count as Number, noun as String) as String {
        return count.toString() + " " + noun + (count == 1 ? "" : "s");
    }

    // Numbers on the finish review screen: workout time so far, sets done and exercises with at
    // least one set done.
    function reviewStats(session as Dictionary, now as Number) as Dictionary {
        var exercises = session["exercises"] as Array;
        var worked = 0;
        for (var i = 0; i < exercises.size(); i++) {
            if (SessionLogic.completedCount(exercises[i] as Dictionary) > 0) {
                worked++;
            }
        }
        return {
            "elapsedSec" => WorkoutClock.elapsed(session, now),
            "sets" => SessionLogic.totals(session)["done"],
            "exercises" => worked
        };
    }

    // "m:ss" (minutes capped at 99).
    function clockText(seconds as Number) as String {
        var total = seconds < 0 ? 0 : (seconds > 5999 ? 5999 : seconds);
        return (total / 60).toString() + ":" + (total % 60 < 10 ? "0" : "") + (total % 60).toString();
    }

    // "+m:ss" counting up once the rest has run out and is still waiting for the next set.
    function restOvertime(session as Dictionary) as String? {
        var rest = session["rest"];
        if (!(rest instanceof Dictionary) || !Model.sameString(rest["state"], "expired")) {
            return null;
        }
        return "+" + clockText(RestClock.overtime(rest as Dictionary, Time.now().value()));
    }

    // Rest line with the clock icon for overtime (green); returns the next y.
    function drawRestLine(dc as Dc, session as Dictionary, y as Number,
                          font as Graphics.FontType) as Number {
        var running = restStatus(session);
        var over = running == null ? restOvertime(session) : null;
        if (running == null && over == null) {
            return y;
        }
        if (over == null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            return drawLine(dc, running as String, y, font) + 3;
        }
        var s = Icons.unit(dc);
        var width = dc.getTextWidthInPixels(over as String, font);
        var height = dc.getFontHeight(font);
        Icons.clock(dc, dc.getWidth() / 2 - width / 2 - s * 2, y + height / 2, s, Graphics.COLOR_GREEN);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        return drawLine(dc, over as String, y, font) + 3;
    }

    // Confirmation after logging: "Set 2 · 65 kg × 8", "Warmup 1 · …".
    function confirmText(exercise as Dictionary, slot as Number) as String? {
        var found = Model.slotAt(exercise, slot);
        var done = found == null ? null : (found as Dictionary)["completed"];
        if (!(done instanceof Dictionary)) {
            return null;
        }
        var label = slot >= Model.WARMUP_BASE ? "Warmup " + (slot - Model.WARMUP_BASE + 1).toString() :
            "Set " + (slot + 1).toString();
        var type = exercise["loadType"];
        var value = Model.sameString(type, "timed") ? done["durationSec"].toString() + " s" :
            (Model.sameString(type, "bodyweight") ? "BW × " + done["reps"].toString() :
                load100(done["load100"] as Number) + " kg × " + done["reps"].toString());
        return label + " · " + value;
    }

    function restStatus(session as Dictionary) as String? {
        var rest = session["rest"];
        if (!(rest instanceof Dictionary)) {
            return null;
        }
        if (!Model.sameString(rest["state"], "running")) {
            return null;
        }
        var seconds = RestClock.remaining(rest as Dictionary, Time.now().value());
        var minutes = seconds / 60;
        var remainder = seconds % 60;
        return "REST " + minutes.toString() + ":" +
            (remainder < 10 ? "0" : "") + remainder.toString();
    }

    function draftLine(exercise as Dictionary, slotIndex as Number) as String {
        var draft = (Model.slotAt(exercise, slotIndex) as Dictionary)["draft"] as Dictionary;
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight")) {
            return load100(draft["load100"] as Number) + " kg × " + draft["reps"].toString();
        }
        if (Model.sameString(type, "assistance")) {
            return load100(draft["load100"] as Number) + " kg assist × " + draft["reps"].toString();
        }
        if (Model.sameString(type, "bodyweight")) {
            return "Bodyweight × " + draft["reps"].toString();
        }
        return draft["durationSec"].toString() + " sec";
    }

    // "8–10" when the plan gave a rep range for this set, else null.
    function repRange(exercise as Dictionary, slotIndex as Number) as String? {
        var plans = exercise["planTargets"];
        if (!(plans instanceof Array) || slotIndex < 0 || slotIndex >= (plans as Array).size()) {
            return null;
        }
        var target = (plans as Array)[slotIndex] as Dictionary;
        return target["minReps"] instanceof Number && target["reps"] instanceof Number ?
            target["minReps"].toString() + "–" + target["reps"].toString() : null;
    }

    // "Next: <name> <load> × <reps>" for the open set that follows the running rest.
    function nextUpLine(session as Dictionary) as String? {
        var rest = session["rest"];
        if (!(rest instanceof Dictionary)) {
            return null;
        }
        var next = SessionLogic.nextUp(session, (rest as Dictionary)["entryId"] as String);
        if (next == null) {
            return null;
        }
        var target = exercise(session, (next as Dictionary)["entryId"] as String) as Dictionary;
        var name = target["name"] as String;
        if (name.length() > 16) {
            name = name.substring(0, 14) + "..";
        }
        return "Next: " + name + " " + draftLine(target, (next as Dictionary)["slot"] as Number);
    }

    function targetLine(exercise as Dictionary, slotIndex as Number) as String? {
        if (slotIndex >= Model.WARMUP_BASE) {
            return null;
        }
        var plans = exercise["planTargets"];
        if (plans instanceof Array && slotIndex >= 0 && slotIndex < (plans as Array).size()) {
            var target = (plans as Array)[slotIndex] as Dictionary;
            if (Model.sameString(exercise["loadType"], "timed")) {
                return null;
            }
            var draft = ((exercise["slots"] as Array)[slotIndex] as Dictionary)["draft"] as Dictionary;
            var reps = target["reps"];
            var load = target["load100"];
            if (draft["reps"] == reps && draft["load100"] == load) {
                return null;
            }
            if (Model.sameString(exercise["loadType"], "weight") && load instanceof Number) {
                return "PLAN " + load100(load as Number) + " kg × " + reps.toString();
            }
            if (Model.sameString(exercise["loadType"], "assistance") && load instanceof Number) {
                return "PLAN " + load100(load as Number) + " kg assist × " + reps.toString();
            }
            return "PLAN " + reps.toString() + " reps";
        }
        var minimum = exercise["targetRepsMin"];
        var maximum = exercise["targetRepsMax"];
        if (Model.sameString(exercise["loadType"], "timed") || !(minimum instanceof Number) ||
            !(maximum instanceof Number)) {
            return null;
        }
        var draft = ((exercise["slots"] as Array)[slotIndex] as Dictionary)["draft"] as Dictionary;
        if (minimum == maximum) {
            return draft["reps"] == minimum ? null : "target " + minimum.toString();
        }
        return "target " + minimum.toString() + "–" + maximum.toString();
    }

    function lastLine(exercise as Dictionary, slotIndex as Number) as String? {
        if (slotIndex >= Model.WARMUP_BASE) {
            return null;
        }
        var last = exercise["last"];
        if (!(last instanceof Dictionary) || !(last["sets"] instanceof Array)) {
            return null;
        }
        var sets = last["sets"] as Array;
        var selected = null;
        for (var i = 0; i < sets.size(); i++) {
            var tuple = sets[i] as Array;
            selected = tuple;
            if (tuple[0] == slotIndex) {
                break;
            }
        }
        if (selected == null) {
            return null;
        }
        var values = selected as Array;
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight")) {
            return "LAST " + load100(values[1] as Number) + " kg × " + values[2].toString();
        }
        if (Model.sameString(type, "assistance")) {
            return "LAST " + load100(values[1] as Number) + " kg assist × " + values[2].toString();
        }
        if (Model.sameString(type, "bodyweight")) {
            return "LAST bodyweight × " + values[2].toString();
        }
        return "LAST " + values[3].toString() + " sec";
    }

    // The most recently logged slot number (a warmup slot is WARMUP_BASE + index), or -1.
    function lastSlot(exercise as Dictionary) as Number {
        var slots = exercise["slots"] as Array;
        var last = -1;
        var sequence = -1;
        for (var i = 0; i < slots.size(); i++) {
            var completed = slots[i]["completed"];
            if (completed != null && completed["sequence"] > sequence) {
                sequence = completed["sequence"];
                last = i;
            }
        }
        var warmups = exercise["warmupSlots"];
        for (var i = 0; warmups instanceof Array && i < (warmups as Array).size(); i++) {
            var completed = (warmups as Array)[i]["completed"];
            if (completed != null && completed["sequence"] > sequence) {
                sequence = completed["sequence"];
                last = Model.WARMUP_BASE + i;
            }
        }
        return last;
    }

    // "3" for working set 3, "W2" for the second warmup.
    function slotLabel(slot as Number) as String {
        return slot >= Model.WARMUP_BASE ? "W" + (slot - Model.WARMUP_BASE + 1).toString() :
            (slot + 1).toString();
    }
}
