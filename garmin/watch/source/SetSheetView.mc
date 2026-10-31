using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Time as Time;
using Toybox.Lang;

// Drawing for the set sheet: three rows, the focused one in green and marked
// with a caret.
//
// The colours and font sizes are the training screen's own, so the sheet reads
// as the same app rather than as a dialog from somewhere else. Push it with
//
//   loop.openSheet();
//   var sheet = new SetSheetView(loop.sheet, loop, Text.fit(loop.name(), 12));
//   Ui.pushView(sheet, new SetSheetDelegate(sheet), Ui.SLIDE_UP);
//
// and banking goes through the loop and StriveApp.recordSet, so the state
// machine, the log and the bus all see the same set in the same order. The
// exercise view below the sheet decides what to show when it pops back.
class SetSheetView extends Ui.View {

    var sheet;
    var loop;
    var title;

    function initialize(model, trainingLoop, heading) {
        View.initialize();
        sheet = model;
        loop = trainingLoop;
        title = heading;
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.075, Gfx.FONT_SMALL, title, Gfx.TEXT_JUSTIFY_CENTER);

        var top = height * 0.30;
        var step = height * 0.155;
        drawRow(dc, width, top, SheetField.WEIGHT, "Weight", sheet.weight().format("%.1f") + " kg");
        drawRow(dc, width, top + step, SheetField.REPS, "Reps", sheet.reps().toString());
        drawRow(dc, width, top + step * 2, SheetField.RIR, "RIR", sheet.rir().toString());

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.84, Gfx.FONT_XTINY, hintText(), Gfx.TEXT_JUSTIFY_CENTER);
    }

    // Label left, value right, both inside the round face's usable width: a row
    // pushed to the edges loses its first character on a fenix.
    function drawRow(dc, width, y, field, label, value) {
        var focused = sheet.focus() == field;

        dc.setColor(focused ? Gfx.COLOR_LT_GRAY : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.26, y, Gfx.FONT_TINY, label, Gfx.TEXT_JUSTIFY_LEFT);

        dc.setColor(focused ? Gfx.COLOR_GREEN : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.74, y, Gfx.FONT_TINY, value, Gfx.TEXT_JUSTIFY_RIGHT);

        if (!focused) {
            return;
        }

        // The caret and the rule carry the highlight as well as the colour: a
        // colour alone is the one cue that a sweaty glance mid-set misses.
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.18, y, Gfx.FONT_TINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawLine(width * 0.26, y + dc.getFontHeight(Gfx.FONT_TINY) + 4, width * 0.74, y + dc.getFontHeight(Gfx.FONT_TINY) + 4);
    }

    function hintText() as Lang.String {
        if (sheet.focus() >= SheetField.RIR) {
            return "START: log  BACK: cancel";
        }
        return "START: next  BACK: cancel";
    }

    // START on the last row. The set reaches Storage before the view pops, so a
    // crash in between still leaves it banked.
    function bank() as Void {
        var set = sheet.accept();
        if (set == null) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return;
        }

        // The loop first: its tally and the rest it starts decide the next
        // screen, and they have to be right even if the write below is what
        // fails. The log and the bus follow from the same accepted set, so the
        // phone and the watch can never disagree about what was lifted.
        loop.bankSet(set[:weight], set[:reps], set[:rir], Time.now().value());
        StriveApp.recordSet(loop, set);

        Haptics.setBanked();
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    // BACK. Nothing is written: a cancelled sheet banks nothing.
    function cancel() as Void {
        sheet.cancel();
        Ui.popView(Ui.SLIDE_RIGHT);
    }
}
