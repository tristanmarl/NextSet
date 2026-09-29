import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class SummaryView extends WatchUi.View {
    private var _outcome as String;

    public function initialize(outcome as String) {
        _outcome = outcome;
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var totals = SessionLogic.totals(session as Dictionary);
        var complete = Model.sameString(_outcome, "completed");
        var full = Model.sameString((session as Dictionary)["completionKind"], "full");
        var title = complete ? (full ? "NextSet log saved" : "Partial NextSet log") :
            "Workout ended";
        var lines = [title, totals["done"].toString() + "/" +
            totals["planned"].toString() + " sets"];
        var fonts = [Graphics.FONT_SMALL, Graphics.FONT_LARGE];
        var gaps = [8, 8];
        var caption = UiFormat.captionFont();
        if (session["elapsedSec"] instanceof Number && session["activeSec"] instanceof Number) {
            lines.add("ELAPSED " + duration(session["elapsedSec"] as Number));
            fonts.add(caption);
            gaps.add(4);
            lines.add("ACTIVE " + duration(session["activeSec"] as Number));
            fonts.add(caption);
            gaps.add(8);
        }
        lines.add(activityLabel(session["fitState"]));
        fonts.add(caption);
        gaps.add(5);
        var segments = session["fitSegments"];
        if (segments instanceof Number && segments > 1) {
            lines.add(segments.toString() + " GARMIN SEGMENTS");
            fonts.add(caption);
            gaps.add(5);
        }
        var unknown = session["fitUnknownSegments"];
        if (unknown instanceof Number && unknown > 0) {
            lines.add("PRIOR SEGMENT UNKNOWN");
            fonts.add(caption);
            gaps.add(5);
        }
        lines.add(hasUnresolvedActivity() ? "START: SAVE CHOICE" : "START: EXIT");
        fonts.add(Graphics.FONT_XTINY);
        gaps.add(0);
        var totalHeight = 0;
        for (var i = 0; i < lines.size(); i++) {
            totalHeight += dc.getFontHeight(fonts[i] as Graphics.FontType) +
                (gaps[i] as Number);
        }
        var y = (dc.getHeight() - totalHeight) / 2;
        for (var i = 0; i < lines.size(); i++) {
            y = UiFormat.drawLine(dc, lines[i] as String, y,
                fonts[i] as Graphics.FontType) + (gaps[i] as Number);
        }
    }

    private function activityLabel(fitState as Object?) as String {
        if (Model.sameString(fitState, "saved") || Model.sameString(fitState, "segment_saved")) {
            return "GARMIN ACTIVITY SAVED";
        }
        if (Model.sameString(fitState, "failed")) {
            return "GARMIN ACTIVITY FAILED";
        }
        if (Model.sameString(fitState, "unknown")) {
            return "GARMIN ACTIVITY UNKNOWN";
        }
        return "GARMIN ACTIVITY NOT SAVED";
    }

    private function hasUnresolvedActivity() as Boolean {
        var session = getApp().controller().session();
        return session != null && (Model.sameString((session as Dictionary)["fitState"], "failed") ||
            Model.sameString((session as Dictionary)["fitState"], "unknown"));
    }

    private function duration(totalSeconds as Number) as String {
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.toString() + ":" + (seconds < 10 ? "0" : "") + seconds.toString();
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        var session = getApp().controller().session();
        if (session != null && (Model.sameString((session as Dictionary)["fitState"], "failed") ||
            Model.sameString((session as Dictionary)["fitState"], "unknown"))) {
            Navigator.activityResultActions();
        } else {
            Navigator.exitApp();
        }
        return true;
    }

    public function onBack() as Boolean {
        onSelect();
        return true;
    }
}
