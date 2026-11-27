#!/usr/bin/env python3
"""Settings › Keyboard & Mouse › Vim keys (Vim.swift, docs/VIM.md).

Build first (`./build.sh`), then `python3 Tests/vim_keys.py`. Uses the split
suite's harness: started hidden, no window made or shown, everything removed
afterwards. Keys go through the window's own key handling (bench `vimkey`),
then to the page if nothing took them.

Off (as it ships), j is the page's. On: j/d/G/gg scroll the page, K and J
change tabs (J the tab below in a column, K the one to the right across the top), / opens the find bar, i hands every key to the page until
Escape, a box with the caret keeps every key and Escape lets it go, ? lists
the keys. ⌘ keys are never Vim's.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("vim-keys")
t = sv.T()

CODES = {"f": 3, "F": 3, "s": 1, "e": 14, "h": 4, "j": 38, "k": 40, "d": 2, "u": 32, "g": 5, "G": 5, "K": 40, "J": 38, "i": 34, "x": 7, "/": 26, "?": 27, "a": 0}


def key(ch, mods=None, ignoring=None, settle=0.5):
    req = {"do": "vimkey", "chars": ch, "code": 53 if ch == "\x1b" else CODES[ch], "mods": mods or []}
    if ignoring: req["ignoring"] = ignoring
    if ch.isupper() and "shift" not in req["mods"]: req["mods"].append("shift")
    answer = sv.cmd(req); time.sleep(settle)
    return answer


ESC = "\x1b"


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

    # Hint letters of one's own.
    sv.cmd({"do": "settings", "set": "vim.hints", "value": "hje"}); time.sleep(0.4)
    links = "".join(f"<button onclick=\"document.title='b{n}'\">b{n}</button> " for n in range(4))
    sv.ev(a, "document.body.innerHTML = " + repr(links) + "; true"); time.sleep(0.4)
    # Four with h j e: e, hh, j, hj. j alone is the third.
    key("f"); done = key("j", settle=0.8)
    t.ok("hints made of one's own letters", done["hints"] == "" and sv.ev(a, "document.title") == "b2",
         (done, sv.ev(a, "document.title")))
    sv.cmd({"do": "settings", "set": "vim.hints", "value": "sadfjklewcmpgh"}); time.sleep(0.3)

    # x closes the tab in front, as ⌘W.
    count = len(sv.sp("state")["tabs"])
    t.ok("x is Vim's", key("x", settle=0.8)["taken"] is True)
    t.ok("x closes the tab", len(sv.sp("state")["tabs"]) == count - 1, len(sv.sp("state")["tabs"]))

    # Off again: j is the page's.
    sv.cmd({"do": "settings", "set": "vim.keys", "value": False}); time.sleep(0.5)
    t.ok("off again: j is the page's", key("j")["taken"] is False)
finally:
    sv.finish()
t.done()
sys.exit(1 if t.failed else 0)
