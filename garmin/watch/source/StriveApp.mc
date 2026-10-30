using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Lang;

class StriveApp extends App.AppBase {

    var view;

    function initialize() {
        AppBase.initialize();
        view = null;
    }

    function getInitialView() {
        view = new StriveView();
        return [ view, new StriveDelegate(view) ];
    }

    function onStart(state) {
        Comm.registerForPhoneAppMessages(method(:onPhoneAppMessage));
    }

    // The phone sends a delimited string of exercise id -> weight. A Dictionary
    // is also handled in case the transport ever delivers one.
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        // Receipt counter, shown on screen. It separates "the message never
        // arrived" from "it arrived and the parsing is wrong".
        var count = App.Storage.getValue("msg_count");
        if (count == null) {
            count = 0;
        }
        App.Storage.setValue("msg_count", count + 1);

        var data = msg.data;
        if (data == null) {
            return;
        }

        if (data instanceof Lang.String) {
            Plan.replaceFromText(data);
        } else if (data instanceof Lang.Dictionary) {
            Plan.replaceFromDictionary(data);
        } else {
            return;
        }

        if (view != null) {
            view.reloadFromPlan();
            Ui.requestUpdate();
        }
    }
}
