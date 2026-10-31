using Toybox.Communications as Comm;
using Toybox.Timer as Timer;
using Toybox.Lang;

// Serialised outbound queue for the companion message bus.
//
// Measured behaviour: messages sent faster than roughly one per 350-400 ms are
// silently dropped, and transmit still reports success. A burst of 18 sends
// arrived as 12 messages with no error anywhere. So nothing is ever sent while
// another send is outstanding: the listener releases the queue and the next
// message waits out a short gap.
class Outbox {

    const GAP_MS = 400;

    var items;
    var sending;
    var timer;

    function initialize() {
        items = [] as Lang.Array<Lang.String>;
        sending = false;
        timer = new Timer.Timer();
    }

    function enqueue(text) as Void {
        items.add(text);
        pump();
    }

    function pump() as Void {
        if (sending || items.size() == 0) {
            return;
        }

        sending = true;
        var text = items[0];
        items = items.slice(1, items.size());
        Comm.transmit(text, null, new PhoneListener());
    }

    // Called on success and on failure alike, so a rejected send cannot wedge the
    // queue for the rest of the session.
    function onSent() as Void {
        sending = false;

        if (items.size() == 0) {
            return;
        }
        timer.start(method(:pump), GAP_MS, false);
    }

    function pending() as Lang.Number {
        return items.size();
    }
}
