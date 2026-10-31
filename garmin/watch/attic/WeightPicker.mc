using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
import Toybox.Lang;

// Numeric wheel for the load.
//
// WatchUi.NumberPicker is deprecated (limited to eight fixed modes and not
// supported on current hardware), so this builds a Picker with a custom factory
// instead - the same approach as Garmin's own Picker sample.
class WeightFactory extends Ui.PickerFactory {

    private var increment as Float;
    private var count as Number;

    function initialize(stepKg as Float, maxKg as Float) {
        PickerFactory.initialize();
        increment = stepKg;
        count = (maxKg / stepKg).toNumber() + 1;
    }

    function getValue(index as Number) as Object? {
        return index * increment;
    }

    function getSize() as Number {
        return count;
    }

    function getDrawable(index as Number, selected as Boolean) as Ui.Drawable? {
        var value = getValue(index);
        var text = "0.0";
        if (value instanceof Float) {
            text = value.format("%.1f");
        }
        return new Ui.Text({
            :text => text,
            :color => Gfx.COLOR_WHITE,
            :font => Gfx.FONT_NUMBER_MEDIUM,
            :locX => Ui.LAYOUT_HALIGN_CENTER,
            :locY => Ui.LAYOUT_VALIGN_CENTER
        });
    }
}

class WeightPicker extends Ui.Picker {

    function initialize(currentKg as Float) {
        var title = new Ui.Text({
            :text => "Weight (kg)",
            :color => Gfx.COLOR_WHITE,
            :locX => Ui.LAYOUT_HALIGN_CENTER,
            :locY => Ui.LAYOUT_VALIGN_BOTTOM
        });

        var factory = new WeightFactory(2.5, 300.0);
        var defaultIndex = (currentKg / 2.5).toNumber();

        Picker.initialize({
            :title => title,
            :pattern => [factory],
            :defaults => [defaultIndex]
        });
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        Picker.onUpdate(dc);
    }
}

class WeightPickerDelegate extends Ui.PickerDelegate {

    private var view;

    function initialize(targetView) {
        PickerDelegate.initialize();
        view = targetView;
    }

    function onCancel() as Boolean {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        return true;
    }

    function onAccept(values as Array) as Boolean {
        if (values.size() > 0) {
            view.setWeight(values[0]);
        }
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        return true;
    }
}
