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

    // The phone sends a plan as a Dictionary with string keys:
    //   {"type":"plan","items":[{"id":"bench_press","weight":22.5}, ...]}
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Lang.Dictionary)) {
            return;
        }
        if (data["type"] != "plan") {
            return;
        }

        Plan.replace(data["items"]);

        if (view != null) {
            view.reloadFromPlan();
            Ui.requestUpdate();
        }
    }
}
