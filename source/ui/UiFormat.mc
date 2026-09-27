import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

module UiFormat {
    var _captionFont as Graphics.FontType? = null;

    function captionFont() as Graphics.FontType {
        if (_captionFont == null) {
            _captionFont = Graphics.getVectorFont({:font => Graphics.FONT_XTINY, :scale => 0.75});
            if (_captionFont == null) {
                _captionFont = Graphics.FONT_XTINY;
            }
        }
        return _captionFont as Graphics.FontType;
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

    function restStatus(session as Dictionary) as String? {
        var rest = session["rest"];
        if (!(rest instanceof Dictionary)) {
            return null;
        }
        if (Model.sameString(rest["state"], "expired")) {
            return "Rest finished";
        }
        var paused = Model.sameString(rest["state"], "paused");
        if (!paused && !Model.sameString(rest["state"], "running")) {
            return null;
        }
        var seconds = RestClock.remaining(rest as Dictionary, Time.now().value());
        var minutes = seconds / 60;
        var remainder = seconds % 60;
        return (paused ? "REST PAUSED " : "REST ") + minutes.toString() + ":" +
            (remainder < 10 ? "0" : "") + remainder.toString();
    }

    function draftLine(exercise as Dictionary, slotIndex as Number) as String {
        var slots = exercise["slots"] as Array;
        var draft = slots[slotIndex]["draft"] as Dictionary;
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight")) {
            return load100(draft["load100"] as Number) + " kg  x  " + draft["reps"].toString();
        }
        if (Model.sameString(type, "assistance")) {
            return load100(draft["load100"] as Number) + " kg assist  x  " + draft["reps"].toString();
        }
        if (Model.sameString(type, "bodyweight")) {
            return "Bodyweight  x  " + draft["reps"].toString();
        }
        return draft["durationSec"].toString() + " sec";
    }

    function lastLine(exercise as Dictionary, slotIndex as Number) as String? {
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
            return "LAST " + load100(values[1] as Number) + " kg x " + values[2].toString();
        }
        if (Model.sameString(type, "assistance")) {
            return "LAST " + load100(values[1] as Number) + " kg assist x " + values[2].toString();
        }
        if (Model.sameString(type, "bodyweight")) {
            return "LAST bodyweight x " + values[2].toString();
        }
        return "LAST " + values[3].toString() + " sec";
    }

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
        return last;
    }
}
