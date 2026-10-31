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
    const ANGLE_MENU = 153;  // hold UP; drawn just above the UP marker

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

    // Marker at a physical button: "play", "stop", "check", "back", "up", "down" or "menu".
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

    // One dot per working set: done green, the current one white, the rest gray outlines.
    function setDots(dc as Dc, y as Number, done as Number, planned as Number, current as Number) as Void {
        var s = unit(dc);
        var r = s < 3 ? 4 : s + 1;
        var gap = r * 3;
        var x = dc.getWidth() / 2 - (planned - 1) * gap / 2;
        for (var i = 0; i < planned; i++) {
            if (i < done && i != current) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
                dc.fillCircle(x, y, r);
            } else if (i == current) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.fillCircle(x, y, r);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, r - 1);
                dc.setPenWidth(1);
            }
            x += gap;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    function menuMarker(dc as Dc) as Void {
        edge(dc, "menu", ANGLE_MENU);
    }
}
