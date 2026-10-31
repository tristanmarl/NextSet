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
        // Title, sets, the workout time big, heart rate, and one status row: a check per part
        // when all is well, words only for a problem.
        var current = session as Dictionary;
        var totals = SessionLogic.totals(current);
        var h = dc.getHeight();
        var complete = Model.sameString(_outcome, "completed");
        UiFormat.drawTitle(dc, complete ? "Saved" : "Cancelled", h * 25 / 100);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, h * 39 / 100, Graphics.FONT_SMALL,
            totals["done"].toString() + "/" + totals["planned"].toString() + " sets",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (current["elapsedSec"] instanceof Number) {
            UiFormat.drawBig(dc, [[UiFormat.clockText(current["elapsedSec"] as Number), "num"]],
                h * 55 / 100, -1, Graphics.COLOR_WHITE);
        }
        var hr = getApp().hrStats(current["id"]);
        var caption = UiFormat.captionFont();
        if (hr != null) {
            var text = (hr as Array)[0].toString() + " avg · " + (hr as Array)[1].toString() + " max";
            var s = Icons.unit(dc);
            var width = dc.getTextWidthInPixels(text, caption);
            Icons.heart(dc, (dc.getWidth() - width) / 2 - s * 3, h * 70 / 100, s);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, h * 70 / 100, caption, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        drawStatus(dc, current, h * 81 / 100, caption);
        // START exits, or opens the retry choice for an unresolved Garmin activity.
        Icons.startMarker(dc, hasUnresolvedActivity() ? "play" : "check");
    }

    // "✓ Garmin  ✓ Liftosaur" when both are fine; otherwise the first problem in words (red).
    private function drawStatus(dc as Dc, session as Dictionary, y as Number,
                                font as Graphics.FontType) as Void {
        var fit = session["fitState"];
        var garminOk = Model.sameString(fit, "saved") || Model.sameString(fit, "segment_saved");
        var unknown = session["fitUnknownSegments"];
        var problem = null;
        if (!garminOk) {
            problem = activityLabel(fit);
        } else if (unknown instanceof Number && unknown > 0) {
            problem = "One Garmin part unknown";
        }
        var upload = getApp().controller().uploadSummary();
        var uploadIcon = upload == null ? null : (upload as Dictionary)["icon"] as String;
        if (problem == null && uploadIcon != null && Model.sameString(uploadIcon, "cross")) {
            problem = (upload as Dictionary)["text"] as String;
        }
        if (problem != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, y, font, problem as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            return;
        }
        var s = Icons.unit(dc);
        var left = "Garmin";
        var right = upload == null ? null : "Liftosaur";
        var gap = s * 4;
        var leftWidth = s * 3 + dc.getTextWidthInPixels(left, font);
        var rightWidth = right == null ? 0 : s * 3 + dc.getTextWidthInPixels(right as String, font);
        var x = (dc.getWidth() - leftWidth - (right == null ? 0 : gap + rightWidth)) / 2;
        Icons.check(dc, x + s, y, s, Graphics.COLOR_GREEN);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(x + s * 3, y, font, left, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (right != null) {
            x += leftWidth + gap;
            drawUploadIcon(dc, uploadIcon as String, x + s, y);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(x + s * 3, y, font, right as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    // Liftosaur upload state: check (uploaded), arrow (uploading), clock (waiting).
    private function drawUploadIcon(dc as Dc, icon as String, x as Number, y as Number) as Void {
        var s = Icons.unit(dc);
        if (Model.sameString(icon, "check")) {
            Icons.check(dc, x, y, s, Graphics.COLOR_GREEN);
        } else if (Model.sameString(icon, "arrow")) {
            Icons.arrow(dc, x, y, s, true, Graphics.COLOR_WHITE);
        } else {
            Icons.clock(dc, x, y, s, Graphics.COLOR_WHITE);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    private function activityLabel(fitState as Object?) as String {
        if (Model.sameString(fitState, "saved") || Model.sameString(fitState, "segment_saved")) {
            return "Garmin activity saved";
        }
        if (Model.sameString(fitState, "failed")) {
            return "Garmin activity failed";
        }
        if (Model.sameString(fitState, "unknown")) {
            return "Garmin activity unknown";
        }
        return "Garmin activity not saved";
    }

    private function hasUnresolvedActivity() as Boolean {
        var session = getApp().controller().session();
        return session != null && (Model.sameString((session as Dictionary)["fitState"], "failed") ||
            Model.sameString((session as Dictionary)["fitState"], "unknown"));
    }
}

class SummaryDelegate extends KeyDelegate {
    public function initialize() {
        KeyDelegate.initialize();
    }

    public function onStartKey() as Boolean {
        var session = getApp().controller().session();
        if (session != null && (Model.sameString((session as Dictionary)["fitState"], "failed") ||
            Model.sameString((session as Dictionary)["fitState"], "unknown"))) {
            Navigator.activityResultActions();
        } else {
            Navigator.exitApp();
        }
        return true;
    }

    public function onBackKey() as Boolean {
        return onStartKey();
    }
}
