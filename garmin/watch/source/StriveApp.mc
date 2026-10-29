using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class StriveApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new StriveView();
        return [ view, new StriveDelegate(view) ];
    }
}
