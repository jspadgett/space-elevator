# pad-type — an on-screen keyboard for the installer console. Stands in
# for `gum input` when a gamepad is driving the wizard: arrows move
# over a grid of characters, Enter picks one, Tab jumps to Done. With
# pad-keys running, that is D-pad, A and Y. A real keyboard also types
# straight into the field.
#
#   pad-type [--header TEXT] [--value TEXT] [--placeholder TEXT] [--password]
#
# Prints the text on stdout and exits 0 on Done, 1 on Escape.

import argparse
import curses
import os
import sys
import textwrap

ROWS = [
    list("1234567890-_."),
    list("qwertyuiop/@:"),
    list("asdfghjkl!#$%"),
    list("zxcvbnm,;'\"()"),
    ["Shift", "Space", "Bksp", "Clear", "Done"],
]
ACTIONS = set(ROWS[-1])


class Editor:
    """The keyboard's state: text, cursor on the grid, shift.

    Pure: press() takes a key name and returns None, "done" or
    "cancel", so it can be tested without a terminal.
    """

    def __init__(self, value=""):
        self.text = value
        self.row = 1
        self.col = 0
        self.shift = False

    def current(self):
        return ROWS[self.row][self.col]

    def press(self, key):
        if key == "escape":
            return "cancel"
        if key == "tab":
            self.row = len(ROWS) - 1
            self.col = ROWS[-1].index("Done")
        elif key == "up":
            self.row = max(self.row - 1, 0)
            self.col = min(self.col, len(ROWS[self.row]) - 1)
        elif key == "down":
            self.row = min(self.row + 1, len(ROWS) - 1)
            self.col = min(self.col, len(ROWS[self.row]) - 1)
        elif key == "left":
            self.col = (self.col - 1) % len(ROWS[self.row])
        elif key == "right":
            self.col = (self.col + 1) % len(ROWS[self.row])
        elif key == "enter":
            return self.pick(self.current())
        elif key == "backspace":
            self.text = self.text[:-1]
        elif len(key) == 1 and key.isprintable():
            self.text += key
        return None

    def pick(self, key):
        if key == "Done":
            return "done"
        if key == "Shift":
            self.shift = not self.shift
        elif key == "Space":
            self.text += " "
        elif key == "Bksp":
            self.text = self.text[:-1]
        elif key == "Clear":
            self.text = ""
        else:
            self.text += key.upper() if self.shift else key
            self.shift = False
        return None


def key_name(ch):
    if ch in (curses.KEY_ENTER, 10, 13):
        return "enter"
    if ch == 27:
        return "escape"
    if ch == 9:
        return "tab"
    if ch in (curses.KEY_BACKSPACE, 127, 8):
        return "backspace"
    names = {
        curses.KEY_UP: "up",
        curses.KEY_DOWN: "down",
        curses.KEY_LEFT: "left",
        curses.KEY_RIGHT: "right",
    }
    if ch in names:
        return names[ch]
    if 32 <= ch < 127:
        return chr(ch)
    return ""


def draw(scr, ed, args):
    scr.erase()
    height, width = scr.getmaxyx()
    y = 0
    for line in textwrap.wrap(args.header or "", max(width - 2, 20)):
        scr.addnstr(y, 1, line, width - 2, curses.A_BOLD)
        y += 1
    y += 1
    if ed.text:
        shown = "*" * len(ed.text) if args.password else ed.text
        scr.addnstr(y, 1, "> " + shown + "_", width - 2)
    else:
        scr.addnstr(y, 1, "> " + (args.placeholder or ""), width - 2,
                    curses.A_DIM)
    y += 2
    for r, row in enumerate(ROWS):
        x = 1
        for c, key in enumerate(row):
            label = key if key in ACTIONS else (
                key.upper() if ed.shift else key)
            attr = curses.A_NORMAL
            if (r, c) == (ed.row, ed.col):
                attr = curses.A_REVERSE
            elif key == "Shift" and ed.shift:
                attr = curses.A_BOLD | curses.A_UNDERLINE
            cell = f" {label} "
            if x + len(cell) < width:
                scr.addstr(y + r, x, cell, attr)
            x += len(cell) + (0 if key in ACTIONS else 1)
    hint = "arrows/D-pad move  Enter/A picks  Tab/Y to Done  Esc/B cancels"
    if y + len(ROWS) + 1 < height:
        scr.addnstr(y + len(ROWS) + 1, 1, hint, width - 2, curses.A_DIM)
    scr.refresh()


def run(scr, args):
    curses.curs_set(0)
    try:
        curses.set_escdelay(25)
    except AttributeError:
        pass
    scr.keypad(True)
    ed = Editor(args.value or "")
    while True:
        draw(scr, ed, args)
        result = ed.press(key_name(scr.getch()))
        if result == "done":
            return ed.text
        if result == "cancel":
            return None


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--header", default="")
    parser.add_argument("--value", default="")
    parser.add_argument("--placeholder", default="")
    parser.add_argument("--password", action="store_true")
    args = parser.parse_args()

    # The wizard captures stdout, so the screen is drawn on the
    # terminal itself and only the answer goes to the pipe.
    saved_stdout = os.dup(1)
    tty = os.open("/dev/tty", os.O_RDWR)
    os.dup2(tty, 1)
    try:
        result = curses.wrapper(run, args)
    finally:
        os.dup2(saved_stdout, 1)
        os.close(tty)
    if result is None:
        sys.exit(1)
    print(result)


if __name__ == "__main__":
    main()
