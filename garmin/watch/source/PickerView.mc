using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Time as Time;
using Toybox.Application as App;
using Toybox.Lang;

// Pick an exercise.
//
// The first three rows are the engine's ranking - least-loaded muscles first,
// with a nudge for a lift that has not come up in a week - each showing the load
// and the sets it would ask for. The last row opens the whole library, scrolled,
// because the user may train whatever they want and the ranking is a suggestion.
//
// Two modes in one view rather than a second view: the full list is the same
// list with the filter removed, and pushing a view for it would put the BACK
// button one level deeper than the thing the user opened.
class PickerView extends Ui.View {

    const RANKED_ROWS = 3;
    const VISIBLE_ROWS = 4;

    var loop;
    var mode;
    var cursor;
    var top;

    // The ranking is the expensive part of a frame - Engine.rank walks every
    // spec against every set - so it is computed once per visit rather than
    // once per row and once per keypress. Without the cache a single DOWN
    // re-ranks the library a dozen times.
    var cachedRanked;
    var cachedAll;

    function initialize(model) {
        View.initialize();
        loop = model;
        mode = 0;
        cursor = 0;
        top = 0;
        cachedRanked = null;
        cachedAll = null;
    }

    function rankedRows() as Lang.Array {
        Crumb.at("rank");
        if (cachedRanked == null) {
            cachedRanked = loop.ranked(Time.now().value(), RANKED_ROWS);
        }
        Crumb.at("rank ok");
        return cachedRanked;
    }

    function rows() as Lang.Array {
        return mode == 0 ? rankedRows() : all();
    }

    function all() as Lang.Array {
        if (cachedAll == null) {
            cachedAll = loop.all();
        }
        return cachedAll;
    }

    // The ranked mode has one extra row: "All exercises >".
    function rowCount() as Lang.Number {
        var size = rows().size();
        return mode == 0 ? size + 1 : size;
    }

    function isAllRow() as Lang.Boolean {
        return mode == 0 && cursor >= rankedRows().size();
    }

    function move(direction) as Void {
        Crumb.at("mv");
        var moved = cursor + direction;
        if (moved < 0) {
            moved = 0;
        }
        if (moved > rowCount() - 1) {
            moved = rowCount() - 1;
        }
        cursor = moved;

        // Keep the highlighted row on screen: the full list is longer than a
        // round face, and a cursor that scrolls off the bottom is a list that
        // looks like it stopped.
        if (cursor < top) {
            top = cursor;
        }
        if (cursor > top + VISIBLE_ROWS - 1) {
            top = cursor - VISIBLE_ROWS + 1;
        }
        if (top > rowCount() - VISIBLE_ROWS) {
            top = rowCount() - VISIBLE_ROWS;
        }
        if (top < 0) {
            top = 0;
        }
        Crumb.at("mv ok");
    }

    function take() as Void {
        Crumb.at("take");
        if (isAllRow()) {
            mode = 1;
            cursor = 0;
            top = 0;
            Ui.requestUpdate();
            return;
        }

        var list = rows();
        if (cursor >= list.size()) {
            return;
        }

        var now = Time.now().value();
        loop.pick(list[cursor][:id], now);
        Crumb.at("picked");
        Ui.pushView(new ExerciseView(loop), new ExerciseDelegate(loop), Ui.SLIDE_LEFT);
    }

    // Back out of the full list into the ranking, then out to Home.
    function back() as Lang.Boolean {
        if (mode == 1) {
            mode = 0;
            cursor = 0;
            top = 0;
            Ui.requestUpdate();
            return true;
        }
        // Leaving clears the error, or the next visit opens on a stale message.
        App.Storage.deleteValue("crash");
        return false;
    }

