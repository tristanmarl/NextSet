import Toybox.Lang;
import Toybox.WatchUi;

// Base of the key-only delegates (review, discard and other destructive confirmations). Actions
// come ONLY from physical key events (onKey -> onXxxKey); every touch callback is consumed, so a
// tap, swipe or water on the screen can never save, discard or delete anything. This is an
// InputDelegate, not a BehaviorDelegate: on a BehaviorDelegate the firmware turns taps into
// onSelect and the buttons into behaviours (onPreviousPage, ...) that never reach onKey.
// Hold UP arrives as KEY_MENU (onMenuKey); there is no simulator long-press emulation here.
// Subclasses override the onXxxKey methods only.
class KeyDelegate extends WatchUi.InputDelegate {
    public function initialize() {
        InputDelegate.initialize();
    }

    // One press = one action: DOWN/UP edge events of the same press are ignored, the action
    // event (or an untyped event) dispatches. LIGHT and other keys are left to the firmware.
    public function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        var type = keyEvent.getType();
        var handled = key == WatchUi.KEY_ENTER || key == WatchUi.KEY_ESC ||
            key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN || key == WatchUi.KEY_MENU;
        if (!handled) {
            return false;
        }
        if (type == WatchUi.PRESS_TYPE_DOWN || type == WatchUi.PRESS_TYPE_UP) {
            return true;
        }
        if (key == WatchUi.KEY_ENTER) {
            return onStartKey();
        } else if (key == WatchUi.KEY_ESC) {
            return onBackKey();
        } else if (key == WatchUi.KEY_UP) {
            return onUpKey();
        } else if (key == WatchUi.KEY_DOWN) {
            return onDownKey();
        }
        return onMenuKey();
    }

    // Overridable key actions; the default consumes the key and does nothing.
    public function onStartKey() as Boolean {
        return true;
    }

    public function onBackKey() as Boolean {
        return true;
    }

    public function onUpKey() as Boolean {
        return true;
    }

    public function onDownKey() as Boolean {
        return true;
    }

    public function onMenuKey() as Boolean {
        return true;
    }

    public function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    public function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    public function onFlick(flickEvent as WatchUi.FlickEvent) as Boolean {
        return true;
    }

    public function onDrag(dragEvent as WatchUi.DragEvent) as Boolean {
        return true;
    }

    public function onHold(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    public function onRelease(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }
}
