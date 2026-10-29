using Toybox.Application as App;
using Toybox.Lang;

// Weights pushed from the phone, one entry per exercise id.
//
// Stored separately from Progress so a plan from the phone never overwrites the
// watch's own record of what was actually lifted.
module Plan {

    function key(id) {
        return "p_" + id;
    }

    function replace(items) {
        if (items == null) {
            return;
        }
        for (var i = 0; i < items.size(); i++) {
            var item = items[i];
            if (!(item instanceof Lang.Dictionary)) {
                continue;
            }
            var id = item["id"];
            var weight = item["weight"];
            if (id == null || weight == null) {
                continue;
            }
            App.Storage.setValue(key(id), weight.toFloat());
        }
    }

    function weightFor(id) {
        return App.Storage.getValue(key(id));
    }
}