    function onShow() as Void {
        // The ranking depends on the library and the history, so it is rebuilt
        // when the screen comes back rather than kept from the last visit.
        cachedRanked = null;
        cachedAll = null;

        // The finish cascade ends here: the menu popped, the exercise popped and
        // the picker popped, and this is the screen left holding the finished
        // session.
        if (loop.state == LoopState.SUMMARY) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return;
        }
        Ui.requestUpdate();
    }

    // A crash here costs the workout, so the draw is guarded: an exception is
    // caught, written to Storage and shown on screen instead of taking the app
    // down with it. Without the message on the watch itself there is no way to
    // read a stack off a wrist.
    function onUpdate(dc) {
        var stored = App.Storage.getValue("crash");
        if (stored != null) {
            showMessage(dc, stored.toString());
            return;
        }

        try {
            paint(dc);
        } catch (e) {
            var message = e.getErrorMessage();
            if (message == null) {
                message = "unreadable";
            }
            App.Storage.setValue("crash", message);
            showMessage(dc, message);
        }
    }

    // The message is shown where the user is already looking, and kept in
    // Storage so a crash in a key handler (which never reaches onUpdate) still
    // reaches the screen on the next redraw.
    function showMessage(dc, message) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.26, Gfx.FONT_XTINY, "PICKER", Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.42, Gfx.FONT_XTINY, Text.fit(message, 24), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.60, Gfx.FONT_XTINY, "BACK to leave", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function paint(dc) {
        Crumb.at("paint");
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.10, Gfx.FONT_XTINY, mode == 0 ? "FREE TRAINING" : "ALL EXERCISES", Gfx.TEXT_JUSTIFY_CENTER);

        var now = Time.now().value();
        var list = rows();
        var last = top + VISIBLE_ROWS;
        if (last > rowCount()) {
            last = rowCount();
        }

        for (var i = top; i < last; i++) {
            var y = height * 0.30 + (i - top) * height * 0.13;
            drawRow(dc, width, y, i, list, now);
        }

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.86, Gfx.FONT_XTINY, "START: pick  BACK: up", Gfx.TEXT_JUSTIFY_CENTER);
        Crumb.at("paint ok");
    }

    function drawRow(dc, width, y, index, list, now) {
        if (mode == 0 && index >= list.size()) {
            drawAllRow(dc, width, y);
            return;
        }
        if (index >= list.size()) {
            return;
        }

        var spec = list[index];
        var selected = index == cursor;

        if (selected) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width * 0.10, y, Gfx.FONT_XTINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        }

        dc.setColor(selected ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.17, y, Gfx.FONT_XTINY, Text.fit(spec[:name], 12), Gfx.TEXT_JUSTIFY_LEFT);

        dc.setColor(selected ? Gfx.COLOR_LT_GRAY : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.88, y, Gfx.FONT_XTINY, loop.rowDetail(spec, now), Gfx.TEXT_JUSTIFY_RIGHT);
    }

    // A rule above it, because it is a different kind of row: the three above are
    // lifts, this one is a door.
    function drawAllRow(dc, width, y) {
        var selected = cursor >= rankedRows().size();
        var ruleY = y - dc.getFontHeight(Gfx.FONT_XTINY) * 0.8;

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(width * 0.22, ruleY, width * 0.78, ruleY);

        if (selected) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width * 0.10, y, Gfx.FONT_XTINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        }

        dc.setColor(selected ? Gfx.COLOR_GREEN : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, Gfx.FONT_XTINY, "All exercises >", Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class PickerDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    function onKey(evt) {
        var key = evt.getKey();

        try {
            if (key == Ui.KEY_UP) {
                view.move(-1);
                Ui.requestUpdate();
                return true;
            }

            if (key == Ui.KEY_DOWN) {
                view.move(1);
                Ui.requestUpdate();
                return true;
            }

            if (key == Ui.KEY_ENTER) {
                view.take();
                return true;
            }
        } catch (e) {
            // Keep the app alive and let the view show what went wrong: a
            // keypress that throws is a crash the user cannot read.
            App.Storage.setValue("crash", e.getErrorMessage());
            Ui.requestUpdate();
            return true;
        }

        return false;
    }

    // Intercepted only while the full list is open: BACK there closes the list
    // rather than leaving free training entirely.
    function onBack() as Lang.Boolean {
        return view.back();
    }
}
