using Toybox.Application as App;
using Toybox.Lang;

// A breadcrumb of the last thing the app started doing.
//
// The watch gives no stack when it kills an app: it shows the Connect IQ icon
// and that is the whole report. Writing the current step to Storage before and
// after it means the next launch can say which call never returned, which is
// the difference between a guess and a diagnosis. Home draws it, so the answer
// survives the crash that produced it.
//
// Diagnostic only, and cheap enough to leave in: two writes per screen, not per
// frame.
module Crumb {

    function key() as Lang.String {
        return "crumb";
    }

    function at(text) as Void {
        App.Storage.setValue(key(), text);
    }

    function last() as Lang.String or Null {
        var value = App.Storage.getValue(key());
        if (value == null) {
            return null;
        }
        return value.toString();
    }

    function clear() as Void {
        App.Storage.deleteValue(key());
    }
}
