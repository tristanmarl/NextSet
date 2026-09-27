import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class OverviewView extends WatchUi.View {
    private var _selectedIndex as Number = 0;

    public function initialize() {
        View.initialize();
        var session = getApp().controller().session();
        if (session != null) {
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
        if (_selectedIndex >= exercises.size()) {
            _selectedIndex = 0;
        }
        var caption = UiFormat.captionFont();
        var totals = SessionLogic.totals(current);
        var y = UiFormat.drawLine(dc, current["templateName"] + " " +
            totals["done"].toString() + "/" + totals["planned"].toString(),
            40, Graphics.FONT_XTINY) + 8;
        var rest = UiFormat.restStatus(current);
        // Reserve the status row so rest expiry never moves the selection.
        if (rest != null) {
            UiFormat.drawLine(dc, rest as String, y, caption);
        }
        y += dc.getFontHeight(caption) + 20;

        var focused = exercises[_selectedIndex] as Dictionary;
        var focusTitle = focused["name"] as String;
        var focusFont = Graphics.FONT_TINY;
        if (UiFormat.safeText(dc, focusTitle, y, focusFont) != focusTitle) {
            focusFont = Graphics.FONT_XTINY;
        }
        y = UiFormat.drawLine(dc, focusTitle, y, focusFont) + 4;
        y = UiFormat.drawLine(dc, UiFormat.progress(focused), y, Graphics.FONT_XTINY) + 14;
        if (exercises.size() > 1) {
            var above = (_selectedIndex + exercises.size() - 1) % exercises.size();
            var below = (_selectedIndex + 1) % exercises.size();
            y = UiFormat.drawLine(dc, "UP: " + exercises[above]["name"], y, caption) + 8;
            y = UiFormat.drawLine(dc, "DOWN: " + exercises[below]["name"], y, caption) + 16;
        }
        y = UiFormat.drawLine(dc, "START: OPEN", y, caption) + 6;
        UiFormat.drawLine(dc, "BACK: ACTIONS", y, caption);
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
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        if (_selectedIndex < exercises.size()) {
            Navigator.exercise((exercises[_selectedIndex] as Dictionary)["entryId"] as String);
        }
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
        Navigator.actions();
        return true;
    }

    public function onBack() as Boolean {
        Navigator.actions();
        return true;
    }
}
