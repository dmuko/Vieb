#!/usr/bin/env python3
"""Settings › Keyboard & Mouse › Vim keys (Vim.swift, docs/VIM.md).

Build first (`./build.sh`), then `python3 Tests/vim_keys.py`. Uses the split
suite's harness: started hidden, no window made or shown, everything removed
afterwards. Keys go through the window's own key handling (bench `vimkey`),
then to the page if nothing took them.

Off (as it ships), j is the page's. On: j/d/G/gg scroll the page, K and J
change tabs (J the tab below in a column, K the one to the right across the top), / opens the find bar, i hands every key to the page until
Escape, a box with the caret keeps every key and Escape lets it go, ? lists
the keys. f and F hint links, gi types in a field. o and ge raise the
address field, T ⌘K's, b and B one of bookmarks alone, and ⌃J/⌃K walk its
list. ⌘ keys are never Vim's.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("vim-keys")
t = sv.T()

CODES = {"f": 3, "F": 3, "s": 1, "e": 14, "h": 4, "j": 38, "k": 40, "d": 2, "u": 32, "g": 5, "G": 5, "K": 40, "J": 38, "i": 34, "x": 7, "/": 26, "?": 27, "a": 0,
         "o": 31, "O": 31, "l": 37, "b": 11, "B": 11, "T": 17, "E": 14}


def key(ch, mods=None, ignoring=None, settle=0.5):
    req = {"do": "vimkey", "chars": ch, "code": 53 if ch == "\x1b" else CODES[ch], "mods": mods or []}
    if ignoring: req["ignoring"] = ignoring
    if ch.isupper() and "shift" not in req["mods"]: req["mods"].append("shift")
    answer = sv.cmd(req); time.sleep(settle)
    return answer


ESC = "\x1b"
# ⌃ and a letter: the control character it types, and its key.
CONTROL = {"j": ("\n", 38), "k": ("\x0b", 40), "n": ("\x0e", 45), "p": ("\x10", 35)}


def ctrl(letter, settle=0.3):
    chars, code = CONTROL[letter]
    answer = sv.cmd({"do": "vimkey", "chars": chars, "code": code, "mods": ["control"], "ignoring": letter})
    time.sleep(settle)
    return answer


def field(): return sv.cmd({"do": "suggest"})
def placeholder(): return sv.cmd({"do": "probe"})["placeholder"]
# The tab in front: a key nothing is mapped to answers with it.
def front(): return sv.cmd({"do": "vimkey", "chars": "z", "code": 6})["active"].lower()


def y(id): return sv.ev(id, "Math.round(scrollY)")


try:
    sv.setup()
    sv.launch()
    a = sv.page("long"); b = sv.page("tall"); sv.sp("select", id=a); time.sleep(0.6)

    found = sv.cmd({"do": "settings", "find": "vimium"})
    t.ok("found by Settings' search", any("vim.keys" in i["keys"] for i in found["found"]), [i["id"] for i in found["found"]])
    t.ok("off by default", found["values"].get("vim.keys") is False, found["values"].get("vim.keys"))
    t.ok("off: j is the page's", key("j")["taken"] is False)

    sv.cmd({"do": "settings", "set": "vim.keys", "value": True}); time.sleep(0.5)

    # Scrolling.
    t.ok("j is Vim's", key("j", settle=0.8)["taken"] is True)
    t.ok("j scrolls down", y(a) > 0, y(a))
    before = y(a)
    key("d", settle=0.9)
    height = sv.ev(a, "innerHeight")
    t.ok("d scrolls half a page", abs(y(a) - before - height / 2) <= 2, (before, y(a), height))
    key("G", ignoring="g", settle=1.2)
    bottom = sv.ev(a, "document.documentElement.scrollHeight - innerHeight")
    t.ok("G goes to the bottom", abs(y(a) - bottom) <= 2, (y(a), bottom))
    first = key("g")
    t.ok("g waits for the next key", first["taken"] and first["pending"] == "g", first)
    key("g", settle=1.2)
    t.ok("gg goes to the top", y(a) == 0, y(a))
    first = key("g", settle=1.3)
    t.ok("a g let be is forgotten after a second", first["pending"] == "g" and sv.cmd({"do": "vimkey", "chars": "z", "code": 6})["pending"] == "", first)

    # Tabs.
    moved = key("K")
    t.ok("K goes to the next tab", moved["active"].lower().startswith(b.lower()), (moved["active"], b))
    moved = key("J")
    t.ok("J comes back", moved["active"].lower().startswith(a.lower()), (moved["active"], a))
    # Tabs down a column: J is the tab below, K the one above.
    sv.cmd({"do": "ui", "sidebar": True}); time.sleep(0.8)
    moved = key("J")
    t.ok("in a column, J goes to the tab below", moved["active"].lower().startswith(b.lower()), (moved["active"], b))
    moved = key("K")
    t.ok("and K to the one above", moved["active"].lower().startswith(a.lower()), (moved["active"], a))
    sv.cmd({"do": "ui", "sidebar": False}); time.sleep(0.8)
    moved = key("K")
    t.ok("across the top again, K goes right", moved["active"].lower().startswith(b.lower()), (moved["active"], b))
    key("J")

    # Find.
    t.ok("/ opens the find bar", key("/", mods=["shift"], ignoring="7")["finding"] is True)
    key(ESC)
    t.ok("Escape puts it away", sv.cmd({"do": "vimkey", "chars": "z", "code": 6})["finding"] is False)

    # i: every key the page's until Escape.
    t.ok("i hands the keys to the page", key("i")["inserting"] is True)
    before = y(a)
    t.ok("then j is the page's", key("j")["taken"] is False and y(a) == before, y(a))
    left = key(ESC)
    t.ok("Escape gives them back", left["taken"] and left["inserting"] is False, left)

    # A box with the caret keeps every key; Escape lets it go.
    sv.ev(a, "document.body.insertAdjacentHTML('afterbegin', '<input id=f>'); document.getElementById('f').focus(); true")
    time.sleep(0.5)
    typed = key("j")
    t.ok("in a box, j is the box's", typed["taken"] is False, typed)
    t.ok("and types there", sv.ev(a, "document.getElementById('f').value") == "j", sv.ev(a, "document.getElementById('f').value"))
    left = key(ESC, settle=0.8)
    t.ok("Escape lets the box go", left["taken"] and sv.ev(a, "document.activeElement.id") != "f",
         (left, sv.ev(a, "document.activeElement.id")))
    t.ok("and j is Vim's again", key("j")["taken"] is True)

    # The list of keys.
    t.ok("? lists the keys", key("?", mods=["shift"], ignoring="+")["helping"] is True)
    t.ok("Escape puts the list away", key(ESC)["helping"] is False)

    # Hints: f clicks, F opens behind, Escape takes them away, gi types.
    links = (f"<a id=one href='{sv.BASE}/first'>one</a> <a id=two href='{sv.BASE}/second'>two</a> "
             "<button id=three onclick=\"document.title='clicked'\">three</button> <input id=field>")
    sv.ev(a, "document.body.innerHTML = " + repr(links) + "; scrollTo(0, 0); document.title = 'links'; true"); time.sleep(0.4)
    up = key("f")
    t.ok("f puts hints up", up["taken"] and up["hints"] == "shown", up)
    # Four things to click, the field too: a d f s, Vimium's home row sorted.
    picked = key("f", settle=0.8)
    t.ok("a hint's letter clicks it", picked["hints"] == "" and sv.ev(a, "document.title") == "clicked",
         (picked, sv.ev(a, "document.title")))
    key("f"); gone = key(ESC)
    t.ok("Escape takes the hints away", gone["taken"] and gone["hints"] == "", gone)
    tabs = sv.cmd({"do": "vimkey", "chars": "z", "code": 6})["tabs"]
    key("F", ignoring="f"); behind = key("d", settle=1.2)
    t.ok("F opens the link in a tab behind", behind["tabs"] == tabs + 1 and behind["active"].lower().startswith(a.lower()),
         (behind, tabs))
    key("g"); key("i")
    t.ok("gi puts the caret in the first field", sv.ev(a, "document.activeElement.id") == "field", sv.ev(a, "document.activeElement.id"))
    key(ESC, settle=0.6)
    key("f"); followed = key("a", settle=1.5)
    t.ok("f on a link follows it", sv.url(sv.sp("state"), a).endswith("/first"), sv.url(sv.sp("state"), a))

    # Opening: o and ge raise the field over the page, T ⌘K's, b and B
    # one of bookmarks alone; ⌃J ⌃K ⌃N ⌃P walk a list from its field.
    key("o", settle=0.8)
    st = field(); c = sv.cmd({"do": "caret"})
    t.ok("o raises the field with the page's address", st["editing"] and st["typed"] == st["address"] != "", st)
    t.ok("selected whole, to type over", c.get("selected") == [0, len(c.get("text", ""))], c)
    key(ESC, settle=0.6)
    t.ok("Escape puts it away", field()["editing"] is False)
    key("g"); key("e", settle=0.8)
    st = field(); c = sv.cmd({"do": "caret"})
    t.ok("ge: the address, the caret after it", st["typed"] == st["address"] and c.get("selected") == [len(c.get("text", "")), 0],
         (st["typed"], c.get("selected")))
    key(ESC, settle=0.6)

    key("T", settle=0.8)
    st = field()
    t.ok("T raises ⌘K's list of open tabs", st["editing"] and placeholder() == "Switch to an open tab"
         and len(st["offers"]) >= 2 and st["picked"] == 0, (placeholder(), st))
    ctrl("j"); t.ok("⌃J goes down the list", field()["picked"] == 1, field()["picked"])
    ctrl("k"); t.ok("⌃K up", field()["picked"] == 0, field()["picked"])
    ctrl("n"); ctrl("p")
    t.ok("⌃N and ⌃P the same", field()["picked"] == 0, field()["picked"])
    key(ESC, settle=0.6)

    sv.sp("select", id=b); time.sleep(0.5); sv.cmd({"do": "keeppage"}); tall = sv.url(sv.sp("state"), b)
    sv.sp("select", id=a); time.sleep(0.5); sv.cmd({"do": "keeppage"})
    key("b", settle=0.8)
    st = field()
    t.ok("b offers bookmarks alone", st["editing"] and st["typed"] == "" and st["offers"]
         and all(o[1] == "bookmark" for o in st["offers"]) and st["picked"] == 0, st)
    t.ok("and says so", placeholder() == "Search bookmarks", placeholder())
    sv.cmd({"do": "suggest", "action": "go"}); time.sleep(1.2)
    t.ok("Return opens the first in this tab", sv.url(sv.sp("state"), a) == tall, (sv.url(sv.sp("state"), a), tall))

    # A new tab is a blank one (or the blank tab already there), whose
    # field is up as the tab itself.
    key("B", settle=1.0)
    st = field()
    t.ok("B offers them for a new tab", st["address"] == "" and st["offers"]
         and all(o[1] == "bookmark" for o in st["offers"]) and placeholder() == "Search bookmarks", (st, placeholder()))
    ctrl("j"); down = field()["picked"]; ctrl("k")
    t.ok("⌃J and ⌃K walk a blank tab's list too", len(st["offers"]) == 2 and down == 1 and field()["picked"] == 0,
         (len(st["offers"]), down, field()["picked"]))
    sv.cmd({"do": "suggest", "action": "go"}); time.sleep(1.2)
    t.ok("and Return opens it there", field()["address"] == tall and not front().startswith(a.lower()), (field()["address"], front()))
    opened = front()

    key("g"); key("E", settle=1.0)
    st = field(); c = sv.cmd({"do": "caret"})
    t.ok("gE: the address in a new tab's field, the caret after it",
         st["address"] == "" and st["typed"] == tall and c.get("selected") == [len(c.get("text", "")), 0],
         (st["address"], st["typed"], c.get("selected")))
    sv.cmd({"do": "suggest", "action": "go"}); time.sleep(1.2)
    t.ok("and Return goes there", field()["address"] == tall and front() != opened, (field()["address"], front()))

    sv.sp("select", id=a); time.sleep(0.5)
    key("O", settle=1.0)
    st = field()
    t.ok("O: a new tab, its field empty", st["address"] == "" and st["typed"] == "" and placeholder() == "Enter a web address", (st, placeholder()))
    sv.sp("select", id=a); time.sleep(0.6)

    # Hint letters of one's own.
    sv.cmd({"do": "settings", "set": "vim.hints", "value": "hje"}); time.sleep(0.4)
    links = "".join(f"<button onclick=\"document.title='b{n}'\">b{n}</button> " for n in range(4))
    sv.ev(a, "document.body.innerHTML = " + repr(links) + "; true"); time.sleep(0.4)
    # Four with h j e: e, hh, j, hj. j alone is the third.
    key("f"); done = key("j", settle=0.8)
    t.ok("hints made of one's own letters", done["hints"] == "" and sv.ev(a, "document.title") == "b2",
         (done, sv.ev(a, "document.title")))
    sv.cmd({"do": "settings", "set": "vim.hints", "value": "sadfjklewcmpgh"}); time.sleep(0.3)

    # Settings: its rows walked as a list, not its find field's keys.
    sv.cmd({"do": "ui", "settings": True}); time.sleep(1.0)
    here = sv.cmd({"do": "vimkey", "chars": "z", "code": 6})
    rows = here["rows"]
    t.ok("Settings opens with the keys Vim's, not Find a setting's", here["caret"] is False and len(rows) > 3 and here["row"] == "",
         {k: here[k] for k in ("caret", "row")} | {"rows": len(rows)})
    t.ok("j picks the first row", key("j")["row"] == rows[0])
    t.ok("j again the next", key("j")["row"] == rows[1])
    t.ok("k back up", key("k")["row"] == rows[0])
    t.ok("G the last", key("G", ignoring="g")["row"] == rows[-1])
    key("g"); t.ok("gg the first", key("g")["row"] == rows[0])
    start = here["settingsPage"]
    moved = key("l", settle=0.8)
    t.ok("l the next section", moved["settingsPage"] != start and moved["row"] == "", moved["settingsPage"])
    back = key("h", settle=0.8)
    t.ok("h back", back["settingsPage"] == start, back["settingsPage"])
    for _ in range(14):
        if key("l", settle=0.6)["settingsPage"] == "keyboard": break
    # The switch is under the page's Advanced fold: Return on the fold opens it.
    for _ in range(40):
        if key("j", settle=0.25)["row"] == "vim.advanced": break
    folded = sv.cmd({"do": "vimkey", "chars": "z", "code": 6})["rows"]
    opened = sv.cmd({"do": "vimkey", "chars": "\r", "code": 36}); time.sleep(0.4)
    opened = sv.cmd({"do": "vimkey", "chars": "z", "code": 6})
    t.ok("Return on Advanced opens it, its rows to walk", "keys.backspaceBack" not in folded
         and "keys.backspaceBack" in opened["rows"] and opened["row"] == "vim.advanced", (len(folded), len(opened["rows"])))
    for _ in range(40):
        if key("j", settle=0.25)["row"] == "keys.backspaceBack": break
    was = sv.cmd({"do": "settings", "find": "backspace"})["values"].get("keys.backspaceBack")
    pressed = sv.cmd({"do": "vimkey", "chars": "\r", "code": 36}); time.sleep(0.4)
    now = sv.cmd({"do": "settings", "find": "backspace"})["values"].get("keys.backspaceBack")
    t.ok("Return turns the picked switch", pressed["row"] == "keys.backspaceBack" and pressed["taken"] and now is (not was),
         (pressed["row"], was, now))
    sv.cmd({"do": "vimkey", "chars": " ", "code": 49}); time.sleep(0.4)
    t.ok("Space turns it back", sv.cmd({"do": "settings", "find": "backspace"})["values"].get("keys.backspaceBack") is was)
    t.ok("Escape lets go of the row", key(ESC)["row"] == "")
    t.ok("/ puts the keys in Find a setting", key("/", mods=["shift"], ignoring="7")["caret"] is True)
    for ch, code in (("v", 9), ("i", 34), ("m", 46)):
        sv.cmd({"do": "vimkey", "chars": ch, "code": code}); time.sleep(0.1)
    time.sleep(0.4)
    found = sv.cmd({"do": "vimkey", "chars": "\r", "code": 36})
    t.ok("Return there gives the keys back, at the first row found", found["caret"] is False and found["row"] == found["rows"][0]
         and "vim.keys" in found["rows"], {k: found[k] for k in ("caret", "row", "rows")})
    sv.cmd({"do": "ui", "settings": False}); time.sleep(0.6)
    sv.sp("select", id=a); time.sleep(0.5)

    # x closes the tab in front, as ⌘W.
    count = len(sv.sp("state")["tabs"])
    t.ok("x is Vim's", key("x", settle=0.8)["taken"] is True)
    t.ok("x closes the tab", len(sv.sp("state")["tabs"]) == count - 1, len(sv.sp("state")["tabs"]))

    # Off again: j is the page's.
    sv.cmd({"do": "settings", "set": "vim.keys", "value": False}); time.sleep(0.5)
    t.ok("off again: j is the page's", key("j")["taken"] is False)

    # ⌘T's field floating over the page (Settings › New tab in a floating
    # field, read at launch): B raises that one, and Escape leaves the page.
    sv.setup(**{"newtab.floating": True}); sv.launch()
    a = sv.page("long"); b = sv.page("tall")
    sv.sp("select", id=b); time.sleep(0.5); sv.cmd({"do": "keeppage"}); tall = sv.url(sv.sp("state"), b)
    sv.sp("select", id=a); time.sleep(0.5)
    sv.cmd({"do": "settings", "set": "vim.keys", "value": True}); time.sleep(0.5)
    key("B", settle=1.0)
    st = field()
    t.ok("floating, B raises the field over the page", st["editing"] and st["address"] != tall
         and placeholder() == "New tab: search bookmarks" and st["offers"] and st["picked"] == 0, (st, placeholder()))
    key(ESC, settle=0.5)
    t.ok("and Escape puts it away, the page as it was", not field()["editing"] and front().startswith(a.lower()), field())
    count = len(sv.sp("state")["tabs"])
    key("B", settle=1.0); sv.cmd({"do": "suggest", "action": "go"}); time.sleep(1.2)
    t.ok("Return opens the bookmark in a new tab", len(sv.sp("state")["tabs"]) == count + 1 and field()["address"] == tall
         and not front().startswith(a.lower()), (len(sv.sp("state")["tabs"]), count, field()["address"]))
finally:
    sv.finish()
t.done()
sys.exit(1 if t.failed else 0)
