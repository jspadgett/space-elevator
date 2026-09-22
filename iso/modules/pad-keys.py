# pad-keys — turns any connected gamepad into a keyboard on the
# installer console, so the wizard's menus can be driven from a
# handheld's built-in pad.
#
#   D-pad / left stick   arrow keys
#   A / Start            Enter
#   B / Select           Escape
#   X                    Space  (toggles an entry in a multi-select)
#   Y                    Tab    (moves between the buttons of a prompt)
#
# This maps buttons, not letters; while a pad is connected the file
# /run/pad-keys/pad exists, which is the wizard's cue to offer its
# on-screen keyboard (pad-type) for text prompts. Pads are picked up
# and dropped as they come and go.

import os
import select
import time

import evdev
from evdev import ecodes as E

DEVICE_NAME = "pad-keys"
MARKER = "/run/pad-keys/pad"
RESCAN_SECONDS = 2.0
PRESS = 0.5     # a stick past this fraction of its travel presses
RELEASE = 0.3   # and releases once it comes back inside this

BUTTONS = {
    E.BTN_SOUTH: E.KEY_ENTER,
    E.BTN_START: E.KEY_ENTER,
    E.BTN_EAST: E.KEY_ESC,
    E.BTN_SELECT: E.KEY_ESC,
    E.BTN_WEST: E.KEY_SPACE,
    E.BTN_NORTH: E.KEY_TAB,
}

# Each axis drives a pair of keys: negative direction, positive direction.
AXES = {
    E.ABS_HAT0X: (E.KEY_LEFT, E.KEY_RIGHT),
    E.ABS_HAT0Y: (E.KEY_UP, E.KEY_DOWN),
    E.ABS_X: (E.KEY_LEFT, E.KEY_RIGHT),
    E.ABS_Y: (E.KEY_UP, E.KEY_DOWN),
}

KEYS = sorted(
    set(BUTTONS.values()) | {k for pair in AXES.values() for k in pair}
)


class Mapper:
    """Turns gamepad events into key presses and releases.

    Pure: feed() returns a list of (key, pressed) pairs and touches
    no devices, which is what makes it testable without a pad.
    """

    def __init__(self, absinfo):
        # absinfo: {axis code: (min, max)} for the axes the pad reports.
        self.centre = {}
        self.half = {}
        for code, (lo, hi) in absinfo.items():
            self.centre[code] = (lo + hi) / 2
            self.half[code] = max((hi - lo) / 2, 1)
        self.held = {}  # axis code -> -1, 0 or 1

    def feed(self, ev_type, code, value):
        if ev_type == E.EV_KEY and code in BUTTONS:
            if value == 2:  # autorepeat from the pad itself; ignore
                return []
            return [(BUTTONS[code], value == 1)]
        if ev_type == E.EV_ABS and code in AXES:
            return self._axis(code, value)
        return []

    def _axis(self, code, value):
        if code in (E.ABS_HAT0X, E.ABS_HAT0Y):
            # Hats report -1, 0, 1 directly.
            wanted = (value > 0) - (value < 0)
        else:
            if code not in self.centre:
                return []
            n = (value - self.centre[code]) / self.half[code]
            current = self.held.get(code, 0)
            if n > PRESS:
                wanted = 1
            elif n < -PRESS:
                wanted = -1
            elif current != 0 and abs(n) >= RELEASE:
                wanted = current  # hysteresis: stay held until well back
            else:
                wanted = 0
        return self._change(code, wanted)

    def _change(self, code, wanted):
        current = self.held.get(code, 0)
        if wanted == current:
            return []
        neg, pos = AXES[code]
        out = []
        if current == -1:
            out.append((neg, False))
        elif current == 1:
            out.append((pos, False))
        if wanted == -1:
            out.append((neg, True))
        elif wanted == 1:
            out.append((pos, True))
        self.held[code] = wanted
        return out


def is_gamepad(dev):
    caps = dev.capabilities()
    return E.BTN_SOUTH in caps.get(E.EV_KEY, []) and dev.name != DEVICE_NAME


def open_pads(known):
    pads = {}
    for path in evdev.list_devices():
        if path in known:
            continue
        try:
            dev = evdev.InputDevice(path)
            if is_gamepad(dev):
                absinfo = {
                    code: (info.min, info.max)
                    for code, info in dev.capabilities().get(E.EV_ABS, [])
                    if code in AXES
                }
                pads[path] = (dev, Mapper(absinfo))
                print(f"pad-keys: using {dev.name} at {path}", flush=True)
            else:
                dev.close()
        except OSError:
            pass
    return pads


def mark(present):
    if present:
        os.makedirs(os.path.dirname(MARKER), exist_ok=True)
        open(MARKER, "a").close()
    elif os.path.exists(MARKER):
        os.remove(MARKER)


def main():
    keyboard = evdev.UInput({E.EV_KEY: KEYS}, name=DEVICE_NAME)
    pads = {}
    last_scan = 0.0
    while True:
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            pads.update(open_pads(pads))
            mark(bool(pads))
            last_scan = now
        if not pads:
            time.sleep(RESCAN_SECONDS)
            continue
        by_fd = {dev.fd: path for path, (dev, _) in pads.items()}
        ready, _, _ = select.select(list(by_fd), [], [], RESCAN_SECONDS)
        for fd in ready:
            path = by_fd[fd]
            dev, mapper = pads[path]
            try:
                events = list(dev.read())
            except OSError:
                print(f"pad-keys: lost {dev.name}", flush=True)
                for code in list(mapper.held):
                    for key, pressed in mapper._change(code, 0):
                        keyboard.write(E.EV_KEY, key, int(pressed))
                dev.close()
                del pads[path]
                mark(bool(pads))
                keyboard.syn()
                continue
            for ev in events:
                for key, pressed in mapper.feed(ev.type, ev.code, ev.value):
                    keyboard.write(E.EV_KEY, key, int(pressed))
            keyboard.syn()


if __name__ == "__main__":
    main()
