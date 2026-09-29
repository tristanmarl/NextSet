import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class OverviewView extends WatchUi.View {
    private var _selectedIndex as Number = 0;
    private var _seenNextSetSequence as Number = 0;

    public function initialize() {
        View.initialize();
        var session = getApp().controller().session();
        if (session != null) {
            var current = session as Dictionary;
            if (current["nextSetSequence"] instanceof Number) {
                _seenNextSetSequence = current["nextSetSequence"] as Number;
            }
            var exercises = (session as Dictionary)["exercises"] as Array;
            for (var i = 0; i < exercises.size(); i++) {
                if (SessionLogic.nextSlot(exercises[i] as Dictionary) >= 0) {
                    _selectedIndex = i;
                    break;
                }
            }
        }
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL,
                "No active workout", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var current = session as Dictionary;
        var exercises = current["exercises"] as Array;
        if (exercises.size() == 0) {
            return;
        }
        if (current["nextSetSequence"] instanceof Number &&
            current["nextSetSequence"] != _seenNextSetSequence) {
            _seenNextSetSequence = current["nextSetSequence"] as Number;
            if (SessionLogic.nextSlot(exercises[_selectedIndex] as Dictionary) < 0) {
                for (var offset = 1; offset <= exercises.size(); offset++) {
                    var candidateIndex = (_selectedIndex + offset) % exercises.size();
                    if (SessionLogic.nextSlot(exercises[candidateIndex] as Dictionary) >= 0) {
                        _selectedIndex = candidateIndex;
                        break;
                    }
                }
            }
        }
        if (_selectedIndex >= exercises.size()) {
            _selectedIndex = 0;
        }
        var focused = exercises[_selectedIndex] as Dictionary;
        var focusTitle = focused["name"] as String;
        var titleFont = Graphics.FONT_SMALL;
        var countFont = Graphics.FONT_LARGE;
        var gap = 8;
        var footerFont = UiFormat.captionFont();
        var footerHeight = dc.getFontHeight(footerFont) + 2;
        var nextSlot = SessionLogic.nextSlot(focused);
        var restStatus = UiFormat.restStatus(current);
        // Rows below the count: next target (optional), progress, rest (optional), browse hint.
        var rows = 2 + (nextSlot >= 0 ? 1 : 0);
        var blockHeight = dc.getFontHeight(titleFont) + gap + dc.getFontHeight(countFont) + 3 +
            rows * footerHeight + (restStatus != null ? dc.getFontHeight(footerFont) + 4 : 0);
        var titleY = (dc.getHeight() - blockHeight) / 2;
        if (!Model.sameString(UiFormat.safeText(dc, focusTitle, titleY, titleFont), focusTitle)) {
            titleFont = Graphics.FONT_XTINY;
            blockHeight -= dc.getFontHeight(Graphics.FONT_SMALL) - dc.getFontHeight(titleFont);
            titleY = (dc.getHeight() - blockHeight) / 2;
        }
        UiFormat.drawLine(dc, focusTitle, titleY, titleFont);
        var countY = titleY + dc.getFontHeight(titleFont) + gap;
        var count = getApp().controller().isWorkoutPaused() ? "WORKOUT PAUSED" :
            (SessionLogic.completedCount(focused).toString() + "/" +
             focused["plannedSetCount"].toString() + " sets");
        UiFormat.drawLine(dc, count, countY, countFont);
        var y = countY + dc.getFontHeight(countFont) + 3;
        if (nextSlot >= 0) {
            y = UiFormat.drawLine(dc, "Next: " + UiFormat.draftLine(focused, nextSlot), y,
                footerFont) + 2;
        }
        var totals = SessionLogic.totals(current);
        y = UiFormat.drawLine(dc, totals["done"].toString() + "/" + totals["planned"].toString() +
            " SETS", y, footerFont) + 2;
        if (restStatus != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            y = UiFormat.drawLine(dc, restStatus as String, y, footerFont) + 4;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        }
        // ponytail: plain "UP/DOWN" text instead of arrow glyphs, whose font coverage is unverified.
        UiFormat.drawLine(dc, "UP/DOWN · EX " + (_selectedIndex + 1).toString() + "/" +
            exercises.size(), y, footerFont);
    }

    public function moveSelection(direction as Number) as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var count = (session as Dictionary)["exercises"].size();
        if (count == 0) {
            return;
        }
        _selectedIndex = (_selectedIndex + direction + count) % count;
        WatchUi.requestUpdate();
    }

    public function openSelection() as Void {
        if (getApp().controller().isWorkoutPaused()) {
            Navigator.resumeWorkout();
            return;
        }
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        if (_selectedIndex < exercises.size()) {
            Navigator.exercise((exercises[_selectedIndex] as Dictionary)["entryId"] as String);
        }
    }

    public function selectedEntryId() as String? {
        var session = getApp().controller().session();
        if (session == null) {
            return null;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        return _selectedIndex < exercises.size() ?
            (exercises[_selectedIndex] as Dictionary)["entryId"] as String : null;
    }
}

class OverviewDelegate extends WatchUi.BehaviorDelegate {
    private var _view as OverviewView;

    public function initialize(view as OverviewView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_UP) {
            _view.moveSelection(-1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.moveSelection(1);
            return true;
        }
        if (key == KEY_ENTER) {
            _view.openSelection();
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        _view.openSelection();
        return true;
    }

    public function onMenu() as Boolean {
        var entryId = _view.selectedEntryId();
        if (entryId != null) {
            Navigator.actionsForOverview(entryId as String);
        } else {
            Navigator.actions();
        }
        return true;
    }

    public function onBack() as Boolean {
        return onMenu();
    }
}
