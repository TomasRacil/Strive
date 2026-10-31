using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application as App;
using Toybox.Lang;

// What the session added up to, shown once the workout is finished.
//
// It also shows whether the log reached the phone. That line is the only
// honest signal that the sync worked: the BLE write is queued and acked in the
// background, so a summary that claims "synced" without checking would be a
// guess.
class SummaryView extends Ui.View {

    var summary;

    function initialize(data) {
        View.initialize();
        summary = data;
    }

    function clockText(seconds) {
        var minutes = seconds / 60;
        var secs = seconds % 60;
        var pad = secs < 10 ? "0" : "";
        return minutes.toString() + ":" + pad + secs.toString();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.10, Gfx.FONT_SMALL, "Session done", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.26, Gfx.FONT_LARGE, summary[:sets].toString(), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.38, Gfx.FONT_XTINY, "sets", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.48, Gfx.FONT_MEDIUM, summary[:volume].format("%.0f") + " kg", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.60, Gfx.FONT_TINY, clockText(summary[:duration]), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.74, Gfx.FONT_XTINY, "sync " + syncText(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height * 0.83, Gfx.FONT_XTINY, "BACK to close", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function syncText() as Lang.String {
        var text = App.Storage.getValue("ble_status");
        if (text == null) {
            return "-";
        }
        return text.toString();
    }
}

// BACK is deliberately not intercepted here either: the summary is a dead end
// otherwise, and the system's own back-out is the one behaviour every watch
// user already knows.
class SummaryDelegate extends Ui.InputDelegate {

    function initialize() {
        InputDelegate.initialize();
    }

    function onKey(evt) {
        if (evt.getKey() == Ui.KEY_ENTER) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    function onSwipe(evt) {
        if (evt.getDirection() == Ui.SWIPE_RIGHT) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return true;
        }
        return false;
    }
}
