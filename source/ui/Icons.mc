import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Icons drawn with Dc primitives (system-font glyph coverage on the FR965 is unverified).
// White, yellow, green and red (heart) on black only. Button angles come from the fr965 simulator layout:
// degrees counter-clockwise from 3 o'clock, measured from the screen centre to the key.
module Icons {
    const ANGLE_START = 25;
    const ANGLE_BACK = 335;
    const ANGLE_UP = 180;
    const ANGLE_DOWN = 210;
    const ANGLE_MENU = 153;  // former hold-UP position (next to LIGHT); kept for reference
    const ANGLE_HOLD = 172;  // hold UP: beside the UP button, inside its arrow

    function unit(dc as Dc) as Number {
        return dc.getFontHeight(Graphics.FONT_XTINY) / 4;
    }

    function check(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 3 + 1);
        dc.drawLine(x - s, y, x - s / 3, y + s * 2 / 3);
        dc.drawLine(x - s / 3, y + s * 2 / 3, x + s, y - s * 2 / 3);
        dc.setPenWidth(1);
    }

    function cross(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 3 + 1);
        dc.drawLine(x - s, y - s, x + s, y + s);
        dc.drawLine(x - s, y + s, x + s, y - s);
        dc.setPenWidth(1);
    }

    function clock(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 4 + 1);
        dc.drawCircle(x, y, s);
        dc.drawLine(x, y, x, y - s * 2 / 3);
        dc.drawLine(x, y, x + s / 2, y);
        dc.setPenWidth(1);
    }

    function play(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillPolygon([[x - s / 2, y - s], [x - s / 2, y + s], [x + s, y]]);
    }

    function stop(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillRectangle(x - s * 2 / 3, y - s * 2 / 3, s * 4 / 3, s * 4 / 3);
    }

    // Arrow along the vertical axis: up = true points up (upload), false points down.
    function arrow(dc as Dc, x as Number, y as Number, s as Number, up as Boolean, color as Number) as Void {
        var d = up ? -1 : 1;
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 3 + 1);
        dc.drawLine(x, y + d * s, x, y - d * s / 3);
        dc.setPenWidth(1);
        dc.fillPolygon([[x - s, y - d * s / 3], [x + s, y - d * s / 3], [x, y - d * s]]);
    }

    // Chevron pointing up, down or left.
    function chevron(dc as Dc, x as Number, y as Number, s as Number, dir as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 3 + 1);
        if (dir == 0) {
            dc.drawLine(x - s, y + s / 2, x, y - s / 2);
            dc.drawLine(x, y - s / 2, x + s, y + s / 2);
        } else if (dir == 1) {
            dc.drawLine(x - s, y - s / 2, x, y + s / 2);
            dc.drawLine(x, y + s / 2, x + s, y - s / 2);
        } else {
            dc.drawLine(x + s / 2, y - s, x - s / 2, y);
            dc.drawLine(x - s / 2, y, x + s / 2, y + s);
        }
        dc.setPenWidth(1);
    }

    function dots(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(x - s, y, s / 3 + 1);
        dc.fillCircle(x, y, s / 3 + 1);
        dc.fillCircle(x + s, y, s / 3 + 1);
    }

    function plus(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(s / 3 + 1);
        dc.drawLine(x - s, y, x + s, y);
        dc.drawLine(x, y - s, x, y + s);
        dc.setPenWidth(1);
    }

    // Small dumbbell: a handle between two plates, each a tall inner plate and a shorter outer one.
    // Half width is about 1.6 s, so it fits the hold-UP ring (radius 2.5 s) with a clear margin.
    function dumbbell(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_BLACK);
        var pw = s / 2 < 2 ? 2 : s / 2;
        var inner = s / 2 + 1;
        var tall = s * 5 / 4;
        var shortHalf = s * 3 / 4;
        dc.setPenWidth(s / 3 + 1);
        dc.drawLine(x - inner - pw, y, x + inner + pw, y);
        dc.setPenWidth(1);
        dc.fillRectangle(x - inner - pw, y - tall, pw, tall * 2);
        dc.fillRectangle(x + inner, y - tall, pw, tall * 2);
        dc.fillRectangle(x - inner - pw * 2 - 1, y - shortHalf, pw, shortHalf * 2);
        dc.fillRectangle(x + inner + pw + 1, y - shortHalf, pw, shortHalf * 2);
    }

    // Marker at a physical button: "play", "stop", "check", "back", "up", "down", "plus" or "menu".
    function edge(dc as Dc, kind as String, angle as Number) as Void {
        var s = unit(dc);
        var radius = (dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight()) / 2 - s * 2;
        var radians = angle * Math.PI / 180.0;
        var x = dc.getWidth() / 2 + (radius * Math.cos(radians)).toNumber();
        var y = dc.getHeight() / 2 - (radius * Math.sin(radians)).toNumber();
        if (Model.sameString(kind, "play")) {
            play(dc, x, y, s, Graphics.COLOR_GREEN);
        } else if (Model.sameString(kind, "stop")) {
            stop(dc, x, y, s, Graphics.COLOR_GREEN);
        } else if (Model.sameString(kind, "check")) {
            check(dc, x, y, s, Graphics.COLOR_GREEN);
        } else if (Model.sameString(kind, "back")) {
            chevron(dc, x, y, s, 2, Graphics.COLOR_WHITE);
        } else if (Model.sameString(kind, "up")) {
            chevron(dc, x, y, s, 0, Graphics.COLOR_WHITE);
        } else if (Model.sameString(kind, "down")) {
            chevron(dc, x, y, s, 1, Graphics.COLOR_WHITE);
        } else if (Model.sameString(kind, "plus")) {
            plus(dc, x, y, s, Graphics.COLOR_WHITE);
        } else {
            dots(dc, x, y, s, Graphics.COLOR_WHITE);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    function startMarker(dc as Dc, kind as String) as Void {
        edge(dc, kind, ANGLE_START);
    }

    function backMarker(dc as Dc) as Void {
        edge(dc, "back", ANGLE_BACK);
    }

    function browseMarkers(dc as Dc) as Void {
        edge(dc, "up", ANGLE_UP);
        edge(dc, "down", ANGLE_DOWN);
    }

    // UP/DOWN chevrons in yellow: on the set screen they always change the highlighted value.
    function focusMarkers(dc as Dc) as Void {
        var s = unit(dc);
        var radius = (dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight()) / 2 - s * 2;
        var angles = [ANGLE_UP, ANGLE_DOWN];
        for (var i = 0; i < 2; i++) {
            var radians = (angles[i] as Number) * Math.PI / 180.0;
            var x = dc.getWidth() / 2 + (radius * Math.cos(radians)).toNumber();
            var y = dc.getHeight() / 2 - (radius * Math.sin(radians)).toNumber();
            chevron(dc, x, y, s, i, Graphics.COLOR_YELLOW);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    // Heart for the HR readout: two circles and a triangle.
    function heart(dc as Dc, x as Number, y as Number, s as Number) as Void {
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        var r = s * 3 / 4 + 2;
        dc.fillCircle(x - r + 1, y - r / 2, r);
        dc.fillCircle(x + r - 1, y - r / 2, r);
        dc.fillPolygon([[x - 2 * r, y - r / 3], [x + 2 * r, y - r / 3], [x, y + 2 * r - 1]]);
    }

    // Width the dots row may use at height y: the chord of the round screen, kept clear of the
    // hold-UP ring beside the UP button (the widest of the edge icons at this height).
    function dotsWidth(dc as Dc, y as Number, radius as Number) as Number {
        var s = unit(dc);
        var screen = (dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight()) / 2;
        var dy = (y - dc.getHeight() / 2).abs() + radius + DotsLogic.RING;
        var chordHalf = Math.sqrt((screen * screen - dy * dy).toFloat()).toNumber() - s * 2;
        var ringInner = ((screen - s * 6) * Math.cos(ANGLE_HOLD * Math.PI / 180.0)).abs().toNumber() - (s * 5 / 2 + 2) - 3;
        var half = chordHalf < ringInner ? chordHalf : ringInner;
        return half < 0 ? 0 : 2 * half;
    }

    // The set-progress row: one dot per warmup (smaller, gray: done filled gray, the current one
    // filled white, open a gray outline), then one per working set (done green, the current one
    // white with a ring, open a light-gray thick outline). `current` is the slot up next
    // (Model.WARMUP_BASE + i for a warmup, -1 none). Long rows shrink their gap, then the dots.
    function setProgress(dc as Dc, y as Number, warmups as Number, doneWarmups as Number, planned as Number,
                         doneSets as Number, current as Number) as Void {
        var r0 = unit(dc) + 3;
        var kinds = DotsLogic.kinds(warmups, doneWarmups, planned, doneSets, current);
        var box = DotsLogic.layout(warmups, planned, dotsWidth(dc, y, r0), r0);
        var r = box["radius"] as Number;
        var rw = box["warmRadius"] as Number;
        var gap = box["gap"] as Number;
        var x = dc.getWidth() / 2 - (box["width"] as Number) / 2;
        for (var i = 0; i < kinds.size(); i++) {
            var kind = kinds[i];
            var warm = kind <= DotsLogic.WARM_OPEN;
            var d = warm ? rw : r;
            x += d;
            if (kind == DotsLogic.WARM_DONE) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
                dc.fillCircle(x, y, d);
            } else if (kind == DotsLogic.WARM_CURRENT) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.fillCircle(x, y, d);
            } else if (kind == DotsLogic.WARM_OPEN) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
                dc.drawCircle(x, y, d - 1);
            } else if (kind == DotsLogic.SET_CURRENT) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, d + 2);
                dc.setPenWidth(1);
                dc.fillCircle(x, y, d - 1);
            } else if (kind == DotsLogic.SET_DONE) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
                dc.fillCircle(x, y, d);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
                dc.setPenWidth(3);
                dc.drawCircle(x, y, d - 1);
                dc.setPenWidth(1);
            }
            x += d + gap;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    // Hold-UP action, drawn beside the UP button just inside its arrow: the icon in a ring with a
    // gap, like a press still filling up, which reads as "hold".
    function holdMarker(dc as Dc, kind as String) as Void {
        var s = unit(dc);
        var radius = (dc.getWidth() < dc.getHeight() ? dc.getWidth() : dc.getHeight()) / 2 - s * 6;
        var radians = ANGLE_HOLD * Math.PI / 180.0;
        var x = dc.getWidth() / 2 + (radius * Math.cos(radians)).toNumber();
        var y = dc.getHeight() / 2 - (radius * Math.sin(radians)).toNumber();
        var ring = s * 5 / 2 + 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        // 300 degrees counter-clockwise from 1 o'clock: a ring with a gap at the top right.
        dc.drawArc(x, y, ring, Graphics.ARC_COUNTER_CLOCKWISE, 60, 0);
        dc.setPenWidth(1);
        if (Model.sameString(kind, "plus")) {
            plus(dc, x, y, s, Graphics.COLOR_WHITE);
        } else if (Model.sameString(kind, "weight")) {
            dumbbell(dc, x, y, s, Graphics.COLOR_WHITE);
        } else if (Model.sameString(kind, "time")) {
            clock(dc, x, y, s * 5 / 4, Graphics.COLOR_WHITE);
        } else {
            dots(dc, x, y, s, Graphics.COLOR_WHITE);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    // Hold UP on a workout set screen: a dumbbell (Change weight) or a clock (Change time).
    function loadMarker(dc as Dc, action as String) as Void {
        holdMarker(dc, Model.sameString(action, "time") ? "time" : "weight");
    }

    function menuMarker(dc as Dc) as Void {
        holdMarker(dc, "menu");
    }

    // Hold UP adds a set (Overview).
    function addMarker(dc as Dc) as Void {
        holdMarker(dc, "plus");
    }
}
