using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Time as Time;
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

    function initialize(model) {
        View.initialize();
        loop = model;
        mode = 0;
        cursor = 0;
        top = 0;
    }

    function rankedRows() as Lang.Array {
        return loop.ranked(Time.now().value(), RANKED_ROWS);
    }

    function rows() as Lang.Array {
        return mode == 0 ? rankedRows() : loop.all();
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
    }

    function take() as Void {
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
        return false;
    }

    function onShow() as Void {
        // The finish cascade ends here: the menu popped, the exercise popped and
        // the picker popped, and this is the screen left holding the finished
        // session.
        if (loop.state == LoopState.SUMMARY) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return;
        }
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
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

        return false;
    }

    // Intercepted only while the full list is open: BACK there closes the list
    // rather than leaving free training entirely.
    function onBack() as Lang.Boolean {
        return view.back();
    }
}
