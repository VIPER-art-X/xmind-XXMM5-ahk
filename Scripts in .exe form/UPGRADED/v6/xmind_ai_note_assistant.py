#!/usr/bin/env python3
"""
xmind_ai_note_assistant.py
===========================
A small standalone Windows tool -- separate from the .xmind BUILDER
script on purpose, since this one only ever touches an already-open
XMind Desktop window, never a .xmind file on disk.

What it does
------------
A tiny always-on-top floating box sits on your screen with two fields
(Node Name, Instructions) and one button. Workflow:

  1. Open a node's note in the real XMind Desktop app, so it's focused.
  2. Type the node name + instructions into this floating box.
  3. Click "Ask AI -> Paste".
  4. The FIRST click of a session launches one headless, PROFILED Chromium
     (Playwright) and leaves it running; every click after that reuses the
     SAME browser -- it just opens a fresh tab, goes to DeepSeek, submits
     "<node name>\n<instructions>", waits for the reply to finish
     streaming, and scrapes the text (see _BrowserWorker / ask_deepseek).
     Chromium is only relaunched if it wasn't already running, never once
     per click -- that keeps every query fast after the first and avoids
     repeatedly paying Chromium's startup cost.
  4.5. Once the reply is scraped, the tab is closed. The browser process
     stays open in the background for the next query. (Chat history on
     the DeepSeek account is left alone -- clean it up manually if
     needed.)
  5. In "Note" mode, every non-blank line of the reply is force-turned
     into a REAL rendered H1 heading -- not literal '#' characters -- by
     building an actual HTML fragment ("<h1>...</h1>" per line) and
     putting it on the clipboard using Windows' CF_HTML ("HTML Format")
     clipboard format (see build_note_html / set_clipboard_html). This
     does NOT rely on the AI having followed the H1 instructions in the
     prompt -- the heading tags are added in code, deterministically,
     every time. A plain "# ..." markdown fallback (ensure_h1_headers) is
     included alongside it for anything that only reads plain text.
  6. If for any reason the CF_HTML clipboard write can't be done (e.g. a
     Windows clipboard API call fails), it falls back to writing the
     plain "# ..." version to a .txt file in %TEMP% and piping THAT onto
     the clipboard via Windows' clip.exe (see set_clipboard_text) -- in
     that fallback case XMind will show literal "# " text rather than a
     rendered heading, since real formatting requires the CF_HTML route.
  7. XMind is brought back to the foreground and a synthetic Ctrl+V is
     sent, pasting the clipboard contents directly into the still-open,
     still-focused note field.

Why clipboard+paste instead of editing the .xmind file directly:
XMind Desktop does not live-reload a file that's changed on disk while
it's open, so writing into content.json wouldn't show up in the note
you're looking at until you closed and reopened the file. Simulating
the paste is the only way to land text into an already-open note.

One-time setup
--------------
  pip install playwright
  playwright install chromium

This tool reuses the SAME saved Chromium profile as the other (M3-165)
script's "Open Browser & Search There" mini-browser -- if you've
already logged into DeepSeek through that, nothing else to do here.
Otherwise, run this script once with --login to open a normal, visible
browser window on that same profile and log in by hand.

    python xmind_ai_note_assistant.py --login
    python xmind_ai_note_assistant.py

Caveats
-------
- Windows only (uses ctypes/user32 for window focus + synthetic
  keystrokes).
- The real-H1-heading route (build_note_html / set_clipboard_html) only
  produces an actual rendered heading if XMind's note editor accepts
  pasted rich text (HTML) and renders "<h1>" as a real heading style. If
  XMind's note field only ever accepts plain text no matter what's on the
  clipboard, you'll see literal "# " text either way, and the CF_HTML
  work is effectively wasted (though harmless) -- there's no way to force
  an app to render formatting it doesn't support on paste.
- While the AI query + paste sequence is running, this window is put into
  WS_EX_NOACTIVATE mode (see set_toolbar_noactivate) so it can't steal
  Windows' foreground/active status back from XMind mid-sequence, which
  was previously breaking the paste. It's switched back to normal right
  after (success or failure), so clicking into the Node Name / Instructions
  fields to type still works as usual between queries.
- Automating DeepSeek's web UI instead of calling an official API is
  against most such sites' Terms of Service, and the CSS selectors
  below WILL break whenever DeepSeek reshuffles their page -- treat the
  selectors in `_DEEPSEEK_SELECTORS` as the first thing to fix if
  queries start failing. They're a best-effort starting point and
  haven't been verified against the live site -- open DevTools on
  chat.deepseek.com and confirm/update them before relying on this.
- This never touches your .xmind file. It only reads/writes the
  Windows clipboard and sends a Ctrl+V keystroke to whatever window
  was last focused, so it fires ONLY when that window belongs to
  XMind.exe.
- The shared Chromium profile can only be open in ONE browser at a
  time. Close the other script's mini-browser before using "Ask AI ->
  Paste" here, and vice versa. Once THIS script's own persistent
  Chromium is up (after your first query), it holds that profile for
  the rest of the session.
- Clicking this window's own close (X) button does NOT quit the app or
  the browser anymore -- it just hides the window, so the paired AHK
  script's F11 key can bring the same running session back (same
  browser, same Node/Note tab, same typed instructions) instead of
  relaunching Python and paying Chromium's startup cost again. The
  browser is torn down when this Python process actually exits.
- Node/Note "search": the paired AHK script lets you hold the right
  mouse button and press XButton2 (mouse button 5) inside XMind to
  capture the selected node's name, or the currently open note's
  content, and hand it to this app in the background (see
  FloatingToolbar._poll_bridge / _handle_bridge_request) -- as if you'd
  typed it in and clicked "Ask AI -> Paste" yourself. Whichever tab
  (Node/Note) is selected here decides what happens with that text.
"""

import atexit
import ctypes
import html
import os
import queue
import random
import re
import string
import subprocess
import sys
import tempfile
import threading
import time
from ctypes import wintypes

if sys.platform != "win32":
    sys.exit("xmind_ai_note_assistant.py only supports Windows (uses ctypes/user32).")

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

# ----------------------------------------------------------------------------
# ctypes signatures -- WITHOUT these, ctypes assumes every user32/kernel32
# call returns a plain 32-bit signed int. Window handles are pointer-sized;
# on 64-bit Windows that truncation/sign-flip silently corrupts HWND values,
# which is exactly why focus-tracking comparisons could never match reliably.
# ----------------------------------------------------------------------------
user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetForegroundWindow.argtypes = []
user32.IsWindow.restype = wintypes.BOOL
user32.IsWindow.argtypes = [wintypes.HWND]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.SetForegroundWindow.restype = wintypes.BOOL
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.ShowWindow.restype = wintypes.BOOL
user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.BringWindowToTop.restype = wintypes.BOOL
user32.BringWindowToTop.argtypes = [wintypes.HWND]
user32.AttachThreadInput.restype = wintypes.BOOL
user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
user32.SendInput.restype = wintypes.UINT
user32.GetWindowLongW.restype = wintypes.LONG
user32.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
user32.SetWindowLongW.restype = wintypes.LONG
user32.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, wintypes.LONG]

# -- GetGUIThreadInfo, for checking which CHILD control currently has
# keyboard focus inside the target app. This is a different thing from
# "which top-level window is foreground" (that's all force_foreground
# checks): a top-level window can be the foreground window while its
# actual note-editor control/popup has already lost focus or closed, and
# in that case a synthetic Ctrl+V still "succeeds" at the Win32 level but
# lands nowhere useful. Checking hwndFocus right before pasting is how
# _on_success below tells "really pasted into the note" apart from
# "pasted into nothing because the note field wasn't there anymore".
class GUITHREADINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("hwndActive", wintypes.HWND),
        ("hwndFocus", wintypes.HWND),
        ("hwndCapture", wintypes.HWND),
        ("hwndMenuOwner", wintypes.HWND),
        ("hwndMoveSize", wintypes.HWND),
        ("hwndCaret", wintypes.HWND),
        ("rcCaret", wintypes.RECT),
    ]


user32.GetGUIThreadInfo.restype = wintypes.BOOL
user32.GetGUIThreadInfo.argtypes = [wintypes.DWORD, ctypes.POINTER(GUITHREADINFO)]
user32.GetClassNameW.restype = ctypes.c_int
user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
kernel32.GetCurrentThreadId.restype = wintypes.DWORD
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                                 wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel32.CloseHandle.restype = wintypes.BOOL
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]

# -- Clipboard APIs, for writing a REAL rich-text (CF_HTML) heading rather
# than plain "# " text. Tk's clipboard_append can only ever write plain
# text, so putting an actual rendered <h1> on the clipboard has to go
# through these directly.
user32.OpenClipboard.restype = wintypes.BOOL
user32.OpenClipboard.argtypes = [wintypes.HWND]
user32.EmptyClipboard.restype = wintypes.BOOL
user32.EmptyClipboard.argtypes = []
user32.CloseClipboard.restype = wintypes.BOOL
user32.CloseClipboard.argtypes = []
user32.SetClipboardData.restype = wintypes.HANDLE
user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
user32.RegisterClipboardFormatW.restype = wintypes.UINT
user32.RegisterClipboardFormatW.argtypes = [wintypes.LPCWSTR]
kernel32.GlobalAlloc.restype = wintypes.HANDLE
kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
kernel32.GlobalLock.restype = wintypes.LPVOID
kernel32.GlobalLock.argtypes = [wintypes.HANDLE]
kernel32.GlobalUnlock.restype = wintypes.BOOL
kernel32.GlobalUnlock.argtypes = [wintypes.HANDLE]
kernel32.GlobalFree.restype = wintypes.HANDLE
kernel32.GlobalFree.argtypes = [wintypes.HANDLE]

_GMEM_MOVEABLE = 0x0002
_CF_UNICODETEXT = 13

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
# Reuses the SAME saved Chromium profile as the other (M3-165) script's
# "Open Browser & Search There" mini-browser / "Log In / Clear CAPTCHA"
# button (_WIE_PROFILE_DIR there). If you've already logged into DeepSeek
# through that mini-browser, this tool picks that session up automatically
# -- no separate login needed. Change this if you'd rather keep them apart.
_PROFILE_DIR = os.path.join(os.path.expanduser("~"), ".webpage_image_extractor", "chromium_profile")
_LOGIN_MARKER = os.path.join(os.path.dirname(_PROFILE_DIR), "login_complete.txt")
_XMIND_PROCESS_NAMES = ("xmind.exe",)          # lower-cased exe name(s) to allow pasting into
_DEEPSEEK_URL = "https://chat.deepseek.com/"
# NOTE: deliberately no forced/spoofed User-Agent here -- the automated
# worker's Chromium is left to report its own real UA (see
# _launch_persistent_context), matching what run_login_setup's visible
# browser used when the session was first logged in. A previous version
# forced a hardcoded, stale UA string on the headless worker while login
# used the browser's genuine one; that mismatch (real cookies + spoofed,
# inconsistent fingerprint) looked like session hijacking to DeepSeek and
# could force the whole account's session to invalidate.

# CSS selectors for chat.deepseek.com -- the single most likely thing to
# need updating if this stops working. Kept in one place on purpose.
# "composer" and "assistant_messages" are confirmed against real DeepSeek
# automation scripts as of Sep 2026. There's no confirmed selector for a
# "stop generating" button, so completion is instead detected by polling
# the last reply's text until it stops changing (see ask_deepseek).
_DEEPSEEK_SELECTORS = {
    "composer": "textarea[placeholder='Message DeepSeek']",
    "assistant_messages": ".ds-markdown",
}


# Prepended to the user's Node-name/Instructions text so the AI's reply
# comes back as a proper Stage-1 learning-mind-map skeleton (the full v5
# prompt family below, used verbatim per tier) instead of a shallow
# one-level outline. Pastes cleanly into XMind as a tab-indented tree once
# the surrounding code-block fence and any DeepSeek UI chrome are stripped
# off (see strip_code_block_chrome below).
#
# Four size tiers control roughly how big/deep the generated mindmap is,
# from a lean essentials-only map (Short) up to the fully scaffolded,
# textbook-depth map (Ultra). Selected in the UI via the "Mindmap size"
# dropdown on the Node tab (see FloatingToolbar.size_var).
_NODE_SIZE_TIERS = ("Very Short", "Short", "Medium", "Super", "Ultra")
_NODE_DEFAULT_SIZE_TIER = "Very Short"

_NODE_FORMAT_INSTRUCTIONS_BY_SIZE = {
    "Very Short": '# LEARNING MIND MAP SKELETON — Tab-Hierarchy Generator (STAGE 1) [VERY SHORT]\n\n## WHAT THIS PROMPT IS FOR\n\nThis is a **two-stage pipeline**, and this prompt is **Stage 1 only**.\n\n- **Stage 1 (THIS prompt):** Given a subject, field, or topic, output ONLY the **skeleton** — every node name, arranged as a hierarchy using **tab indentation**. No notes. No equations. No explanations. Just names, correctly nested.\n- **Stage 2 (a separate prompt, run in a DIFFERENT chat):** Takes the finished Stage-1 skeleton and, node by node, converts it into the full export format, filling in notes and equations for each node Stage 1 already named.\n\n**Your job in this chat is Stage 1 ONLY.** Never write `lvl1[1]`-style markers, never write `note:`, `equation:`, or any `{...}` block, never add explanatory prose describing a node.\n\n**This is the VERY SHORT size tier: the goal is a small, lean map — the essential skeleton only, not exhaustive coverage.** Prefer fewer, well-chosen branches over completeness. Do not add scaffolding branches "just in case" — only include what the topic actually calls for at a glance.\n\n---\n\n## OUTPUT FORMAT\n\n1. **One node per line.**\n2. **Indentation = depth.** Exactly one **tab character** per level of depth below the root.\n3. **A line contains ONLY the node\'s name.** Plain text. No numbering, no bullets, no dashes, no parenthetical asides, no markers, no `{...}` overrides, no notes.\n4. **No blank lines between nodes.**\n5. **Wrap the entire output in a single fenced code block** (triple backticks, no language tag).\n6. **Do not explain the tree, do not add commentary before or after the code block.**\n\n**Example shape (topic: "Citrus"):**\n```\nCitrus\n\tSweet Citrus\n\t\tOrange\n\t\tMandarin\n\tSour Citrus\n\t\tLemon\n\t\tLime\n```\n\n---\n\n## ⛔ RULE 1 (MOST IMPORTANT): ONE NODE = ONE ATOMIC IDEA, ALWAYS\n\nBefore writing any node name, ask: **"Is this actually more than one thing?"**\n\nA node name is broken and must be split if it contains any of these tells:\n- **A comma-separated list** of two or more items: `Trichophyton (Tinea corporis, pedis, cruris, unguium)` → the organism is one node, each disease is its own child.\n- **Parenthetical content that is itself a list, a definition, a mechanism, or a second fact.**\n- **"and" / "or" joining two nameable things**: `Chlamydospores and Arthrospores` → two sibling nodes.\n- **A colon or dash followed by an explanation.**\n\nA short parenthetical alias with no internal list (`Malaria (Plasmodium)`) is fine — anything smuggling in an extra fact is not.\n\n**A sibling relationship is not a child relationship.** Two things of the same kind (two species, two drugs in a class) are siblings under a shared parent, never one nested inside the other.\n\n---\n\n## RULE 2: LOOSE BACKBONE (adapt per subject, don\'t force it)\n\nUse a light version of the standard learning schema as a starting point — root, then major branches, then specific items, then a fact or two under each — but **do not force every layer to exist for every item.** For VERY SHORT, it\'s fine (and expected) for a leaf item to go straight from its name to 1-3 key facts without a full "Attribute Group" layer in between, if that keeps things lean without cramming two facts into one node.\n\n**Do not add archetype scaffolding branches the source material doesn\'t call for.** Unlike the fuller size tiers, VERY SHORT does **not** require adding placeholder branches like `Risk Factors`, `Diagnosis`, `Mechanism of Action`, etc. just because a node matches a known archetype (disease, drug, organism...). Only include a branch if it\'s naturally part of what\'s being asked for, or if leaving it out would make an included sibling fact look cramped or context-free.\n\n**Do not add `Comparison` nodes.** Skip the comparison-slot convention entirely at this tier — it adds structure the VERY SHORT tier doesn\'t need.\n\n---\n\n## RULE 3: DEPTH TARGETS (VERY SHORT — these are ALSO a ceiling, not just a floor)\n\n| Request scope | Target depth (levels from root) |\n|---|---|\n| A single narrow topic (e.g. "the Krebs Cycle") | 2-3 |\n| A chapter or unit (e.g. "Mycology") | 3 |\n| A full subject (e.g. "Microbiology") | 3-4 |\n| A full field spanning multiple subjects | 4 |\n\nStay close to these numbers. If a branch is going much deeper than the target, that\'s a sign to trim to the most essential facts rather than to keep drilling down — VERY SHORT favors breadth of the main ideas over exhaustive depth.\n\n---\n\n## RULE 4: NAMING STANDARDS FOR EACH NODE\n\n- **Short.** A node name should read like a label, not a sentence (roughly 1-6 words).\n- **No restating the parent.** (`Fungi` → `Types of Fungi` → `Fungus Types` is circular padding, not depth.)\n- **No bare, empty category nodes.** Every node must have at least one child (if grouping) or be a genuine leaf fact (if terminal).\n- **Consistent grammatical form among siblings.**\n- **Use proper scientific/technical names exactly as known.**\n\n---\n\n## RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS\n\nA later automated step fetches one picture per node by searching that node\'s **name, exactly as written**. It auto-disambiguates a repeated name by prefixing it with its parent\'s name (then grandparent, etc.) until unique.\n\n1. **A recurring category name across different branches is fine — leave it bare.** Don\'t pre-qualify a category name with its ancestor baked in (write `Diagnosis` under `Tuberculosis`, not `Tuberculosis Diagnosis`).\n2. **Never give two children of the same parent the identical name.**\n3. **Watch for a name colliding with an unrelated node where the parent names ALSO collide** — fix by making the names more specific, don\'t rely on the rescue.\n4. **Name leaf-level facts concretely, not generically** (`Night Sweats`, not `Symptom`).\n\n---\n\n## RULE 5: STRUCTURAL CONSISTENCY\n\n- **Depth increases by exactly one tab at a time going down** — never jump from 2 tabs to 4 tabs in consecutive lines.\n- **Never use spaces to fake indentation.** Only real tab characters count as one level.\n\n---\n\n## ⛔ SKELETON VERIFICATION CHECKLIST (run before finishing)\n\n- [ ] **Atomicity:** scan every node name for a comma, parenthetical list, "and"/"or", or colon-plus-explanation. Split anything that\'s hiding a second fact.\n- [ ] **Size discipline:** is anything here that isn\'t actually essential to understanding the topic at a glance? If a branch feels like padding, cut it.\n- [ ] **Format:** every line uses only tabs; depth never jumps by more than one tab; no `note:`, `equation:`, `{`, `}`, `lvl`, numbering, or bullet characters anywhere; the whole thing is inside one fenced code block with nothing else outside it.\n- [ ] **IFM discipline (Rule 4.5):** no two children of the same parent share a name; no archetype/category name is pre-qualified with an ancestor\'s name baked in; leaf facts are named concretely.\n\n---\n\n## YOUR TASK\n\nWhen the user names a field, subject, chapter, or topic:\n\n1. Determine the scope and its VERY SHORT depth target (Rule 3).\n2. Draft a lean tree: major branches, then the handful of specific items and facts that actually matter — no forced scaffolding, no comparison slots.\n3. Apply Rule 1 to every node as you go: never let two facts share one node name.\n4. Apply Rule 4.5 as you name nodes.\n5. Run the Verification Checklist.\n6. Output **ONLY** the tab-indented skeleton in a single fenced code block. No notes, no equations, no commentary before or after.\n\nNow generate the skeleton the user requested.',
    "Short": '# LEARNING MIND MAP SKELETON — Tab-Hierarchy Generator (STAGE 1) [SHORT]\n\n## WHAT THIS PROMPT IS FOR\n\nThis is a **two-stage pipeline**, and this prompt is **Stage 1 only**.\n\n- **Stage 1 (THIS prompt):** Given a subject, field, or topic, output ONLY the **skeleton** — every node name, arranged as a hierarchy using **tab indentation**. No notes. No equations. No explanations. Just names, correctly nested.\n- **Stage 2 (a separate prompt, run in a DIFFERENT chat):** Takes the finished Stage-1 skeleton and, node by node, converts it into the full export format, filling in notes and equations for each node Stage 1 already named.\n\n**Your job in this chat is Stage 1 ONLY.** Never write `lvl1[1]`-style markers, never write `note:`, `equation:`, or any `{...}` block, never add explanatory prose describing a node.\n\n**This is the SHORT size tier: one notch up from the leanest (VERY SHORT) tier.** It goes one level deeper on average so the shape of each branch is a little clearer, but it is still a lean map, not a study guide — no forced scaffolding branches, no comparison nodes. Prefer fewer, well-chosen branches over completeness.\n\n---\n\n## OUTPUT FORMAT\n\n1. **One node per line.**\n2. **Indentation = depth.** Exactly one **tab character** per level of depth below the root.\n3. **A line contains ONLY the node\'s name.** Plain text. No numbering, no bullets, no dashes, no parenthetical asides, no markers, no `{...}` overrides, no notes.\n4. **No blank lines between nodes.**\n5. **Wrap the entire output in a single fenced code block** (triple backticks, no language tag).\n6. **Do not explain the tree, do not add commentary before or after the code block.**\n\n**Example shape (topic: "Citrus"):**\n```\nCitrus\n	Sweet Citrus\n		Orange\n			Navel Orange\n		Mandarin\n	Sour Citrus\n		Lemon\n		Lime\n```\n\n---\n\n## ⛔ RULE 1 (MOST IMPORTANT): ONE NODE = ONE ATOMIC IDEA, ALWAYS\n\nBefore writing any node name, ask: **"Is this actually more than one thing?"**\n\nA node name is broken and must be split if it contains any of these tells:\n- **A comma-separated list** of two or more items: `Trichophyton (Tinea corporis, pedis, cruris, unguium)` → the organism is one node, each disease is its own child.\n- **Parenthetical content that is itself a list, a definition, a mechanism, or a second fact.**\n- **"and" / "or" joining two nameable things**: `Chlamydospores and Arthrospores` → two sibling nodes.\n- **A colon or dash followed by an explanation.**\n\nA short parenthetical alias with no internal list (`Malaria (Plasmodium)`) is fine — anything smuggling in an extra fact is not.\n\n**A sibling relationship is not a child relationship.** Two things of the same kind (two species, two drugs in a class) are siblings under a shared parent, never one nested inside the other.\n\n---\n\n## RULE 2: LOOSE BACKBONE (adapt per subject, don\'t force it)\n\nUse a light version of the standard learning schema as a starting point — root, then major branches, then specific items, then a fact or two under each — but **do not force every layer to exist for every item.** It\'s fine (and expected) for a leaf item to go straight from its name to 1-3 key facts without a full "Attribute Group" layer in between, if that keeps things lean without cramming two facts into one node.\n\n**Do not add archetype scaffolding branches the source material doesn\'t call for**, the same as the leanest tier — this tier is not the place for placeholder branches like `Risk Factors`, `Diagnosis`, `Mechanism of Action`, etc. just because a node matches a known archetype. Only include a branch if it\'s naturally part of what\'s being asked for.\n\n**Do not add `Comparison` nodes.** Skip the comparison-slot convention entirely at this tier too — that starts at the MEDIUM tier and up.\n\n---\n\n## RULE 3: DEPTH TARGETS (SHORT — these are ALSO close to a ceiling, not just a floor)\n\n| Request scope | Target depth (levels from root) |\n|---|---|\n| A single narrow topic (e.g. "the Krebs Cycle") | 3 |\n| A chapter or unit (e.g. "Mycology") | 3-4 |\n| A full subject (e.g. "Microbiology") | 4-5 |\n| A full field spanning multiple subjects | 5 |\n\nStay close to these numbers — one notch deeper than the leanest tier, not a jump to a full study map. If a branch is going much deeper than the target, trim to the most essential facts rather than keep drilling down.\n\n---\n\n## RULE 4: NAMING STANDARDS FOR EACH NODE\n\n- **Short.** A node name should read like a label, not a sentence (roughly 1-6 words).\n- **No restating the parent.** (`Fungi` → `Types of Fungi` → `Fungus Types` is circular padding, not depth.)\n- **No bare, empty category nodes.** Every node must have at least one child (if grouping) or be a genuine leaf fact (if terminal).\n- **Consistent grammatical form among siblings.**\n- **Use proper scientific/technical names exactly as known.**\n\n---\n\n## RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS\n\nA later automated step fetches one picture per node by searching that node\'s **name, exactly as written**. It auto-disambiguates a repeated name by prefixing it with its parent\'s name (then grandparent, etc.) until unique.\n\n1. **A recurring category name across different branches is fine — leave it bare.** Don\'t pre-qualify a category name with its ancestor baked in (write `Diagnosis` under `Tuberculosis`, not `Tuberculosis Diagnosis`).\n2. **Never give two children of the same parent the identical name.**\n3. **Watch for a name colliding with an unrelated node where the parent names ALSO collide** — fix by making the names more specific, don\'t rely on the rescue.\n4. **Name leaf-level facts concretely, not generically** (`Night Sweats`, not `Symptom`).\n\n---\n\n## RULE 5: STRUCTURAL CONSISTENCY\n\n- **Depth increases by exactly one tab at a time going down** — never jump from 2 tabs to 4 tabs in consecutive lines.\n- **Never use spaces to fake indentation.** Only real tab characters count as one level.\n\n---\n\n## ⛔ SKELETON VERIFICATION CHECKLIST (run before finishing)\n\n- [ ] **Atomicity:** scan every node name for a comma, parenthetical list, "and"/"or", or colon-plus-explanation. Split anything that\'s hiding a second fact.\n- [ ] **Size discipline:** is anything here that isn\'t actually essential? If a branch feels like padding, cut it. No scaffolding branches, no `Comparison` nodes.\n- [ ] **Depth:** does the tree land roughly one notch deeper than a bare-essentials skeleton, per the Rule 3 table, without ballooning further?\n- [ ] **Format:** every line uses only tabs; depth never jumps by more than one tab; no `note:`, `equation:`, `{`, `}`, `lvl`, numbering, or bullet characters anywhere; the whole thing is inside one fenced code block with nothing else outside it.\n- [ ] **IFM discipline (Rule 4.5):** no two children of the same parent share a name; no archetype/category name is pre-qualified with an ancestor\'s name baked in; leaf facts are named concretely.\n\n---\n\n## YOUR TASK\n\nWhen the user names a field, subject, chapter, or topic:\n\n1. Determine the scope and its SHORT depth target (Rule 3).\n2. Draft a lean tree, one notch deeper than the bare-essentials tier — the handful of specific items and facts that actually matter, no forced scaffolding, no comparison slots.\n3. Apply Rule 1 to every node as you go: never let two facts share one node name.\n4. Apply Rule 4.5 as you name nodes.\n5. Run the Verification Checklist.\n6. Output **ONLY** the tab-indented skeleton in a single fenced code block. No notes, no equations, no commentary before or after.\n\nNow generate the skeleton the user requested.',
    "Medium": '# LEARNING MIND MAP SKELETON — Tab-Hierarchy Generator (STAGE 1) [MEDIUM]\n\n## WHAT THIS PROMPT IS FOR\n\nThis is a **two-stage pipeline**, and this prompt is **Stage 1 only**.\n\n- **Stage 1 (THIS prompt):** Given a subject, field, or topic, output ONLY the **skeleton** — every node name, arranged as a hierarchy using **tab indentation**. No notes. No equations. No explanations. Just names, correctly nested.\n- **Stage 2 (a separate prompt, run in a DIFFERENT chat):** Takes the finished Stage-1 skeleton and, node by node, converts it into the full export format, filling in notes and equations for each node Stage 1 already named.\n\n**Your job in this chat is Stage 1 ONLY.** Never write `lvl1[1]`-style markers, never write `note:`, `equation:`, or any `{...}` block, never add explanatory prose describing a node.\n\n**This is the MEDIUM size tier: a solidly useful study map, more than the bare essentials but not exhaustive.** Add the handful of extra branches that clearly round out understanding — but don\'t chase full textbook-chapter completeness; that\'s what the larger tiers are for.\n\n---\n\n## ⛔ THE CORE PROBLEM THIS PROMPT EXISTS TO FIX\n\nMind maps built in one shot tend to fail in a specific, predictable way: the AI stuffs multiple distinct facts into one node\'s name, using commas and parentheses as a substitute for actually branching the tree.\n\n**Real example of the failure:**\n```\nTrichophyton (Tinea corporis, pedis, cruris, unguium)\n```\nThis single node is secretly **five separate facts** — the organism, plus four distinct diseases it causes — flattened into one line.\n\n**This is the single most important thing this prompt exists to prevent.**\n\n---\n\n## OUTPUT FORMAT\n\n1. **One node per line.**\n2. **Indentation = depth.** Exactly one **tab character** per level of depth below the root.\n3. **A line contains ONLY the node\'s name.** Plain text. No numbering, no bullets, no dashes, no parenthetical asides, no markers, no `{...}` overrides, no notes.\n4. **No blank lines between nodes.**\n5. **Wrap the entire output in a single fenced code block** (triple backticks, no language tag).\n6. **Do not explain the tree, do not add commentary before or after the code block.**\n\n**Example shape (topic: "Citrus"):**\n```\nCitrus\n\tSweet Citrus\n\t\tOrange\n\t\t\tNavel Orange\n\t\t\tValencia Orange\n\t\tMandarin\n\tSour Citrus\n\t\tLemon\n\t\tLime\n\t\tGrapefruit\n```\n\n---\n\n## ⛔ RULE 1 (MOST IMPORTANT): ONE NODE = ONE ATOMIC IDEA, ALWAYS\n\nBefore writing any node name, ask: **"Is this actually more than one thing?"**\n\nA node name is broken and must be split if it contains any of these tells:\n- **A comma-separated list** of two or more items (diseases, examples, types, symptoms, dates, names...).\n- **Parenthetical content that is itself a list, a definition, a mechanism, or a second fact**, not just a short one-or-two-word disambiguator.\n- **"and" / "or" joining two nameable things.**\n- **A colon or dash followed by an explanation.**\n\nA parenthetical is allowed to stay ONLY when it\'s a single short disambiguator with no internal list (`Malaria (Plasmodium)`).\n\n**A sibling relationship is not a child relationship.** Two things of the same kind (two species, two drugs in a class) are siblings under a shared parent, never one nested inside the other. A slash, semicolon, or "or" joining two names is cramming, exactly like a comma.\n\n---\n\n## RULE 2: THE STANDARD LEARNING SCHEMA (adapt per subject, don\'t force it rigidly)\n\nUse this as a loose backbone, then apply Rule 1 underneath every level:\n\n```\nField / Subject                      (root)\n\tMajor Branch / Domain\n\t\tChapter / Category\n\t\t\tTopic / Specific Item\n\t\t\t\tAttribute Group        (e.g. Clinical Presentation, Mechanism, Diagnosis)\n\t\t\t\t\tIndividual Fact\n```\n\nNot every subject needs every layer — a narrow topic might start straight at "Chapter" level. The rule that never bends is Rule 1.\n\n---\n\n## RULE 2.5 (LIGHT): ADD THE MOST OBVIOUS MISSING BRANCHES ONLY\n\nRaw source material usually only tells you what\'s directly stated. For MEDIUM, add a **small number of the most obviously missing, high-value branches** a study guide would include — but don\'t run the full archetype checklist from the larger tiers.\n\n**Guideline, not a mandate:** for a Disease/Condition, if the source discusses cause and mechanism but nothing about how it presents, add one `Signs & Symptoms` branch (even as a placeholder for Stage 2 to fill) — but don\'t also force Risk Factors, Prognosis, Prevention, etc. unless they\'re similarly glaring gaps. For a Drug, one `Mechanism of Action` or `Adverse Effects` branch if obviously missing is enough. Pick the 1-2 branches that would most help a learner, not the whole textbook checklist.\n\n**Comparison nodes are optional at this tier.** Only add a shared `Comparison` sibling for a group of 2+ same-kind siblings when the contrast is genuinely central and unavoidable (e.g. Gram-positive vs Gram-negative) — don\'t add one for every sibling group.\n\n---\n\n## RULE 3: DEPTH TARGETS (MEDIUM)\n\n| Request scope | Target depth (levels from root) |\n|---|---|\n| A single narrow topic (e.g. "the Krebs Cycle") | 3-4 |\n| A chapter or unit (e.g. "Mycology") | 4 |\n| A full subject (e.g. "Microbiology") | 5 |\n| A full field spanning multiple subjects | 6 |\n\nIf a whole branch tops out noticeably shallower than sibling branches around it, check for crammed nodes (Rule 1) before assuming it\'s just simple.\n\n---\n\n## RULE 4: NAMING STANDARDS FOR EACH NODE\n\n- **Short.** A node name should read like a label, not a sentence (roughly 1-6 words).\n- **No restating the parent.**\n- **No bare, empty category nodes.** Every node must have at least one child (if grouping) or be a genuine leaf fact.\n- **Consistent grammatical form among siblings.**\n- **Use proper scientific/technical names exactly as known.**\n\n---\n\n## RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS\n\nA later automated step fetches one picture per node by searching that node\'s **name, exactly as written**. It auto-disambiguates a repeated name by prefixing it with its parent\'s name (then grandparent, etc.) until unique.\n\n1. **A recurring category name across different branches is fine — leave it bare.** Don\'t pre-qualify it with its ancestor baked in (`Diagnosis` under `Tuberculosis`, not `Tuberculosis Diagnosis`).\n2. **Never give two children of the same parent the identical name.**\n3. **Watch for a name colliding with an unrelated node where the parent names ALSO collide** — fix by making the names more specific.\n4. **Name leaf-level facts concretely, not generically** (`Night Sweats`, not `Symptom`).\n\n---\n\n## RULE 5: STRUCTURAL CONSISTENCY\n\n- **Depth increases by exactly one tab at a time going down.**\n- **Never use spaces to fake indentation.**\n\n---\n\n## ⛔ SKELETON VERIFICATION CHECKLIST (run before finishing)\n\n**A — Atomicity:** scan every node for a comma, a parenthetical list, "and"/"or"/"/" joining two things, or a colon/dash plus explanation — split anything hiding a second fact. Check every parent-child link: is the child really a property of the parent, or a mis-nested sibling?\n\n**B — Depth:** compare the deepest point in each major branch against the Rule 3 target; a branch that falls noticeably short almost always still has a crammed node in it.\n\n**C — Format:** only tabs for indentation; depth never jumps by more than one tab; no `note:`, `equation:`, `{`, `}`, `lvl`, numbering, or bullets anywhere; everything inside one fenced code block, nothing outside it.\n\n**D — Light scaffolding check:** did you add the 1-2 most obviously missing branches per node where relevant (Rule 2.5), without over-adding a full textbook checklist?\n\n**G — IFM discipline:** no duplicate sibling names; no archetype/category name pre-qualified with an ancestor\'s name baked in; leaf facts named concretely.\n\n---\n\n## YOUR TASK\n\nWhen the user names a field, subject, chapter, or topic:\n\n1. Determine the scope and its MEDIUM depth target (Rule 3).\n2. Draft the tree using the Rule 2 schema as a loose backbone.\n3. Apply Rule 1 relentlessly to every node as you go — do not wait until the end. Check every parent-child link: property, or mis-nested sibling?\n4. Apply Rule 2.5 (light touch): add only the handful of most obviously missing branches, and a `Comparison` node only where the contrast is unmissable.\n5. Apply Rule 4.5 as you name nodes.\n6. Run the Verification Checklist (A, B, C, D, G).\n7. Output **ONLY** the tab-indented skeleton in a single fenced code block. No notes, no equations, no commentary before or after.\n\nNow generate the skeleton the user requested.',
    "Super": '# LEARNING MIND MAP SKELETON — Tab-Hierarchy Generator (STAGE 1) [SUPER]\n\n## WHAT THIS PROMPT IS FOR\n\nThis is a **two-stage pipeline**, and this prompt is **Stage 1 only**.\n\n- **Stage 1 (THIS prompt):** Given a subject, field, or topic, output ONLY the **skeleton** — every node name, arranged as a deep hierarchy using **tab indentation**. No notes. No equations. No explanations. Just names, correctly nested.\n- **Stage 2 (a separate prompt, run in a DIFFERENT chat):** Takes the finished Stage-1 skeleton and, node by node, converts it into the full export format, filling in notes and equations for each node Stage 1 already named.\n\n**Your job in this chat is Stage 1 ONLY.** Never write `lvl1[1]`-style markers, never write `note:`, `equation:`, or any `{...}` block, never add explanatory prose describing a node.\n\n**This is the SUPER size tier: thorough and well-scaffolded, one notch below the largest (ULTRA) tier.** Use the full archetype-scaffolding and comparison-node machinery below, but with core branch lists rather than the exhaustive ones, and lighter external-verification requirements.\n\n---\n\n## ⛔ THE CORE PROBLEM THIS PROMPT EXISTS TO FIX\n\nMind maps built in one shot tend to fail in a specific, predictable way: the AI stuffs multiple distinct facts into one node\'s name, using commas and parentheses as a substitute for actually branching the tree. The result LOOKS like a mind map but is really a shallow, bloated list wearing a mind-map costume.\n\n**Real example of the failure:**\n```\nCandida albicans (Thrush, vulvovaginitis, esophagitis, septicemia, germ tube positive)\n```\nThat is **one node name hiding six facts**: the organism, four distinct clinical presentations, and a diagnostic feature. None of those six ideas are the same idea, so they cannot share one node.\n\n**This is the single most important thing this prompt exists to prevent.**\n\n---\n\n## OUTPUT FORMAT\n\n1. **One node per line.**\n2. **Indentation = depth.** Exactly one **tab character** per level of depth below the root.\n3. **A line contains ONLY the node\'s name.** Plain text. No numbering, no bullets, no dashes, no parenthetical asides, no markers, no `{...}` overrides, no notes.\n4. **No blank lines between nodes.**\n5. **Wrap the entire output in a single fenced code block** (triple backticks, no language tag).\n6. **Do not explain the tree, do not add commentary before or after the code block.**\n\n---\n\n## ⛔ RULE 1 (MOST IMPORTANT): ONE NODE = ONE ATOMIC IDEA, ALWAYS\n\nBefore writing any node name, ask: **"Is this actually more than one thing?"**\n\nA node name is broken and must be split if it contains any of these tells:\n- **A comma-separated list** of two or more items.\n- **Parenthetical content that is itself a list, a definition, a mechanism, or a second fact**, not just a short disambiguator.\n- **"and" / "or" joining two nameable things.**\n- **A colon or dash followed by an explanation.**\n\nA parenthetical is allowed to stay ONLY when it\'s a single short disambiguator with no internal list (`Malaria (Plasmodium)`).\n\n**A sibling relationship is not a child relationship.** Two things of the same kind are siblings under a shared parent, never one nested inside the other. A slash, semicolon, or "or" joining two names is cramming, exactly like a comma.\n\n---\n\n## RULE 2: THE STANDARD LEARNING SCHEMA (adapt per subject, don\'t force it rigidly)\n\n```\nField / Subject                      (root)\n\tMajor Branch / Domain             (e.g. Mycology, Virology, Bacteriology)\n\t\tChapter / Category             (e.g. Medically Important Fungi)\n\t\t\tTopic / Subcategory          (e.g. Systemic Dimorphic Mycoses)\n\t\t\t\tSpecific Item              (e.g. Histoplasma capsulatum)\n\t\t\t\t\tAttribute Group          (e.g. Clinical Presentation, Mechanism, Diagnosis)\n\t\t\t\t\t\tIndividual Fact        (e.g. Ohio/Mississippi valleys)\n```\n\nSome subjects need more layers, some need fewer near the top. The one rule that never bends is Rule 1.\n\n---\n\n## RULE 2.5: ARCHETYPE-DRIVEN EXPLANATORY SCAFFOLDING (core branches, not the exhaustive list)\n\nA hierarchy built **for learning** needs more than the raw source material states — symptoms and diagnosis for a disease even if the source only mentioned its cause; adverse effects for a drug even if the source only named it.\n\n**Recognize what KIND of thing a node represents and add its CORE expected branches** (fewer than the full ULTRA checklist — pick the 3-4 that matter most, not every possible one):\n\n| Archetype | Recognize it by | Core branches to check for / add |\n|---|---|---|\n| **Disease / Clinical Condition** | A named illness, syndrome, or disorder | Signs & Symptoms, Diagnosis, Treatment/Management, Complications |\n| **Organism / Pathogen** | A species, genus, or microbe | Morphology/Classification, Transmission, Associated Conditions |\n| **Drug / Therapeutic Agent** | A named medication or drug class | Mechanism of Action, Indications, Adverse Effects |\n| **Process / Mechanism / Pathway** | A biological, chemical, or physical process | Stages/Steps, Key Molecules or Agents Involved, Real-World Significance |\n| **Formula / Equation / Physical Law** | A named law, equation, or quantitative relationship | Variable Definitions, Worked Example, Real-World Application |\n| **Historical Event / Theory / Concept** | A discovery, historical episode, or abstract theory | Historical Context, Modern Relevance |\n| **Sibling Group (Comparison-worthy)** | 2+ sibling nodes of the same kind that are commonly contrasted | A `Comparison` node under their shared parent, with 2-3 dimensions worth contrasting as bare-label children |\n\nWhere you don\'t have enough information to fill a branch accurately, still create the node (a placeholder for Stage 2 to research), rather than skipping it. Don\'t add a branch that plainly doesn\'t apply (a virus doesn\'t need "Dosing").\n\n**Comparison nodes are structural, not prose.** Name the node (`Comparison`) and, if useful, 2-3 bare-label dimensions as children — don\'t describe the actual differences here.\n\n**How to spot a comparison-worthy sibling group:** after writing 2+ sibling nodes, ask "would a student mixing these up be a common, predictable mistake?" If yes, add `Comparison` as an additional sibling, nested under the parent they share.\n\n---\n\n## RULE 2.75: SIBLING BRANCH PARITY (light check)\n\nWhen a subject splits into multiple major sibling sub-fields (e.g. `Bacteriology`, `Virology`, `Mycology`, `Parasitology`), each sibling should open with **some** genuinely-fitting foundational layer (structure, classification, general mechanism) before naming specific instances — not necessarily identical layer names, just an equivalent *kind* of grounding. Once all major siblings are drafted, glance across them: if most open with a foundational layer and one jumps straight to a list of named instances, add a matching foundational branch to that one.\n\n---\n\n## RULE 3: DEPTH TARGETS (SUPER)\n\n| Request scope | Minimum depth (levels from root) |\n|---|---|\n| A single narrow topic (e.g. "the Krebs Cycle") | 4 |\n| A chapter or unit (e.g. "Mycology") | 5 |\n| A full subject (e.g. "Microbiology") | 6, most branches 7+ |\n| A full field spanning multiple subjects | 7, core branches 8+ |\n\nIf a whole branch tops out 2+ levels shallower than the target while sibling branches don\'t, it almost certainly still has crammed nodes in it — re-apply Rule 1.\n\n---\n\n## RULE 4: NAMING STANDARDS FOR EACH NODE\n\n- **Short.** Roughly 1-6 words. If longer, it\'s likely hiding a second fact.\n- **No restating the parent.**\n- **No bare, empty category nodes.** Every node must have a child (if grouping) or be a genuine leaf fact.\n- **Consistent grammatical form among siblings.**\n- **Use proper scientific/technical names exactly as known.**\n\n---\n\n## RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS\n\nA later automated step fetches one picture per node by searching that node\'s **name, exactly as written**. It auto-disambiguates a repeated name by prefixing it with its parent\'s name (then grandparent, etc.) until unique.\n\n1. **A recurring category/archetype name across different branches is expected and correct — leave it bare.** Never pre-qualify it yourself (`Diagnosis` under `Tuberculosis`, not `Tuberculosis Diagnosis`).\n2. **Never give two children of the same parent the identical name.**\n3. **Watch for a name colliding with an unrelated node where the parent names ALSO collide** — fix by making the names more specific; don\'t rely on the ancestor-prefix chain.\n4. **Name leaf-level facts concretely, not generically** (`Night Sweats`, not `Symptom`). Save generic names for genuine grouping/category nodes.\n\n---\n\n## RULE 5: STRUCTURAL CONSISTENCY\n\n- **Depth increases by exactly one tab at a time going down** — never jump from 2 tabs to 4 tabs in consecutive lines.\n- **Never use spaces to fake indentation.**\n\n---\n\n## ⛔ SKELETON VERIFICATION CHECKLIST (run before finishing)\n\n**A — Atomicity (do this pass twice):** scan every node for a comma, a parenthetical list, "and"/"or"/"/" joining two things, or a colon/dash plus explanation. Check every parent-child link for mis-nested siblings.\n\n**B — Depth:** compare the deepest point in each major branch against the Rule 3 target; investigate any branch that falls short for crammed nodes.\n\n**C — Format:** only tabs for indentation; depth never jumps by more than one tab; no `note:`, `equation:`, `{`, `}`, `lvl`, numbering, or bullets anywhere; everything inside one fenced code block, nothing outside it.\n\n**D — Scaffolding:** does each archetype-matching node have its core expected branches (Rule 2.5), without forcing branches that plainly don\'t fit?\n\n**E — Comparison coverage:** does every comparison-worthy sibling group have a shared `Comparison` node, sitting under the parent they share (not nested inside one member)?\n\n**F — Sibling parity:** does every major sibling branch open with some genuinely-fitting foundational layer before naming specific instances, roughly matching its siblings?\n\n**G — IFM discipline:** no duplicate sibling names; no archetype/category name pre-qualified with an ancestor\'s name baked in; leaf facts named concretely.\n\n---\n\n## YOUR TASK\n\nWhen the user names a field, subject, chapter, or topic:\n\n1. Determine the scope and its SUPER depth target (Rule 3).\n2. Draft the tree using the Rule 2 schema as a loose backbone.\n3. Apply Rule 1 relentlessly to every node as you go. Check every parent-child link: property, or mis-nested sibling?\n4. For every node, check Rule 2.5\'s core branches and add a `Comparison` node for every comparison-worthy sibling group.\n5. Once major sibling branches are drafted, run the Rule 2.75 light parity check.\n6. Apply Rule 4.5 as you name nodes.\n7. Run the full Verification Checklist (A-G).\n8. Output **ONLY** the tab-indented skeleton in a single fenced code block. No notes, no equations, no commentary before or after.\n\nNow generate the skeleton the user requested.',
    "Ultra": '# LEARNING MIND MAP SKELETON — Tab-Hierarchy Generator (STAGE 1) [v5]\n\n> **v5 changelog (adds Rule 4.5 — READ THIS FIRST):** New **RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS**, between naming standards (Rule 4) and structural consistency (Rule 5). The downstream IFM/Automatic Search pipeline fetches one image per node by searching that node\'s name, and already auto-disambiguates a repeated name by prefixing it with the parent\'s name (then grandparent, etc. as needed) until the search term is unique. This version makes sure the skeleton cooperates with that mechanism instead of fighting it: recurring archetype/category names (`Diagnosis`, `Comparison`, ...) are left bare rather than pre-qualified with an ancestor\'s name baked in, true duplicate siblings are never left in, and name collisions the automatic rescue can\'t cleanly resolve (same name AND same parent name elsewhere in the tree) are caught and given more specific names instead. New checklist Part G and task step 5.5 make this mandatory before finishing.\n\n## WHAT THIS PROMPT IS FOR\n\nThis is a **two-stage pipeline**, and this prompt is **Stage 1 only**.\n\n- **Stage 1 (THIS prompt):** Given a subject, field, or topic, output ONLY the **skeleton** — every node name, arranged as a deep hierarchy using **tab indentation**. No notes. No equations. No explanations. Just names, correctly nested.\n- **Stage 2 (a separate prompt, M3-87, run in a DIFFERENT chat):** Takes the finished Stage-1 skeleton and, node by node, converts it into the `lvlN[I]Title{note:"...", equation:"..."}` export format, filling in notes, equations, and detail for each node that Stage 1 already named.\n\n**Your job in this chat is Stage 1 ONLY.** Never write `lvl1[1]`-style markers, never write a `note:`, `equation:`, or any `{...}` block, never add explanatory prose describing a node — that content belongs to Stage 2, in the other chat, later. If you add it here, Stage 2 has nothing left to do and the two-stage split breaks down.\n\n---\n\n## ⛔ THE CORE PROBLEM THIS PROMPT EXISTS TO FIX\n\nMind maps built in one shot tend to fail in a specific, predictable way: the AI gets lazy about the hierarchy and honest about the hierarchy, and instead **stuffs multiple distinct facts into one node\'s name**, using commas and parentheses as a substitute for actually branching the tree. The result LOOKS like a mind map but is really a shallow, bloated list wearing a mind-map costume.\n\n**Real example of the failure (this is an actual node name from a prior output):**\n```\nTrichophyton (Tinea corporis, pedis, cruris, unguium)\n```\nThis single node is secretly **five separate facts** — the organism, plus four distinct diseases it causes — flattened into one line. Because they were never split, the tree never grew a level here, and the map ends up looking "deep" in places while actually being wide and shallow everywhere it matters.\n\n**Another real example:**\n```\nCandida albicans (Thrush, vulvovaginitis, esophagitis, septicemia, germ tube positive)\n```\nThat is **one node name hiding six facts**: the organism, four distinct clinical presentations, and a diagnostic feature. None of those six ideas are the same idea, so they cannot share one node.\n\n**This is the single most important thing this prompt exists to prevent.** Everything below serves that goal.\n\n---\n\n## OUTPUT FORMAT\n\n1. **One node per line.**\n2. **Indentation = depth.** Use exactly one **tab character** per level of depth below the root. The root has zero tabs, its children have one tab, their children have two tabs, and so on.\n3. **A line contains ONLY the node\'s name.** Plain text. No numbering, no bullets, no dashes, no parenthetical asides, no `lvlN[I]` markers, no `{...}` overrides, no notes.\n4. **No blank lines between nodes.** The tree is one continuous indented block.\n5. **Wrap the entire output in a single fenced code block** (triple backticks, no language tag) so it has a copy button and pastes cleanly with its tab characters intact.\n6. **Do not explain the tree, do not add commentary before or after the code block.** Output the skeleton and stop.\n\n**Example shape (topic: "Citrus"):**\n```\nCitrus\n\tSweet Citrus\n\t\tOrange\n\t\t\tNavel Orange\n\t\t\tValencia Orange\n\t\tMandarin\n\tSour Citrus\n\t\tLemon\n\t\tLime\n\t\tGrapefruit\n```\n\n---\n\n## ⛔ RULE 1 (MOST IMPORTANT): ONE NODE = ONE ATOMIC IDEA, ALWAYS\n\nBefore writing any node name, ask: **"Is this actually more than one thing?"**\n\nA node name is broken and must be split if it contains any of these tells:\n- **A comma-separated list** of two or more items (diseases, examples, types, symptoms, dates, names...): `Trichophyton (Tinea corporis, pedis, cruris, unguium)` → the organism is one node, each disease is its own child.\n- **Parenthetical content that is itself a list, a definition, a mechanism, or a second fact**, not just a short one-or-two-word disambiguator. `Histoplasma capsulatum (Ohio/Mississippi valleys, intracellular macrophages)` is hiding a geography fact AND a mechanism fact — both deserve their own child node under `Histoplasma capsulatum`.\n- **"and" / "or" joining two nameable things**: `Chlamydospores and Arthrospores` → two sibling nodes.\n- **A colon or dash followed by an explanation**: `Lac Operon: Inducible, catabolite repression by cAMP-CAP` → `Lac Operon` is the node; `Inducible`, `Catabolite Repression (cAMP-CAP)` become its children.\n\n**A parenthetical is allowed to stay in the title ONLY when it is a single short disambiguator with no internal list** — e.g. `Malaria (Plasmodium)` or `TB (Mycobacterium tuberculosis)` used as a plain alias, not when it\'s smuggling in extra facts. When in doubt, split it out into a child instead of leaving it in parentheses.\n\n**Worked correction (using the real Mycology example):**\n\n❌ **WRONG (flat, cramming, this is the failure mode):**\n```\nOpportunistic Mycoses (Immunocompromised hosts)\n\tCandida albicans (Thrush, vulvovaginitis, esophagitis, septicemia, germ tube positive)\n\tAspergillus fumigatus (Allergic sinusitis, aspergilloma, invasive aspergillosis)\n```\n\n✅ **CORRECT (every distinct fact gets its own branch):**\n```\nOpportunistic Mycoses\n\tHost Context\n\t\tImmunocompromised Hosts\n\tCandida albicans\n\t\tClinical Presentations\n\t\t\tThrush\n\t\t\tVulvovaginitis\n\t\t\tEsophagitis\n\t\t\tSepticemia\n\t\tDiagnostic Features\n\t\t\tGerm Tube Test\n\tAspergillus fumigatus\n\t\tClinical Presentations\n\t\t\tAllergic Sinusitis\n\t\t\tAspergilloma\n\t\t\tInvasive Aspergillosis\n```\nNotice depth went from 2 levels to 4-5 levels for the exact same information — nothing was added, it was just un-flattened. This is what "deep" actually means in this format: not padding, but refusing to let two facts share one node.\n\n---\n\n## RULE 2: THE STANDARD LEARNING SCHEMA (adapt per subject, don\'t force it rigidly)\n\nFor hierarchies meant for **learning** a field, subject, or topic, this is the default backbone — use it as a starting skeleton of levels, then apply Rule 1 underneath every level so it actually gets deep instead of stalling:\n\n```\nField / Subject                      (root)\n\tMajor Branch / Domain             (e.g. Mycology, Virology, Bacteriology)\n\t\tChapter / Category             (e.g. Medically Important Fungi)\n\t\t\tTopic / Subcategory          (e.g. Systemic Dimorphic Mycoses)\n\t\t\t\tSpecific Item              (e.g. Histoplasma capsulatum)\n\t\t\t\t\tAttribute Group          (e.g. Clinical Presentation, Mechanism, Diagnosis)\n\t\t\t\t\t\tIndividual Fact        (e.g. Ohio/Mississippi valleys)\n```\n\nThis is a **guide, not a cage** — some subjects need more layers (a "Type" layer between Topic and Specific Item; a "Subtype" layer under an Attribute Group when there are sub-facts within a fact), some need fewer near the top (a narrow topic request might start straight at "Chapter" level rather than a whole "Field"). The one rule that never bends is Rule 1: whatever layers you use, no single node may hide more than one atomic fact.\n\n**How to decide the grouping label for an "Attribute Group" layer:** look at what kinds of facts keep recurring under similar nodes in this subject, and name the group after that recurring kind — `Clinical Presentations`, `Mechanism of Action`, `Diagnostic Features`, `Causes`, `Types`, `Examples`, `Historical Context`, `Variants`, `Stages`, `Related Conditions`, etc. This is exactly the kind of field-agnostic "recurring aspect schema" idea — derive it from the subject rather than forcing one template onto every field.\n\n**⛔ Two things that look like a hierarchy step but are NOT — check every parent-child link against this:**\n- **A sibling relationship is not a child relationship.** If two named things are both instances of the same kind of thing (two species of hookworm, two strains of a virus, two drugs in a class), they are **siblings under a shared parent**, never one nested inside the other. `Necator americanus` is not a child of `Ancylostoma duodenale` just because they cause the same disease — both are children of `Hookworm` (or of `Causative Agents`, plural). Before nesting B under A, ask: "is B a property/example belonging to A specifically, or is B just another thing of the same kind as A?" — the second case is always a sibling, never a child.\n- **A slash, semicolon, or "or" joining two names is cramming, exactly like a comma is.** `Coccidioides immitis / Coccidioides posadasii` is two organisms wearing one node — split it into two children of a plural parent (`Causative Agents`), the same way Rule 1 already treats commas and "and".\n\n---\n\n## RULE 2.5: ARCHETYPE-DRIVEN EXPLANATORY SCAFFOLDING (add the branches a textbook would add)\n\nRaw source material (an encyclopedia entry, a dataset, a list of facts) usually only tells you what\'s directly stated. But a hierarchy built **for learning** needs more than that — it needs the scaffolding a textbook or study guide adds on top of the raw facts to make sure nothing is left as an open question in the learner\'s head: symptoms and diagnosis for a disease even if the source only mentioned its cause; onset and interactions for a drug even if the source only named it; a worked example or real-world application for a formula even if the source only gave the equation.\n\n**Your job is to recognize what KIND of thing a node represents (its "archetype") and make sure its standard, expected branches exist underneath it — adding them yourself when the source material didn\'t spell them out, not just when it did.**\n\nThis does not mean inventing false facts — where you don\'t have enough information to fill in a genuinely accurate answer for a branch, still create the node (so Stage 2 knows to research and fill it), rather than skipping the branch because today\'s source text happened not to mention it.\n\n**Common archetypes and their expected branches** (use these as a checklist, not a rigid template — skip any branch that\'s genuinely not applicable, and add branches beyond this list whenever the subject calls for it):\n\n| Archetype | Recognize it by | Expected branches to check for / add |\n|---|---|---|\n| **Disease / Clinical Condition** | A named illness, syndrome, or disorder | Risk Factors, Signs & Symptoms, Diagnosis, Differential Diagnosis, Treatment/Management, Complications, Prognosis, Prevention |\n| **Organism / Pathogen** | A species, genus, or microbe | Morphology/Classification, Virulence/Pathogenic Mechanism, Transmission, Associated Conditions, Laboratory Identification, Treatment/Susceptibility |\n| **Drug / Therapeutic Agent** | A named medication or drug class | Mechanism of Action, Indications, Dosing & Onset of Action, Pharmacokinetics, Adverse Effects, Contraindications, Drug Interactions |\n| **Process / Mechanism / Pathway** | A biological, chemical, or physical process (e.g. glycolysis, an immune response, a reaction mechanism) | Stages/Steps, Key Molecules or Agents Involved, Regulation/Control, Real-World or Clinical Significance, Common Misconceptions |\n| **Formula / Equation / Physical Law** | A named law, equation, or quantitative relationship (physics, chemistry, math) | Variable Definitions, Derivation or Physical Origin, Worked Example, Real-World Application, Limiting Cases / Edge Conditions, Common Misconceptions |\n| **Historical Event / Theory / Concept** | A discovery, historical episode, or abstract theory | Historical Context, Key Contributors/Evidence, Modern Relevance or Application, Common Misconceptions |\n| **Sibling Group (Comparison-worthy)** | Two or more sibling nodes that are the same *kind* of thing and commonly get confused or contrasted (Gram-positive vs Gram-negative cell walls, two drugs in the same class, two species in the same genus, two disease subtypes, two theories addressing the same problem) | A `Comparison` node under their **shared parent** (a sibling to the group, not a child of any one of them), placeholder-populated with the dimensions worth contrasting (e.g. `Structural Differences`, `Clinical Differences`, `Mechanism Differences`) |\n\n**Comparison nodes are structural, not prose — this is still Stage 1.** You are not writing the comparison here, only guaranteeing a labeled slot exists so Stage 2 is forced to write one. Do not describe the actual differences (no "thicker in Gram-positive" text) — just name the node (`Comparison`) and, if useful, a shallow breakdown of what should be compared (`Cell Wall Thickness`, `Outer Membrane Presence`, `Stain Retention`) as its children, still as bare labels.\n\n**How to spot a comparison-worthy sibling group while drafting:** after writing 2+ sibling nodes, pause and ask "would a student mixing these two up be a common, predictable mistake?" or "does a textbook on this subject always contrast these two side by side?" (Gram-positive/negative, aerobic/anaerobic, first-gen/second-gen drugs, competitive/noncompetitive inhibition...). If yes, add the `Comparison` node as an additional sibling to the group, nested one level up under the parent they share — never nested inside one member of the group, since a comparison belongs to neither one alone.\n\n**How to apply this while drafting:** for every node you write, briefly ask "does this node match one of these archetypes (or an obvious variant of one for this field)?" If yes, before moving to the next node, check whether the standard branches for that archetype exist underneath it — if a branch is missing and would genuinely apply, add a placeholder child node for it (even one word, e.g. `Diagnosis`, `Drug Interactions`, `Worked Example`) so Stage 2 knows to research and fill it in. Do not add a branch that plainly does not apply (a virus doesn\'t need "Dosing"; a historical event doesn\'t need "Pharmacokinetics").\n\nThis list is a starting point, not exhaustive — the same instinct applies to any field: think about what a good textbook chapter on this exact node would include that a bare fact-list wouldn\'t, and add that as a branch.\n\n**Worked example — a disease node, source material vs. properly scaffolded:**\n\n❌ **Source-only (misses what a learner needs):**\n```\nTuberculosis\n\tCausative Agent\n\t\tMycobacterium tuberculosis\n\tPathogenesis\n\t\tGranuloma Formation\n```\n\n✅ **Archetype-scaffolded (adds the textbook branches even though the source didn\'t state them):**\n```\nTuberculosis\n\tCausative Agent\n\t\tMycobacterium tuberculosis\n\tPathogenesis\n\t\tGranuloma Formation\n\t\tCaseous Necrosis\n\tRisk Factors\n\tSigns and Symptoms\n\tDiagnosis\n\tDifferential Diagnosis\n\tTreatment\n\tComplications\n\tPrognosis\n\tPrevention\n```\n(The empty-looking branches above are placeholders for Stage 2 to research and populate — they exist here to guarantee Stage 2 doesn\'t skip them, which is exactly the "notes get skipped" failure this whole pipeline is trying to prevent one stage earlier.)\n\n**Worked example — a comparison-worthy sibling group, before/after:**\n\n❌ **Missing the comparison slot (siblings just sit there uncontrasted):**\n```\nCell Wall\n\tGram-Positive Cell Wall\n\t\tThick Peptidoglycan Layer\n\t\tTeichoic Acids\n\tGram-Negative Cell Wall\n\t\tThin Peptidoglycan Layer\n\t\tOuter Membrane\n```\n\n✅ **Comparison node added as a shared sibling (still just labels, no prose):**\n```\nCell Wall\n\tGram-Positive Cell Wall\n\t\tThick Peptidoglycan Layer\n\t\tTeichoic Acids\n\tGram-Negative Cell Wall\n\t\tThin Peptidoglycan Layer\n\t\tOuter Membrane\n\tComparison\n\t\tCell Wall Thickness\n\t\tOuter Membrane Presence\n\t\tGram Stain Result\n\t\tEndotoxin Presence\n```\nNotice `Comparison` sits under `Cell Wall`, as a sibling to both variants, not tucked under either one — because the contrast belongs to both of them jointly.\n\n---\n\n## RULE 2.75: SIBLING BRANCH PARITY — EVERY MAJOR SUB-FIELD GETS THE SAME FOUNDATIONAL TREATMENT AS ITS SIBLINGS\n\n**This is Rule 1\'s "one node = one idea" discipline applied one level up, to entire branches instead of single nodes.** When a subject splits into multiple major sibling sub-fields (e.g. `Microbiology` → `Bacteriology`, `Virology`, `Mycology`, `Parasitology`, `Immunology`), each of those siblings is doing the same *job* in the tree — introducing one branch of the parent subject — and each one owes the reader the same category of foundational content before it dives into specific named instances (species, drugs, diseases). If three of the four give the reader a "how this group of organisms/agents is built and classified" layer first and the fourth jumps straight to a list of named organisms, that fourth branch is incomplete relative to its own siblings, even if every individual node inside it is correctly atomized.\n\n**Real example of this failure (an actual gap from a prior output):**\n```\nMicrobiology\n\tBacteriology\n\t\tBacterial Structure and Physiology     ← foundational layer present\n\t\tBacterial Growth and Metabolism        ← foundational layer present\n\t\tBacterial Genetics                     ← foundational layer present\n\t\tMedically Important Bacteria           ← THEN specific organisms\n\tVirology\n\t\tViral Structure and Classification     ← foundational layer present\n\t\tViral Replication                      ← foundational layer present\n\t\tMedically Important Viruses            ← THEN specific organisms\n\tMycology\n\t\tFungal Structure and Classification    ← foundational layer present\n\t\tFungal Reproduction                    ← foundational layer present\n\t\tMedically Important Fungi              ← THEN specific organisms\n\tParasitology\n\t\tHelminths (Worms)                      ← ⛔ jumps straight to organism groups,\n\t\t\tNematodes                             no foundational layer at all\n\t\t\t\tEnterobius vermicularis\n\t\tProtozoa\n\t\t\tEntamoeba histolytica\n```\nParasitology has no equivalent to "Structure and Classification" or "Growth and Metabolism" — it just starts listing worm and protozoan species. A learner gets no answer to "what makes something a parasite," "how are parasites classified," "what are the general types of life cycle / transmission a parasite can have" — questions the other three siblings all answer for their own group before naming a single species.\n\n**Corrected — Parasitology given the same category of foundational layer its siblings have (adapted to what\'s actually true of this field, not copy-pasted):**\n```\nParasitology\n\tGeneral Parasitology\n\t\tHost-Parasite Relationships\n\t\t\tDefinitive Host\n\t\t\tIntermediate Host\n\t\t\tReservoir Host\n\t\t\tVector\n\t\tClassification of Parasites\n\t\t\tEctoparasites\n\t\t\tEndoparasites\n\t\tLife Cycle Patterns\n\t\t\tDirect Life Cycle\n\t\t\tIndirect Life Cycle\n\t\tModes of Transmission\n\t\t\tFecal-Oral\n\t\t\tVector-Borne\n\t\t\tIngestion of Infected Tissue\n\tHelminths (Worms)\n\t\tNematodes\n\t\t\tEnterobius vermicularis\n\tProtozoa\n\t\tEntamoeba histolytica\n```\nNothing about the organism-by-organism content changed — the fix is purely that the branch now opens with the same *kind* of foundational layer its siblings already have, adapted to what\'s actually true of parasites (life cycle patterns and host types, not "growth phases" or "replication cycle," because those aren\'t the right foundational concepts for this group).\n\n**How to apply this while drafting:**\n1. Whenever you write 2+ sibling branches that are all instances of the same *kind* of thing (sub-fields of one subject, categories of one classification, drug classes under one system), pause once all of them are drafted and compare their top-level shape side by side.\n2. For each one, ask: "does this branch open with foundational/general content (structure, classification, general mechanisms, general lifecycle) before it names specific individual instances?" If most siblings do and one doesn\'t, that one is missing a branch — go add it, using content genuinely appropriate to that specific sub-field (don\'t force-fit another sibling\'s exact layer names onto it).\n3. This is not about forcing identical branch *names* across siblings — Virology needs "Replication," Parasitology needs "Life Cycle Patterns," Immunology needs neither. It is about making sure each sibling gets *some* genuinely-fitting foundational layer of equivalent depth and purpose, not that all siblings look identical.\n\n---\n\n## RULE 2.8: IF YOU HAVE SEARCH — USE IT TO VERIFY A-TO-Z COVERAGE BEFORE FINALIZING\n\n**Do not draft a broad subject\'s skeleton from memory alone and assume it\'s complete.** For anything at the "chapter," "full subject," or "full field" scope (see Rule 3\'s scope table), memory is a good first draft but an unreliable completeness check — it\'s exactly how an entire foundational branch (see Rule 2.75) or an entire major topic can go quietly missing without ever looking wrong from the inside.\n\n**Before finalizing a broad-scope skeleton, if you have web search available, use it to check your top-level and second-level branch list against real reference sources:**\n- Search for the standard table of contents of a well-regarded textbook in this subject (e.g. "medical parasitology textbook table of contents", "microbiology course syllabus outline"), or a standard curriculum/board-exam content outline if one exists for this field.\n- Compare that list against your drafted top-level and second-level branches. Any major chapter/topic present in multiple independent real sources but absent from your draft is a gap — add it (as a full branch built with Rule 1/2/2.5, not just a bare label).\n- This check is specifically aimed at catching **missing branches**, not verifying every individual fact — Rule 2.5\'s archetype scaffolding and Rule 2.75\'s sibling parity check handle depth and consistency once the branch list itself is complete. Use search to answer "did I forget an entire topic," not to fact-check every leaf.\n- If search isn\'t available in this session, do the same comparison from your own knowledge of how the subject is conventionally organized (its standard textbook chapter breakdown) instead — the goal (a full, non-partial branch list) doesn\'t change, only the method of verifying it does.\n\n---\n\n## RULE 3: DEPTH TARGETS\n\nDepth is a *consequence* of following Rule 1 faithfully, not a separate padding exercise — but as a floor:\n\n| Request scope | Minimum depth (levels from root) |\n|---|---|\n| A single narrow topic (e.g. "the Krebs Cycle") | 5 |\n| A chapter or unit (e.g. "Mycology") | 6 |\n| A full subject (e.g. "Microbiology") | 7, and most branches should go to 8+ |\n| A full field spanning multiple subjects | 8, with core branches reaching 9-10 |\n\nIf, while drafting, a whole branch of the tree tops out 2+ levels shallower than the target and the sibling branches around it don\'t, that branch almost certainly still has crammed nodes in it — go back and apply Rule 1 again before moving on. Shallow-but-correct is rare; shallow is almost always a sign of skipped splitting, not a sign the branch was simple.\n\n---\n\n## RULE 4: NAMING STANDARDS FOR EACH NODE\n\n- **Short.** A node name should read like a label, not a sentence. If you cannot say it in roughly 1-6 words, it is very likely hiding a second fact that belongs one level down (re-check against Rule 1).\n- **No restating the parent.** A child should not just repeat its parent\'s name with one word added and nothing else distinguishing it (`Fungi` → `Types of Fungi` → `Fungus Types` is circular padding, not depth).\n- **No bare, empty category nodes.** Every node you write must have either at least one child (if it\'s a grouping node) or be a genuine leaf fact (if it\'s terminal). Don\'t create a grouping node "for structure" if you\'re not going to populate it.\n- **Consistent grammatical form among siblings.** If one child under "Clinical Presentations" is a noun phrase ("Thrush"), all its siblings should be noun phrases too, not a mix of noun phrases and full sentences.\n- **Use proper scientific/technical names exactly as known** (correct spelling, capitalization, italicizable binomial names written plainly since this is plain text) — Stage 2 will build equations and notes assuming Stage 1\'s names are accurate.\n\n---\n\n## RULE 4.5: NODE NAME DISCIPLINE — IMAGE-MATCHING (IFM) AWARENESS\n\n**Why this matters even at the skeleton stage:** Stage 2 will fill in your names with notes and equations, but the names themselves are what a later, separate automated step (the IFM/Automatic Search pipeline) uses to fetch one picture per node — it searches Google Images for each node\'s **name, exactly as written**. That pipeline already has a built-in rescue for a name that isn\'t unique: it prefixes the name with its parent\'s name, and if that\'s still not enough (the parent\'s name repeats too), it climbs to the grandparent, then great-grandparent, and so on, until the combined phrase is unique or it runs out of ancestors. Your job here isn\'t to run that search — it\'s to draft a skeleton whose names cooperate with that rescue instead of defeating it.\n\n**What this means while drafting:**\n\n1. **A recurring category/archetype name across different branches is expected and correct — leave it bare.** Rule 2.5\'s scaffold names (`Diagnosis`, `Treatment`, `Comparison`, `Mechanism of Action`, `Risk Factors`, `Signs and Symptoms`, `Clinical Presentations`, ...) are *meant* to repeat once per Disease/Drug/Organism-type node — that\'s exactly the case the parent-prefix rescue exists to handle. **Never pre-qualify one of these yourself** by folding the ancestor into the name (writing `Tuberculosis Diagnosis` as the node name instead of nesting a plain `Diagnosis` under `Tuberculosis`) — doing so duplicates what the image pipeline already does automatically later, and it also violates Rule 4\'s "short label" standard by turning a clean one-or-two-word name into a compound phrase.\n2. **Never give two children of the same parent the identical name.** Unlike case 1 (same name, different parents — always fine), a real duplicate sibling is always a drafting mistake: either a leftover repeated line, or two facts that were never actually the same thing and need distinct names. The Atomicity Checklist (Part A) already has you scanning parent-child links for mis-nesting; while you\'re there, also scan sibling groups for literal duplicate names and fix any you find.\n3. **Watch for a name that collides with an unrelated node\'s name where the parent names ALSO collide.** That\'s the one case the automatic rescue can\'t cleanly resolve in a single step — it has to keep climbing the tree, or settle while the two are still ambiguous. In a hand-built skeleton this almost always means one of two things: an accidental duplicate branch (case 2, one level removed), or a sibling group named too generically for its context (two unrelated `Type 1` / `Type 2` pairs instead of each using its own items\' real names). Fix it by making the colliding names more specific and concrete, not by leaving it for the ancestor-prefix chain to sort out.\n4. **Name leaf-level facts concretely, not generically.** A leaf that states one specific fact (a named symptom, drug, organism, structure, date) should be named for that fact (`Night Sweats`, not `Symptom`) rather than a bare category word — a concrete name is both less likely to accidentally collide with an unrelated node elsewhere in a large tree, and makes for a far more accurate image search on its own. Save generic names (`Overview`, `Definition`, `Types`, `Examples`, the Rule 2.5 archetype labels) for genuine grouping/category nodes, where recurrence-plus-parent-prefix (point 1) is exactly the intended behavior.\n\n---\n\n## RULE 5: STRUCTURAL CONSISTENCY (tabs behave like the old lvl-marker rules, simplified)\n\n- **Depth increases by exactly one tab at a time going down** — never jump from 2 tabs to 4 tabs in consecutive lines.\n- **A node\'s siblings are all lines with the same tab count that share the same nearest shallower-tab ancestor.** Going back up to add a new branch just means writing a line with fewer tabs than the line before it — you don\'t need to repeat anything (unlike the lvl-marker format, tabs alone encode the whole path).\n- **Never use spaces to fake indentation.** Only real tab characters count as one level; mixing spaces in will misalign the hierarchy when it\'s pasted elsewhere.\n\n---\n\n## ⛔ SKELETON VERIFICATION CHECKLIST (run this on your ENTIRE output before finishing)\n\n**A — Atomicity Checklist (the most important pass, do this one twice):**\n- [ ] Scan every single node name for a comma. If found, could that comma be separating two facts instead of being part of one name (e.g. "St. Louis, Missouri" is fine; "Thrush, vulvovaginitis" is not)? If it\'s separating facts, split them into children.\n- [ ] Scan every node name for parentheses. Is the parenthetical content a single short disambiguator, or is it a second fact, a list, or a mechanism? If the latter, pull it out into its own child node(s).\n- [ ] Scan for "and" / "or" / "/" joining two nameable things inside one node name. Split them into children of a plural parent.\n- [ ] Scan for a colon or dash followed by descriptive content inside a node name. Split the description into children.\n- [ ] Scan every parent-child link: is the child actually a property of the parent, or is it really a sibling (another instance of the same kind of thing) that got mistakenly nested instead? Move any misnested siblings up to share the correct parent.\n\n**B — Depth Checklist:**\n- [ ] Compare the deepest point in each major branch against the Rule 3 target for this request\'s scope.\n- [ ] Any branch that falls short — re-open it and look for un-split (crammed) nodes; that\'s almost always the cause.\n\n**C — Format Checklist:**\n- [ ] Every line uses only tabs for indentation, never spaces.\n- [ ] Depth never jumps by more than one tab between a line and the line above it.\n- [ ] No `note:`, `equation:`, `{`, `}`, `lvl`, numbering, or bullet characters appear anywhere in the output — this is Stage 2\'s job, not this stage\'s.\n- [ ] The whole thing is inside one fenced code block, and nothing else (no preamble, no summary) sits outside that block.\n\n**D — Explanatory Scaffolding Checklist (Rule 2.5):**\n- [ ] For every node matching a Disease/Condition archetype: Risk Factors, Signs & Symptoms, Diagnosis, Treatment, Complications, Prognosis, Prevention are present (or genuinely not applicable).\n- [ ] For every node matching a Drug archetype: Mechanism, Indications, Dosing/Onset, Adverse Effects, Interactions, Contraindications are present (or genuinely not applicable).\n- [ ] For every node matching a Process/Mechanism or Formula/Equation archetype: a Real-World Application / Worked Example / Significance branch is present, not just the raw mechanics.\n- [ ] No archetype branch was added that plainly doesn\'t fit the node (don\'t force "Dosing" onto a virus, or "Pharmacokinetics" onto a historical event).\n\n**E — Comparison Coverage Checklist (Rule 2.5, Sibling Groups):**\n- [ ] Scan every set of 2+ sibling nodes of the same kind (species, drug-class members, disease subtypes, competing theories, structural variants). For each set, is a `Comparison` node present as their shared sibling?\n- [ ] Every `Comparison` node sits one level up, under the parent the compared items share — never nested inside one of the items being compared.\n- [ ] No `Comparison` node was added for a sibling group that isn\'t actually confusable or contrast-worthy (don\'t force a comparison between two unrelated leaf facts just because they\'re siblings).\n\n**F — Sibling Branch Parity & Coverage Checklist (Rule 2.75, Rule 2.8):**\n- [ ] List every set of major sibling branches that represent the same kind of thing (sub-fields of one subject, categories of one classification). For each set, does every sibling open with a genuinely-fitting foundational/general layer before naming specific instances, matching the depth and purpose (not the literal names) of what its siblings have?\n- [ ] For chapter/subject/field-scope requests: was the branch list checked against a real external source (search, if available) or, at minimum, deliberately compared against the subject\'s standard textbook chapter breakdown from memory? Was anything missing added as a full branch, not a bare label?\n\n**G — Node Name / IFM Disambiguation Checklist (Rule 4.5):**\n- [ ] No two children of the same parent share an identical name. Any true duplicate sibling found is fixed (renamed or removed), not left in.\n- [ ] No archetype/category name (Rule 2.5) was pre-qualified with its ancestor\'s name baked into the text (e.g. no `Tuberculosis Diagnosis` node name — it should just be `Diagnosis`, nested under `Tuberculosis`).\n- [ ] For every name that repeats elsewhere in the tree, its parent\'s name is distinct from the parent\'s name of the other occurrence(s). If two occurrences share both the same name AND the same parent name, that pair is re-examined: it\'s fixed as either a duplicate-branch mistake or a too-generic leaf/sibling name, not left for a longer ancestor chain to sort out.\n- [ ] Leaf nodes stating a specific fact are named for that fact concretely, not with a bare generic label that a sibling group elsewhere in the tree could just as easily collide with.\n\n---\n\n## WORKED FULL EXAMPLE — before/after on real content\n\n**Input request:** "Give me a learning skeleton for the Fungal Reproduction section of Mycology."\n\n**Old-style flattened output (WRONG — this is the failure this prompt fixes):**\n```\nFungal Reproduction\n\tAsexual Reproduction (Mitotic spores)\n\t\tConidia (Macroconidia, Microconidia)\n\t\tSporangiospores\n\t\tArthrospores\n\t\tChlamydospores\n\tSexual Reproduction (Meiotic spores)\n\t\tZygomycota (Zygospores)\n\t\tAscomycota (Ascospores in sacs)\n\t\tBasidiomycota (Basidiospores on club-shaped basidia)\n\t\tDeuteromycota (Imperfect fungi, no known sexual stage)\n```\n\n**Correct Stage-1 skeleton (RIGHT — every fact gets its own node, depth follows naturally):**\n```\nFungal Reproduction\n\tAsexual Reproduction\n\t\tSpore Type\n\t\t\tMitotic Spores\n\t\tSpore Forms\n\t\t\tConidia\n\t\t\t\tMacroconidia\n\t\t\t\tMicroconidia\n\t\t\tSporangiospores\n\t\t\tArthrospores\n\t\t\tChlamydospores\n\tSexual Reproduction\n\t\tSpore Type\n\t\t\tMeiotic Spores\n\t\tFungal Phyla\n\t\t\tZygomycota\n\t\t\t\tZygospores\n\t\t\tAscomycota\n\t\t\t\tAscospores\n\t\t\t\t\tFormed in Sacs (Asci)\n\t\t\tBasidiomycota\n\t\t\t\tBasidiospores\n\t\t\t\t\tFormed on Basidia\n\t\t\t\t\t\tClub-Shaped Structure\n\t\t\tDeuteromycota\n\t\t\t\tImperfect Fungi\n\t\t\t\t\tNo Known Sexual Stage\n```\n\n---\n\n## YOUR TASK\n\nWhen the user names a field, subject, chapter, or topic (however narrow or broad):\n\n1. Determine the scope (single topic / chapter / full subject / full field) and its Rule 3 depth target.\n2. Draft the tree using the Rule 2 schema as a loose backbone. For chapter/subject/field scope, if search is available, check the top-level and second-level branch list against a real reference source (Rule 2.8) before treating the branch list as final.\n3. Apply Rule 1 relentlessly to every node as you go — do not wait until the end to fix cramming; do it live, node by node. Also check every parent-child link as you make it: is this really a property, or a mis-nested sibling?\n4. For every node, check Rule 2.5 — does it match a known archetype, and if so, are its expected branches present? Add placeholder branches Stage 2 will need to fill, even where the source material was silent. For every group of 2+ same-kind siblings, add a shared `Comparison` node so Stage 2 is forced to contrast them instead of describing each in isolation.\n5. Once all major sibling branches are drafted, run Rule 2.75: compare them side by side and confirm each one opens with its own genuinely-fitting foundational layer before naming specific instances — add the missing layer to any sibling that skipped straight to specifics.\n5.5. Apply Rule 4.5 as you name nodes: leave recurring archetype/category names bare (don\'t pre-qualify them with an ancestor\'s name), never let two children of the same parent share a name, and give concrete leaf facts concrete names rather than generic ones.\n6. Run the full Skeleton Verification Checklist (Parts A, B, C, D, E, F, G) before finishing.\n7. Output **ONLY** the tab-indented skeleton in a single fenced code block. No notes, no equations, no `lvl` markers, no commentary before or after.\n\nThe result is meant to be pasted, as-is, into a separate chat running the Stage 2 (M3-87) prompt, which will then walk this exact skeleton node by node and attach notes, equations, and labels to each name you produced here.\n\nNow generate the skeleton the user requested.',
}
_NOTE_FORMAT_INSTRUCTIONS = (
    "Format your entire reply as a list of separate, short one-idea "
    "lines. No nested bullets, no paragraphs, no commentary outside "
    "these lines. If a line is a bullet-point item in a list, start that "
    "line with a single bullet character \"\u2022\" followed by a space -- "
    "never use \"-\", \"*\", or a number as the bullet marker. Leave a "
    "line with no bullet marker at all when it isn't genuinely a list "
    "item. Do not add \"#\" or any heading markers yourself -- headings "
    "are applied automatically afterward, so just write plain text (with "
    "a leading \"\u2022 \" only where a bullet point is genuinely called "
    "for)."
)

# Quick-pick instruction presets for the Note tab, shown as small numbered
# buttons so you don't have to type out the same handful of instructions
# over and over. Clicking a number REPLACES whatever's currently in the
# Note tab's Instructions box with that preset's text -- you can still
# edit it afterward before triggering a request. Each preset is written
# generically ("it"/"this") since the Node-name field already holds the
# actual node name separately.
_NOTE_INSTRUCTION_PRESETS = [
    "Define it: explain what it is and what it does.",
    "Explain how it works, step by step.",
    "List its key characteristics or properties.",
    "Give real-world examples or use cases of it.",
    "Compare it to similar or related things -- key similarities and differences.",
    "Explain why it matters and where it's used.",
    "List the common types or categories of it.",
    "Summarize its advantages and disadvantages.",
]


# Five difficulty levels shared by the MCQ's and QA tabs' dropdowns, in
# ascending order. (Kept generic rather than "_QA_..." now that the MCQ's
# tab uses the same list.)
_DIFFICULTY_LEVELS = ("Very Easy", "Easy", "Medium", "Hard", "Very Hard")
_DEFAULT_DIFFICULTY = "Medium"

# The MCQ's, True/False, and Fill/Blanks tabs all share the same 10
# numbered options-count buttons, running from 4 options/statements/fills
# (button "1") up through 13 (button "10") -- see _select_mcq_options /
# _select_tf_options / _select_fb_options and _build_lettered_options_row
# in build_ui(). _difficulty_to_num_options below turns a difficulty into
# a RECOMMENDED count within that same 4-13 range (shown as a label, see
# _recommend_options_text) -- it does not pick the button for you, since
# question difficulty and option count are genuinely independent (a
# 4-option question can be brutally hard, a 13-option one can be trivial).
_MCQ_MIN_OPTIONS = 4
_MCQ_MAX_OPTIONS = 13


def _difficulty_to_num_options(difficulty: str) -> int:
    """Map a difficulty level to a RECOMMENDED options-per-item count,
    spread evenly across the 4-13 option range (the 10 numbered buttons)
    in the same ascending order as _DIFFICULTY_LEVELS. Purely advisory --
    see _recommend_options_text, which is what actually surfaces this to
    the person as a suggestion label. Nothing calls this to change which
    button is selected."""
    try:
        idx = _DIFFICULTY_LEVELS.index(difficulty)
    except ValueError:
        idx = _DIFFICULTY_LEVELS.index(_DEFAULT_DIFFICULTY)
    span = _MCQ_MAX_OPTIONS - _MCQ_MIN_OPTIONS
    steps = len(_DIFFICULTY_LEVELS) - 1
    return _MCQ_MIN_OPTIONS + round(idx * span / steps)


def _letters_and_phrase(num_options: int):
    """Shared by the MCQ's, True/False, and Fill/Blanks prompt builders:
    the lettered A, B, C... list for `num_options` items, plus an
    English list phrase ("A, B, C, and D") for dropping into prompt
    text."""
    letters = list(string.ascii_uppercase[:num_options])
    if len(letters) > 1:
        phrase = ", ".join(letters[:-1]) + f", and {letters[-1]}"
    else:
        phrase = letters[0]
    return letters, phrase


def _balanced_answer_key_lines(count: int, letters: list) -> str:
    """Shared by the MCQ's, True/False, and Fill/Blanks prompt builders:
    a balanced, shuffled "Question N: <letter>" answer key, one line per
    item, guaranteeing the correct letter is spread as evenly as `count`
    allows across every option rather than left to whatever positional
    bias the model happens to have (empirically it clusters hard on the
    first letter, with occasional runs of a middle one). Repeats the
    letter cycle enough times to cover `count` items, trims to exactly
    `count`, then shuffles -- so every letter's share is within one item
    of every other letter's, without falling into a predictable
    A, B, C, A, B, C... repeating order either."""
    num_options = len(letters)
    reps = (count // num_options) + 1
    answer_key = (letters * reps)[:count]
    random.shuffle(answer_key)
    return "\n".join(
        f"Question {i}: {letter}" for i, letter in enumerate(answer_key, start=1)
    )


def _build_mcq_format_instructions(count: int, num_options: int, difficulty: str) -> str:
    """Prompt text for the MCQ's tab: exactly `count` multiple-choice
    questions, each with `num_options` lettered options (A, B, C, ...),
    laid out to match the fixed pattern this tab always pastes in -- a
    bulleted question line, one lettered option per line, a blank line,
    then a "(checkmark) Answer:" line and a "Reason:" line, blank line
    between questions. The model is not trusted to invent its own layout;
    this spells out the exact one used every time so parsing/pasting
    stays predictable regardless of topic or question count.

    `difficulty` (one of _DIFFICULTY_LEVELS) only affects question
    wording here -- it's folded into the prompt the same way the QA
    tab's difficulty does. `num_options` is independent, chosen
    separately by whichever button is selected (see
    _recommend_options_text for why difficulty no longer drives it).

    Left to itself, the model has its own positional bias for where it
    puts the correct option (empirically it clusters hard on "A", with
    occasional runs of "C" -- rarely "B" or later letters), which makes
    the answer guessable without knowing the material and gives an
    inflated illusion of scoring well. Rather than just *asking* the
    model to "vary" the answer position -- which it tends to ignore or
    approximate poorly -- this pre-computes an explicit, balanced,
    shuffled answer key (each letter used as equally as `count` allows,
    see _balanced_answer_key_lines) -- hands it to the model as a fixed
    requirement for each numbered question, so the distribution is
    guaranteed rather than hoped for."""
    letters, letter_list = _letters_and_phrase(num_options)
    option_lines = "\n".join(f" {letter}. <option text>" for letter in letters)
    answer_key_lines = _balanced_answer_key_lines(count, letters)

    return (
        f"Write exactly {count} multiple-choice questions on the topic "
        f"given below, at a {difficulty} difficulty level. Write "
        "questions that genuinely match that difficulty -- a Very Easy "
        "question should be answerable from a basic definition, while a "
        "Very Hard question should require deeper reasoning or a less "
        f"obvious detail. Give EVERY question exactly {num_options} "
        f"answer options, lettered {letter_list} -- never more, never "
        "fewer. "
        "Follow this EXACT layout for every question, with a blank line "
        "between questions and no commentary, intro, or summary outside "
        "it:\n\n"
        "\u2022 <question text>\n"
        f"{option_lines}\n\n"
        "\u2705 Answer: <letter>. <the correct option's text repeated>\n"
        " Reason: <one to two sentences explaining why that answer is "
        "correct, and briefly why each of the other options is wrong>\n\n"
        "Start every question line with a single bullet character "
        "\"\u2022\" followed by a space, then the question text -- do not "
        "number the questions. Keep each option on its own single line, "
        "with no line break inside an option's own text. Keep the "
        "\"\u2705 Answer:\" line and the \" Reason:\" line exactly as shown "
        "above, including the checkmark and the leading space before "
        "\"Reason\".\n\n"
        "IMPORTANT -- correct-answer placement: which letter is correct "
        "is fixed in advance per question, below, and you must follow it "
        "exactly. Do not default to putting the correct answer under the "
        "same letter over and over -- that makes the quiz guessable "
        "without knowing the material. For question N, write whichever "
        "option is actually correct under letter " + letters[0] + "-" +
        letters[-1] + " as instructed here, then build the other "
        f"{num_options - 1} options as plausible wrong answers around it "
        "(never reorder or renumber this list, and never invent your own "
        "placement):\n\n"
        f"{answer_key_lines}"
    )


def _build_true_false_format_instructions(count: int, num_statements: int, difficulty: str) -> str:
    """Prompt text for the True/False tab: exactly `count` items, each a
    short lettered set of `num_statements` complete, standalone factual
    statements about the topic -- exactly one of them true, the rest
    false -- laid out with the same bullet/lettered-lines/Answer/Reason
    pattern as the MCQ's tab (see _build_mcq_format_instructions) so
    parsing/pasting stays identical. The only real difference from an
    MCQ is what the lettered lines contain: complete true-or-false
    statements standing on their own, not answers to a posed question --
    so the bullet line is a short generic prompt ("Which statement below
    is true?") rather than a real quiz question, and the statements
    themselves carry all the content.

    Same guessability problem as the MCQ's tab applies here too --
    without a fixed, balanced, shuffled answer key the model tends to
    cluster the true statement on the same letter -- so this reuses the
    exact same _balanced_answer_key_lines machinery."""
    letters, letter_list = _letters_and_phrase(num_statements)
    statement_lines = "\n".join(f" {letter}. <statement text>" for letter in letters)
    answer_key_lines = _balanced_answer_key_lines(count, letters)

    return (
        f"Write exactly {count} True/False items on the topic given "
        f"below, at a {difficulty} difficulty level. Write statements "
        "that genuinely match that difficulty -- a Very Easy item's true "
        "statement should follow from a basic definition, while a Very "
        "Hard item's true statement should require deeper reasoning or "
        "a less obvious detail to tell apart from the false ones. Give "
        f"EVERY item exactly {num_statements} statements, lettered "
        f"{letter_list} -- never more, never fewer. Each statement must "
        "be a COMPLETE, standalone factual sentence about the topic on "
        "its own -- not a short phrase and not a direct answer to a "
        "question stem -- exactly one statement per item is true, and "
        "the rest must be false but plausible-sounding (a common "
        "misconception, a close-but-wrong fact, a swapped detail, etc.), "
        "never absurd or obviously false. "
        "Follow this EXACT layout for every item, with a blank line "
        "between items and no commentary, intro, or summary outside "
        "it:\n\n"
        "\u2022 Which statement below is true?\n"
        f"{statement_lines}\n\n"
        "\u2705 Answer: <letter>. <the true statement's text repeated>\n"
        " Reason: <one to two sentences explaining why that statement "
        "is true, and briefly why each of the other statements is "
        "false>\n\n"
        "Start every item with a single bullet character \"\u2022\" "
        "followed by a space, then exactly the text \"Which statement "
        "below is true?\" -- do not number the items and do not change "
        "or vary that bullet line's wording. Keep each statement on its "
        "own single line, with no line break inside a statement's own "
        "text. Keep the \"\u2705 Answer:\" line and the \" Reason:\" line "
        "exactly as shown above, including the checkmark and the "
        "leading space before \"Reason\".\n\n"
        "IMPORTANT -- true-statement placement: which letter is true is "
        "fixed in advance per item, below, and you must follow it "
        "exactly. Do not default to putting the true statement under "
        "the same letter over and over -- that makes it guessable "
        "without knowing the material. For item N, write the actually-"
        "true statement under the letter given below, then write the "
        f"other {num_statements - 1} statements as plausible false ones "
        "around it (never reorder or renumber this list, and never "
        "invent your own placement):\n\n"
        f"{answer_key_lines}"
    )


def _build_fill_blank_format_instructions(count: int, num_options: int, difficulty: str) -> str:
    """Prompt text for the Fill/Blanks tab: exactly `count` fill-in-the-
    blank items, each a single sentence with one blank in it (marked
    "_____") plus `num_options` lettered candidate fills -- exactly one
    correctly completes the sentence, the rest are plausible-sounding
    wrong fills. Same bullet/lettered-lines/Answer/Reason layout and same
    balanced-answer-key machinery as the MCQ's and True/False tabs (see
    _build_mcq_format_instructions) -- the only real difference is that
    the bullet line is a sentence WITH a blank in it rather than a
    question, and the lettered lines are short candidate fills (a word
    or short phrase) rather than full answer options."""
    letters, letter_list = _letters_and_phrase(num_options)
    fill_lines = "\n".join(f" {letter}. <candidate fill>" for letter in letters)
    answer_key_lines = _balanced_answer_key_lines(count, letters)

    return (
        f"Write exactly {count} fill-in-the-blank items on the topic "
        f"given below, at a {difficulty} difficulty level. Write items "
        "that genuinely match that difficulty -- a Very Easy blank "
        "should be fillable from a basic definition, while a Very Hard "
        "blank should require deeper reasoning or a less obvious detail "
        "to fill correctly. Give EVERY item exactly ONE blank in its "
        f"sentence, and exactly {num_options} candidate fills, lettered "
        f"{letter_list} -- never more, never fewer. Each candidate fill "
        "must be a short word or phrase (never a full sentence) that "
        "grammatically fits into the blank -- exactly one candidate per "
        "item is correct, and the rest must be plausible-sounding wrong "
        "fills that also fit grammatically but are factually wrong. "
        "Follow this EXACT layout for every item, with a blank line "
        "between items and no commentary, intro, or summary outside "
        "it:\n\n"
        "\u2022 <sentence with exactly one blank, written as _____>\n"
        f"{fill_lines}\n\n"
        "\u2705 Answer: <letter>. <the correct fill repeated>\n"
        " Reason: <one to two sentences explaining why that fill is "
        "correct, and briefly why each of the other fills is wrong>\n\n"
        "Start every item's sentence line with a single bullet "
        "character \"\u2022\" followed by a space, then the sentence "
        "itself -- do not number the items. Mark the blank in the "
        "sentence with exactly five underscore characters \"_____\" "
        "and nothing else (no brackets, no numbering). Keep each "
        "candidate fill on its own single line, with no line break "
        "inside a fill's own text. Keep the \"\u2705 Answer:\" line and "
        "the \" Reason:\" line exactly as shown above, including the "
        "checkmark and the leading space before \"Reason\".\n\n"
        "IMPORTANT -- correct-fill placement: which letter is correct "
        "is fixed in advance per item, below, and you must follow it "
        "exactly. Do not default to putting the correct fill under the "
        "same letter over and over -- that makes it guessable without "
        "knowing the material. For item N, write the actually-correct "
        f"fill under the letter given below, then write the other "
        f"{num_options - 1} fills as plausible wrong ones around it "
        "(never reorder or renumber this list, and never invent your "
        "own placement):\n\n"
        f"{answer_key_lines}"
    )


def _build_qa_format_instructions(count: int, difficulty: str) -> str:
    """Prompt text for the QA tab: exactly `count` plain (non-multiple-
    choice) question-and-answer pairs at the chosen difficulty level, laid
    out to match the fixed pattern this tab always pastes in -- a bulleted
    question line, then an "Answer:" line, blank line between pairs. Same
    reasoning as _build_mcq_format_instructions: the model is not trusted
    to invent its own layout."""
    return (
        f"Write exactly {count} question-and-answer pairs on the topic "
        f"given below, at a {difficulty} difficulty level. Follow this "
        "EXACT layout for every pair, with a blank line between pairs "
        "and no commentary, intro, or summary outside it:\n\n"
        "\u2022 <question text>\n"
        "Answer: <the answer, one to two sentences>\n\n"
        "Start every question line with a single bullet character "
        "\"\u2022\" followed by a space, then the question text -- do not "
        "number the questions. Keep the question and its \"Answer:\" line "
        "each on their own single line, with no line break inside "
        "either one. Write questions that genuinely match the requested "
        f"difficulty level ({difficulty}) -- a Very Easy question should "
        "be answerable from a basic definition, while a Very Hard "
        "question should require deeper reasoning or a less obvious "
        "detail."
    )

# When the AI is asked (Node mode) to answer as a single fenced code block,
# chat.deepseek.com renders that block with a toolbar row above it: a
# language-label -- "text", since the Stage-1 prompt asks for no language
# tag -- plus "Copy" and (for longer replies) "Download" buttons. Scraping
# the whole message via inner_text() (see ask_deepseek) pulls that toolbar
# row in as a literal leading line, e.g. "text Copy Download", which then
# lands in the pasted skeleton as a fake root node with every real node
# nested underneath it. This regex strips exactly that narrow token
# pattern (short language tag + Copy/Download) off the front of the reply.
_CODE_BLOCK_CHROME_RE = re.compile(
    r'^\s*[\w+.-]{0,20}\s*copy(?:\s+download)?\s*\n+',
    re.IGNORECASE,
)


def format_node_tree_as_bullets(text: str) -> str:
    """Turn a tab-indented node branch (the format GetHeadingBranchStructure-
    Adaptive() / the MCQ's tab's "Keep children nodes" checkbox produce --
    one node per line, depth = leading tab count) into an indented bullet
    list for the AI prompt, e.g.:

        Sweet
        \tOrange
        \t\tNavel
        \t\tValencia
        \tMandarin

    becomes:

        * Sweet
           * Orange
              * Navel
              * Valencia
           * Mandarin

    Three spaces per depth level, matching the size the Node tab's own
    tab-indented skeleton format reads as when eyeballed in an editor.
    Blank lines are dropped; a line's depth is just its leading tab count,
    same rule GetHeadingBranchStructureAdaptive()'s callers already rely on
    elsewhere in this file."""
    out_lines = []
    for raw_line in text.split("\n"):
        line = raw_line.rstrip("\r")
        if line.strip() == "":
            continue
        stripped = line.lstrip("\t")
        depth = len(line) - len(stripped)
        out_lines.append(" " * (depth * 3) + "* " + stripped.strip())
    return "\n".join(out_lines)


def strip_code_block_chrome(text: str) -> str:
    """Remove a leading DeepSeek code-block toolbar row (language label +
    Copy/Download buttons) that inner_text() scraped in as a fake first
    line, if present."""
    return _CODE_BLOCK_CHROME_RE.sub('', text, count=1)


def strip_central_topic_line(text: str) -> str:
    """Drop the skeleton's root line -- the "central topic", which the
    Stage-1 prompt always makes repeat the node name Node search was asked
    about -- and outdent everything else by one tab. Pasted as-is onto the
    already-selected node of that same name, the untouched skeleton
    duplicates that node as its own first child; this is what the "Strip
    the central topic before pasting" checkbox turns on."""
    lines = text.split("\n")
    start = 0
    while start < len(lines) and lines[start].strip() == "":
        start += 1
    if start >= len(lines):
        return text  # nothing but blank lines -- leave it alone
    rest = lines[start + 1:]
    outdented = [ln[1:] if ln.startswith("\t") else ln for ln in rest]
    return "\n".join(outdented).strip("\n")


# ----------------------------------------------------------------------------
# Windows API helpers (focus tracking, forcing foreground, synthetic paste)
# ----------------------------------------------------------------------------
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def get_foreground_hwnd() -> int:
    return user32.GetForegroundWindow()


def get_hwnd_process_name(hwnd: int) -> str:
    """Best-effort lower-cased exe name owning hwnd, e.g. 'xmind.exe'."""
    if not hwnd:
        return ""
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if not pid.value:
        return ""
    h_process = kernel32.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if not h_process:
        return ""
    try:
        buf_len = wintypes.DWORD(260)
        buf = ctypes.create_unicode_buffer(buf_len.value)
        # QueryFullProcessImageNameW
        ok = kernel32.QueryFullProcessImageNameW(h_process, 0, buf, ctypes.byref(buf_len))
        if not ok:
            return ""
        return os.path.basename(buf.value).lower()
    finally:
        kernel32.CloseHandle(h_process)


def force_foreground(hwnd: int) -> bool:
    """Robustly focus hwnd even though Windows normally blocks a background
    process from stealing foreground focus -- attaches this thread's input
    queue to the target window's owning thread first, which lifts that
    restriction for the duration of the call."""
    if not hwnd or not user32.IsWindow(hwnd):
        return False
    fg_hwnd = user32.GetForegroundWindow()
    if fg_hwnd == hwnd:
        return True
    fg_thread = user32.GetWindowThreadProcessId(fg_hwnd, None)
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)
    this_thread = kernel32.GetCurrentThreadId()
    attached_fg = attached_target = False
    try:
        if fg_thread and fg_thread != this_thread:
            attached_fg = bool(user32.AttachThreadInput(this_thread, fg_thread, True))
        if target_thread and target_thread != this_thread:
            attached_target = bool(user32.AttachThreadInput(this_thread, target_thread, True))
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE, in case it's minimized
        user32.SetForegroundWindow(hwnd)
        user32.BringWindowToTop(hwnd)
        return user32.GetForegroundWindow() == hwnd
    finally:
        if attached_fg:
            user32.AttachThreadInput(this_thread, fg_thread, False)
        if attached_target:
            user32.AttachThreadInput(this_thread, target_thread, False)


def get_focused_control_class(hwnd: int) -> str:
    """Best-effort class name of whatever child control currently has
    keyboard focus in the app that owns `hwnd` (e.g. "SunAwtCanvas",
    "Edit", ...). Returns "" if it can't be determined. Uses
    GetGUIThreadInfo, which -- unlike GetFocus -- can be queried for any
    thread, not just the calling one, so no AttachThreadInput dance is
    needed just to look."""
    if not hwnd:
        return ""
    thread_id = user32.GetWindowThreadProcessId(hwnd, None)
    if not thread_id:
        return ""
    info = GUITHREADINFO()
    info.cbSize = ctypes.sizeof(GUITHREADINFO)
    if not user32.GetGUIThreadInfo(thread_id, ctypes.byref(info)):
        return ""
    focus_hwnd = info.hwndFocus
    if not focus_hwnd:
        return ""
    buf = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(focus_hwnd, buf, 256)
    return buf.value


_GWL_EXSTYLE = -20
_WS_EX_NOACTIVATE = 0x08000000


def set_toolbar_noactivate(hwnd: int, enable: bool) -> None:
    """Toggle WS_EX_NOACTIVATE on our own floating toolbar window.

    While enabled, Windows will never switch the OS's foreground/active
    window to this one -- not on a button click, and not as a side effect
    of it being always-on-top and getting reasserted in z-order whenever
    XMind is brought forward. That's what was letting the toolbar steal
    focus back from XMind mid-paste. Button clicks still work as normal
    while this is on: Windows still delivers the click message, it just
    skips the automatic activation that would normally follow it.

    Typing into the Entry/ScrolledText fields DOES require the window to
    actually be the active one, though, so this is only switched on right
    before the automated ask-AI-and-paste sequence starts, and switched
    back off as soon as it ends (success or failure) so the toolbar is
    clickable/typable again for the next query."""
    if not hwnd:
        return
    ex_style = user32.GetWindowLongW(hwnd, _GWL_EXSTYLE)
    new_style = (ex_style | _WS_EX_NOACTIVATE) if enable else (ex_style & ~_WS_EX_NOACTIVATE)
    user32.SetWindowLongW(hwnd, _GWL_EXSTYLE, new_style)


# --- synthetic Ctrl+V via SendInput -----------------------------------------
INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
VK_CONTROL = 0x11
VK_V = 0x56


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD),
                ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG))]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", _INPUTUNION)]


def _send_key(vk: int, key_up: bool = False):
    inp = INPUT(type=INPUT_KEYBOARD,
                union=_INPUTUNION(ki=KEYBDINPUT(
                    wVk=vk, wScan=0,
                    dwFlags=KEYEVENTF_KEYUP if key_up else 0,
                    time=0, dwExtraInfo=None)))
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def send_ctrl_v():
    _send_key(VK_CONTROL, key_up=False)
    time.sleep(0.03)
    _send_key(VK_V, key_up=False)
    time.sleep(0.03)
    _send_key(VK_V, key_up=True)
    time.sleep(0.03)
    _send_key(VK_CONTROL, key_up=True)


# ----------------------------------------------------------------------------
# Note formatting: force H1 headings ourselves rather than trusting the AI
# to have followed _NOTE_FORMAT_INSTRUCTIONS. Prompting alone isn't reliable
# enough to depend on for every reply, so this is a deterministic, code-level
# guarantee that runs on every "Note" mode reply before it ever reaches the
# clipboard. Two representations are built from the same lines:
#   - build_note_html(): a REAL "<h1>...</h1>" HTML fragment, for the
#     CF_HTML clipboard format -- this is what makes XMind (if its note
#     editor renders pasted rich text) show an actual formatted heading.
#   - ensure_h1_headers(): a plain "# ..." markdown fallback, used as the
#     CF_UNICODETEXT companion data and as the last-resort %TEMP%\*.txt
#     route if the CF_HTML clipboard write can't be done at all.
# ----------------------------------------------------------------------------
def _note_lines(text: str) -> list:
    """Split an AI reply into clean, non-blank lines for the Note tab,
    stripping any heading markers (H1-H6) the AI may have already added
    so neither representation below ends up double-prefixed."""
    lines = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        line = re.sub(r'^#{1,6}\s*', '', line)
        lines.append(line)
    return lines


def ensure_h1_headers(text: str) -> str:
    """Return `text` with every non-blank line forced into an H1 markdown
    heading ('# ...'). This is the plain-text fallback -- it will show up
    as literal '#' characters wherever real HTML formatting isn't used or
    isn't supported."""
    return "\n".join(f"# {line}" for line in _note_lines(text))


def build_note_html(text: str) -> str:
    """Return an HTML fragment with every non-blank line of `text` wrapped
    in a real '<h1>...</h1>' tag, for use as CF_HTML clipboard data."""
    return "".join(f"<h1>{html.escape(line)}</h1>" for line in _note_lines(text))


def _global_alloc_bytes(data: bytes) -> int:
    """Copy `data` into newly allocated GMEM_MOVEABLE global memory and
    return the handle, the form the clipboard APIs require ownership of."""
    h_mem = kernel32.GlobalAlloc(_GMEM_MOVEABLE, len(data))
    if not h_mem:
        raise RuntimeError("GlobalAlloc failed")
    ptr = kernel32.GlobalLock(h_mem)
    if not ptr:
        kernel32.GlobalFree(h_mem)
        raise RuntimeError("GlobalLock failed")
    try:
        ctypes.memmove(ptr, data, len(data))
    finally:
        kernel32.GlobalUnlock(h_mem)
    return h_mem


def _build_cf_html_bytes(fragment_html: str) -> bytes:
    """Wrap an HTML fragment in the header Windows' 'HTML Format' clipboard
    format requires (see the CF_HTML spec on MSDN): a handful of decimal
    byte-offset fields pointing back into this same payload, telling the
    receiving app exactly which byte range is the pasteable fragment.
    The offset fields are zero-padded to a fixed width (10 digits) so the
    header's own byte length doesn't change once the real numbers are
    substituted in -- that's what makes computing them in one pass safe."""
    header_template = (
        "Version:0.9\r\n"
        "StartHTML:{start_html:010d}\r\n"
        "EndHTML:{end_html:010d}\r\n"
        "StartFragment:{start_fragment:010d}\r\n"
        "EndFragment:{end_fragment:010d}\r\n"
    )
    prefix = "<html><body>\r\n<!--StartFragment-->"
    suffix = "<!--EndFragment-->\r\n</body></html>"

    header_len = len(header_template.format(
        start_html=0, end_html=0, start_fragment=0, end_fragment=0).encode("utf-8"))
    start_html = header_len
    start_fragment = start_html + len(prefix.encode("utf-8"))
    end_fragment = start_fragment + len(fragment_html.encode("utf-8"))
    end_html = end_fragment + len(suffix.encode("utf-8"))

    header = header_template.format(
        start_html=start_html, end_html=end_html,
        start_fragment=start_fragment, end_fragment=end_fragment)
    return (header + prefix + fragment_html + suffix).encode("utf-8")


def set_clipboard_html(html_fragment: str, plain_fallback: str) -> bool:
    """Put a REAL HTML fragment on the clipboard using Windows' CF_HTML
    format, alongside a plain-text (CF_UNICODETEXT) fallback in the same
    clipboard-open session. An app whose paste handler understands rich
    text (CF_HTML) -- which is what would let XMind show an actual
    rendered heading instead of literal '#' text -- picks that up; a
    plain-text-only target still gets the readable fallback string.
    Returns False (rather than raising) on any failure, so the caller can
    fall back to the %TEMP%\\*.txt + clip.exe route."""
    cf_html_id = user32.RegisterClipboardFormatW("HTML Format")
    if not cf_html_id:
        return False

    html_bytes = _build_cf_html_bytes(html_fragment)
    text_bytes = plain_fallback.encode("utf-16-le") + b"\x00\x00"

    if not user32.OpenClipboard(None):
        return False
    try:
        user32.EmptyClipboard()
        h_html = _global_alloc_bytes(html_bytes)
        h_text = _global_alloc_bytes(text_bytes)
        ok_html = bool(user32.SetClipboardData(cf_html_id, h_html))
        ok_text = bool(user32.SetClipboardData(_CF_UNICODETEXT, h_text))
        # SetClipboardData takes ownership of the handle on success -- only
        # free it ourselves when the call failed, or Windows double-frees it.
        if not ok_html:
            kernel32.GlobalFree(h_html)
        if not ok_text:
            kernel32.GlobalFree(h_text)
        return ok_html or ok_text
    finally:
        user32.CloseClipboard()


def set_clipboard_text(text: str, root: tk.Tk) -> None:
    """Put `text` on the Windows clipboard.

    Tries Tk's clipboard first, since that's simplest and works for almost
    everything. If that raises for any reason (Tk's clipboard API can be
    flaky with large blocks of multiline text), falls back to writing the
    text to a .txt file in %TEMP% and piping that file into it via
    Windows' built-in clip.exe -- reading straight from a file on disk
    sidesteps whatever Tk choked on."""
    try:
        root.clipboard_clear()
        root.clipboard_append(text)
        root.update()  # make sure Tk actually commits the clipboard write
        return
    except Exception:
        pass  # fall through to the file-based fallback below

    tmp_path = os.path.join(tempfile.gettempdir(), f"xmind_ai_note_{int(time.time())}.txt")
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(text)
    try:
        with open(tmp_path, "r", encoding="utf-8") as f:
            subprocess.run(["clip"], stdin=f, check=True)
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


# ----------------------------------------------------------------------------
# DeepSeek automation (Playwright, profiled persistent context)
# ----------------------------------------------------------------------------
def run_login_setup(log=print):
    """One-time, VISIBLE browser on this tool's own saved profile so you can
    log into DeepSeek by hand. Close the window when you're done."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise ImportError("Playwright isn't installed -- run: pip install playwright && playwright install chromium")

    os.makedirs(_PROFILE_DIR, exist_ok=True)
    log(f"Profile folder: {_PROFILE_DIR}")
    with sync_playwright() as pw:
        common_kwargs = dict(
            headless=False, viewport=None,
            ignore_default_args=["--enable-automation"],
            args=["--disable-blink-features=AutomationControlled", "--window-size=1200,850"],
        )
        try:
            context = pw.chromium.launch_persistent_context(_PROFILE_DIR, channel="chrome", **common_kwargs)
            log("Using your installed Google Chrome.")
        except Exception:
            context = pw.chromium.launch_persistent_context(_PROFILE_DIR, **common_kwargs)
            log("Google Chrome not found -- using bundled Chromium.")
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(_DEEPSEEK_URL)
        log("Log into DeepSeek, then just close the browser window.")
        while context.pages:
            try:
                context.pages[0].wait_for_event("close", timeout=1000)
            except Exception:
                pass
        try:
            context.close()
        except Exception:
            pass
    # Write an explicit marker so a later run can tell "login setup ran and
    # the browser was actually closed normally" apart from "the profile
    # folder merely exists" (os.makedirs above creates it unconditionally,
    # even if you Ctrl+C the script before logging in at all).
    with open(_LOGIN_MARKER, "w") as f:
        f.write(f"logged in at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    log("Done -- session saved.")


def _launch_persistent_context(pw):
    """Launch the shared, profiled Chromium context. Called exactly once
    per app run (see _BrowserWorker) rather than once per query. Raises
    RuntimeError with a human-readable message on anything that goes
    wrong (no profile data yet, profile locked by another browser, etc.)."""
    profile_has_data = os.path.isdir(_PROFILE_DIR) and len(os.listdir(_PROFILE_DIR)) > 0
    if not profile_has_data:
        raise RuntimeError(
            "No Chromium profile data found at:\n"
            f"  {_PROFILE_DIR}\n"
            "Log into DeepSeek first, either through the OTHER script's "
            "'Open Browser & Search There' mini-browser (same profile folder), "
            "or by running this script with --login.")

    common_kwargs = dict(
        headless=True,
        viewport={"width": 1280, "height": 800},
        ignore_default_args=["--enable-automation"],
        args=["--disable-blink-features=AutomationControlled"],
    )
    try:
        return pw.chromium.launch_persistent_context(_PROFILE_DIR, channel="chrome", **common_kwargs)
    except Exception:
        try:
            return pw.chromium.launch_persistent_context(_PROFILE_DIR, **common_kwargs)
        except Exception as e:
            if "ProcessSingleton" in str(e) or "SingletonLock" in str(e) or "in use" in str(e).lower():
                raise RuntimeError(
                    "Couldn't open the shared Chromium profile -- it's "
                    "locked by another running browser on it. Close the "
                    "other script's 'Open Browser & Search There' mini-"
                    "browser (or any other Chrome window on that same "
                    "profile) and try again.")
            raise RuntimeError(f"Couldn't launch Chromium: {e}")


def _query_deepseek_in_tab(context, prompt: str, timeout_s: int, log=lambda msg: None) -> str:
    """Open a fresh TAB in the already-running `context`, run one query
    end to end, close the tab, and return the scraped reply text. Raises
    RuntimeError on failure. Opening a new tab (instead of relaunching
    Chromium) is what lets repeated queries reuse the same already-
    warmed-up, already-logged-in browser."""
    from playwright.sync_api import TimeoutError as PWTimeout

    sel = _DEEPSEEK_SELECTORS
    page = context.new_page()
    try:
        page.goto(_DEEPSEEK_URL, wait_until="domcontentloaded")

        try:
            page.wait_for_selector(sel["composer"], timeout=15000)
        except PWTimeout:
            log(f"_query_deepseek_in_tab: composer not found. Current URL: {page.url}")
            raise RuntimeError(
                "Couldn't find DeepSeek's input box -- you may be logged "
                "out (run with --login again) or DeepSeek changed the "
                "page and the selectors in _DEEPSEEK_SELECTORS need updating.")

        page.click(sel["composer"])
        page.keyboard.insert_text(prompt)

        # A fresh tab always starts blank, but keep the same
        # count-before/wait-for-growth pattern for safety in case
        # DeepSeek ever preloads something into a new tab.
        messages = page.locator(sel["assistant_messages"])
        initial_count = messages.count()
        page.keyboard.press("Enter")

        deadline = time.time() + timeout_s
        while messages.count() <= initial_count:
            if time.time() > deadline:
                raise RuntimeError("No new assistant reply appeared on the page (selectors may be stale).")
            time.sleep(0.3)

        # Poll the new reply's text until it stops changing across
        # consecutive checks (streaming replies grow steadily; a
        # finished reply holds still). No confirmed selector exists for
        # a "stop generating" button, so this is the reliable signal.
        last_text = None
        stable_checks = 0
        while time.time() < deadline:
            count = messages.count()
            text = messages.nth(count - 1).inner_text().strip()
            if text and text == last_text:
                stable_checks += 1
                if stable_checks >= 3:  # ~1.5s of no change -> treat as done
                    break
            else:
                stable_checks = 0
            last_text = text
            time.sleep(0.5)
        else:
            raise RuntimeError(f"DeepSeek didn't finish responding within {timeout_s}s.")

        count = messages.count()
        if count == 0:
            raise RuntimeError("No assistant reply found on the page (selectors may be stale).")
        text = messages.nth(count - 1).inner_text().strip()
        if not text:
            raise RuntimeError("Assistant reply came back empty.")
        text = strip_code_block_chrome(text)

        return text
    finally:
        try:
            page.close()
        except Exception:
            pass


class _BrowserWorker:
    """Owns the single, persistent, PROFILED Chromium context used for
    every DeepSeek query, for the life of the app.

    Playwright's sync API is thread-affine -- a browser/context/page
    created on one thread can't safely be driven from a different thread
    -- so this dedicates ONE long-lived background thread to own it.
    Chromium is launched the first time a query comes in (ensure_started)
    and then left running; every query after that reuses the SAME
    browser and just opens a new tab (see _query_deepseek_in_tab), rather
    than paying Chromium's startup cost again on every click."""

    _SHUTDOWN = object()

    def __init__(self):
        self._jobs = queue.Queue()
        self._thread = None
        self._start_lock = threading.Lock()

    def ensure_started(self):
        with self._start_lock:
            if self._thread is None:
                self._thread = threading.Thread(target=self._run, daemon=True)
                self._thread.start()

    def ask(self, prompt: str, timeout_s: int = 120) -> str:
        self.ensure_started()
        result = {}
        done = threading.Event()
        self._jobs.put(("ask", prompt, timeout_s, result, done))
        done.wait()
        if "error" in result:
            raise result["error"]
        return result["text"]

    def shutdown(self, timeout_s: float = 10.0):
        """Close the persistent Chromium context, if it's running. Safe
        to call even if no query was ever made."""
        if self._thread is None:
            return
        done = threading.Event()
        self._jobs.put((self._SHUTDOWN, None, None, {}, done))
        done.wait(timeout=timeout_s)

    def _run(self):
        # This whole method runs on self._thread for the life of the app
        # -- context and every page/tab it opens are only ever touched
        # from here, which is what makes reusing them across clicks safe.
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            context = None
            while True:
                kind, prompt, timeout_s, result, done = self._jobs.get()
                if kind is self._SHUTDOWN:
                    if context is not None:
                        try:
                            context.close()
                        except Exception:
                            pass
                    done.set()
                    break
                try:
                    if context is None:
                        context = _launch_persistent_context(pw)
                    result["text"] = _query_deepseek_in_tab(context, prompt, timeout_s, log=print)
                except Exception as e:
                    result["error"] = e
                finally:
                    done.set()


_browser_worker = _BrowserWorker()


def ask_deepseek(prompt: str, timeout_s: int = 120) -> str:
    """Run one query against DeepSeek using the single persistent,
    PROFILED Chromium browser -- launched on first use and reused (one
    new tab per query) for every query after that. Raises RuntimeError
    with a human-readable message on anything that goes wrong (not
    logged in, selectors stale, timed out, etc.)."""
    return _browser_worker.ask(prompt, timeout_s)


def shutdown_browser():
    """Close the persistent Chromium browser, if it's running. Called
    when the floating toolbar window closes (see FloatingToolbar)."""
    _browser_worker.shutdown()


# ----------------------------------------------------------------------------
# Floating always-on-top toolbar
# ----------------------------------------------------------------------------
class FloatingToolbar:
    POLL_MS = 150
    BRIDGE_POLL_MS = 200

    # Bridge files the AHK script writes to (see SendAISearchRequest() /
    # PerformAISearch() there) when RButton is held and XButton2 is
    # pressed. request.txt holds the captured node name or note content;
    # request.ready is written last and is the actual "go" signal, so a
    # request is never read half-written.
    _BRIDGE_DIR = os.path.join(tempfile.gettempdir(), "xmind_ai_bridge")
    _BRIDGE_REQUEST = os.path.join(_BRIDGE_DIR, "request.txt")
    _BRIDGE_FLAG = os.path.join(_BRIDGE_DIR, "request.ready")
    # Reverse-direction flag: dropped once the AI reply is safely on the
    # clipboard, to ask the AHK script -- not this process -- to actually
    # bring XMind to the foreground and press Ctrl+V. This process's own
    # attempt to do that itself (SetForegroundWindow + a synthetic
    # SendInput Ctrl+V) was reliably copying the reply but never visibly
    # pasting it, so the actual keystroke now happens on the AHK side,
    # which already does this successfully elsewhere for the same window.
    _BRIDGE_PASTE_READY = os.path.join(_BRIDGE_DIR, "paste.ready")
    # AHK drops this when XButton2 (Shift Scroll) is pressed while XButton1
    # (the master features toggle) is OFF, so an in-flight AI request gets
    # abandoned immediately -- nothing gets pasted, even if the DeepSeek
    # call itself is still running when it happens. (Merely turning
    # XButton1 OFF no longer cancels anything.)
    _BRIDGE_CANCEL = os.path.join(_BRIDGE_DIR, "cancel.request")
    # Reverse-direction flag: exists exactly while an AI request is being
    # worked on (see the _busy property below). The AHK script checks it --
    # along with request.ready/request.txt/paste.ready -- to know whether an
    # "F11 session" is ongoing when XButton2 is pressed with features OFF,
    # so it can show the "F11 ongoing session terminated" tooltip.
    _BRIDGE_BUSY = os.path.join(_BRIDGE_DIR, "busy.flag")
    # Forward-direction flag: this process creates/deletes this file so
    # the AHK script knows whether the MCQ's tab's "Keep children nodes"
    # checkbox is checked AND that tab is the one currently active. When
    # present, AHK's PerformAISearch() sends the WHOLE captured branch
    # (the node plus every subnode, still tab-indented) instead of
    # trimming down to just the selected node's own name -- see
    # _sync_keep_children_flag() below.
    _BRIDGE_KEEP_CHILDREN = os.path.join(_BRIDGE_DIR, "keep_children.flag")
    # Dropped by the AHK script's own exit handler (CleanupBeforeExit) right
    # before the script itself closes, so this process shuts down with it
    # instead of being left running in the background. Polled for and acted
    # on here -- rather than just force-killed from the AHK side -- so that
    # main()'s atexit-registered shutdown_browser() still gets to run and
    # close the persistent Chromium browser cleanly.
    _BRIDGE_EXIT = os.path.join(_BRIDGE_DIR, "exit.request")

    @property
    def _busy(self) -> bool:
        return self._busy_state

    @_busy.setter
    def _busy(self, value: bool):
        # Every place that flips _busy (request started, finished, errored,
        # cancelled) automatically mirrors it into busy.flag for AHK.
        self._busy_state = bool(value)
        try:
            if self._busy_state:
                os.makedirs(self._BRIDGE_DIR, exist_ok=True)
                with open(self._BRIDGE_BUSY, "w") as f:
                    f.write("1")
            elif os.path.isfile(self._BRIDGE_BUSY):
                os.remove(self._BRIDGE_BUSY)
        except OSError:
            pass

    def __init__(self, root: tk.Tk):
        self.root = root
        self.last_external_hwnd = 0
        self._own_hwnd = None

        root.title("XMind AI Note Assistant")
        root.attributes("-topmost", True)
        root.geometry("360x510+80+80")
        root.resizable(False, False)

        self.notebook = ttk.Notebook(root)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=(8, 0))

        node_tab = tk.Frame(self.notebook)
        note_tab = tk.Frame(self.notebook)
        self.notebook.add(node_tab, text="Node")
        self.notebook.add(note_tab, text="Note")

        # The Note tab itself holds a second, nested notebook with five
        # pages: "Content" (the original H1-per-line note generator, with
        # its 8 instruction presets), "MCQ's" (multiple-choice question
        # generation, with its question-count spinbox and 10 options-count
        # buttons), "True/False" (a set of lettered statements per item,
        # exactly one true, same 10-button options grid), "Fill/Blanks"
        # (a fill-in-the-blank sentence per item with lettered candidate
        # fills, same 10-button grid again), and "QA" (plain question-
        # and-answer generation, with its own question-count spinbox and
        # a 5-level difficulty dropdown -- the same dropdown levels also
        # appear, as a recommendation only, on MCQ's/True-False/Fill-
        # Blanks). All five pages still count as "the Note tab" one level
        # up -- _get_active_page() below is what tells them apart.
        self.note_subnotebook = ttk.Notebook(note_tab)
        self.note_subnotebook.pack(fill="both", expand=True)
        note_content_tab = tk.Frame(self.note_subnotebook)
        mcq_tab = tk.Frame(self.note_subnotebook)
        tf_tab = tk.Frame(self.note_subnotebook)
        fb_tab = tk.Frame(self.note_subnotebook)
        qa_tab = tk.Frame(self.note_subnotebook)
        self.note_subnotebook.add(note_content_tab, text="Content")
        self.note_subnotebook.add(mcq_tab, text="MCQ's")
        self.note_subnotebook.add(tf_tab, text="True/False")
        self.note_subnotebook.add(fb_tab, text="Fill/Blanks")
        self.note_subnotebook.add(qa_tab, text="QA")

        # The keep-children flag (see _BRIDGE_KEEP_CHILDREN) must only be
        # "on" from AHK's point of view while the MCQ's tab is actually the
        # active one -- switching away to Node/Content should turn it back
        # off even though the checkbox itself stays checked underneath, and
        # switching back to MCQ's should turn it back on. Re-run the sync
        # on every tab change on both notebooks (outer Node/Note, and the
        # inner Content/MCQ's) to keep the flag file honest either way.
        self.notebook.bind("<<NotebookTabChanged>>", lambda e: self._sync_keep_children_flag())
        self.note_subnotebook.bind("<<NotebookTabChanged>>", lambda e: self._sync_keep_children_flag())

        size_row = tk.Frame(node_tab)
        size_row.pack(fill="x", pady=(4, 0))
        tk.Label(size_row, text="Mindmap size").pack(side="left")
        self.size_var = tk.StringVar(value=_NODE_DEFAULT_SIZE_TIER)
        self.size_menu = ttk.Combobox(
            size_row, textvariable=self.size_var, values=_NODE_SIZE_TIERS,
            state="readonly", width=10,
        )
        self.size_menu.pack(side="left", padx=(6, 0))

        # Checked by default: the AI's skeleton always starts with a root
        # line repeating the node name (that's how the Stage-1 prompt is
        # designed), which -- pasted as-is onto the already-selected node
        # of that same name -- duplicates it as its own child. Stripping
        # that first line (and outdenting everything under it by one tab)
        # before pasting avoids that duplicate for the normal case. Left
        # unchecked on purpose for scenarios that actually want the root
        # line kept (e.g. pasting onto a differently-named/blank node).
        self.strip_central_var = tk.BooleanVar(value=True)
        self.strip_central_check = tk.Checkbutton(
            node_tab, text="Strip the central topic before pasting",
            variable=self.strip_central_var,
        )
        self.strip_central_check.pack(anchor="w", pady=(2, 0))

        tk.Label(node_tab, text="Node instructions (asks AI for a tab-indented "
                                 "sub-node outline)").pack(anchor="w", pady=(4, 0))
        self.node_instr_text = scrolledtext.ScrolledText(node_tab, height=8, wrap="word")
        self.node_instr_text.pack(fill="both", expand=True)

        tk.Label(note_content_tab, text="Note instructions (asks AI for H1-per-line "
                                 "content)").pack(anchor="w", pady=(4, 0))

        # Numbered quick-pick preset buttons -- click a number to drop that
        # preset straight into the Instructions box below instead of typing
        # it out. See _NOTE_INSTRUCTION_PRESETS for what each number sends;
        # hovering a button shows its full text in the status line.
        preset_row = tk.Frame(note_content_tab)
        preset_row.pack(anchor="w", pady=(2, 2))
        PRESETS_PER_ROW = 4
        for i, preset_text in enumerate(_NOTE_INSTRUCTION_PRESETS):
            btn = tk.Button(
                preset_row, text=str(i + 1), width=3,
                font=("Segoe UI", 10, "bold"),
                command=lambda t=preset_text: self._apply_note_preset(t),
            )
            btn.grid(row=i // PRESETS_PER_ROW, column=i % PRESETS_PER_ROW, padx=2, pady=2)
            btn.bind("<Enter>", lambda e, t=preset_text: self._set_status(t))
            btn.bind("<Leave>", lambda e: self._set_status("Idle"))

        self.note_instr_text = scrolledtext.ScrolledText(note_content_tab, height=8, wrap="word")
        self.note_instr_text.pack(fill="both", expand=True)

        # --- MCQ's tab -----------------------------------------------
        count_row = tk.Frame(mcq_tab)
        count_row.pack(anchor="w", pady=(4, 0))
        tk.Label(count_row, text="Number of questions").pack(side="left")
        self.mcq_count_var = tk.IntVar(value=30)
        self.mcq_count_spin = tk.Spinbox(
            count_row, from_=10, to=500, increment=10,
            textvariable=self.mcq_count_var, width=6, justify="center",
        )
        self.mcq_count_spin.pack(side="left", padx=(6, 0))
        # Tk's Spinbox has no mouse-wheel handling built in at all -- wire
        # one up here so scrolling over it steps by 10 (matching the
        # arrow buttons' own "increment"), not Tk's usual default of 1.
        self.mcq_count_spin.bind("<MouseWheel>", self._on_mcq_count_scroll)
        self.mcq_count_spin.bind("<Button-4>", self._on_mcq_count_scroll)
        self.mcq_count_spin.bind("<Button-5>", self._on_mcq_count_scroll)

        mcq_diff_row = tk.Frame(mcq_tab)
        mcq_diff_row.pack(anchor="w", pady=(6, 0))
        tk.Label(mcq_diff_row, text="Difficulty").pack(side="left")
        self.mcq_difficulty_var = tk.StringVar(value=_DIFFICULTY_LEVELS[0])
        self.mcq_difficulty_menu = ttk.Combobox(
            mcq_diff_row, textvariable=self.mcq_difficulty_var,
            values=_DIFFICULTY_LEVELS, state="readonly", width=12,
        )
        self.mcq_difficulty_menu.pack(side="left", padx=(6, 0))
        # Difficulty only RECOMMENDS an options-per-question count (via the
        # label below) -- it deliberately does not touch the options
        # buttons itself. Question difficulty and option count are
        # independent in practice (a 4-option question can be brutally
        # hard, a 13-option one can be trivial), so forcing one from the
        # other was wrong; this just folds the chosen difficulty into the
        # prompt text and offers a suggestion, leaving the actual option
        # count entirely up to whichever button you click below.
        self.mcq_difficulty_menu.bind("<<ComboboxSelected>>", self._on_mcq_difficulty_change)
        self.mcq_recommend_var = tk.StringVar(value="")
        tk.Label(mcq_tab, textvariable=self.mcq_recommend_var, fg="#555",
                 wraplength=330, justify="left").pack(anchor="w", pady=(2, 0))

        tk.Label(mcq_tab, text="Options per question"
                 ).pack(anchor="w", pady=(6, 0))
        self._mcq_option_buttons = self._build_lettered_options_row(
            mcq_tab, self._select_mcq_options)
        self.mcq_num_options_var = tk.IntVar(value=_MCQ_MIN_OPTIONS)
        self._select_mcq_options(_MCQ_MIN_OPTIONS)  # button "1" selected by default
        self._on_mcq_difficulty_change()  # populate the recommendation label

        # Checked by default: MCQ generation almost always wants the fuller
        # context (the node plus every subnode beneath it) rather than just
        # a bare name, so the AI has real material to write questions from.
        # Unchecking it falls back to sending only the selected node's own
        # name (subnodes stripped down to the first captured line, same as
        # the Node tab). Actually skipping the strip happens on the AHK
        # side (it's the one doing the capturing); this checkbox just keeps
        # a small flag file in sync so AHK knows the current state -- see
        # _sync_keep_children_flag().
        self.mcq_keep_children_var = tk.BooleanVar(value=True)
        self.mcq_keep_children_check = tk.Checkbutton(
            mcq_tab, text="Keep children nodes (don't strip -- give AI the full branch)",
            variable=self.mcq_keep_children_var,
            command=self._sync_keep_children_flag,
        )
        self.mcq_keep_children_check.pack(anchor="w", pady=(6, 0))

        tk.Label(mcq_tab, text="MCQ instructions (topic to quiz on)"
                 ).pack(anchor="w", pady=(6, 0))
        self.mcq_instr_text = scrolledtext.ScrolledText(mcq_tab, height=6, wrap="word")
        self.mcq_instr_text.pack(fill="both", expand=True)

        # --- True/False tab --------------------------------------------
        # Each item is a small set of lettered, complete statements about
        # the topic -- exactly one is true, the rest are plausible-sounding
        # false statements -- and the task is picking out the true one.
        # Structurally this is the MCQ's tab with statements standing in
        # for answer options (see _build_true_false_format_instructions),
        # so it reuses the exact same widgets/helpers as the MCQ's tab
        # above, just under a "tf_" prefix and with wording that says
        # "statements" instead of "options".
        tf_count_row = tk.Frame(tf_tab)
        tf_count_row.pack(anchor="w", pady=(4, 0))
        tk.Label(tf_count_row, text="Number of items").pack(side="left")
        self.tf_count_var = tk.IntVar(value=30)
        self.tf_count_spin = tk.Spinbox(
            tf_count_row, from_=10, to=500, increment=10,
            textvariable=self.tf_count_var, width=6, justify="center",
        )
        self.tf_count_spin.pack(side="left", padx=(6, 0))
        self.tf_count_spin.bind("<MouseWheel>", self._on_tf_count_scroll)
        self.tf_count_spin.bind("<Button-4>", self._on_tf_count_scroll)
        self.tf_count_spin.bind("<Button-5>", self._on_tf_count_scroll)

        tf_diff_row = tk.Frame(tf_tab)
        tf_diff_row.pack(anchor="w", pady=(6, 0))
        tk.Label(tf_diff_row, text="Difficulty").pack(side="left")
        self.tf_difficulty_var = tk.StringVar(value=_DIFFICULTY_LEVELS[0])
        self.tf_difficulty_menu = ttk.Combobox(
            tf_diff_row, textvariable=self.tf_difficulty_var,
            values=_DIFFICULTY_LEVELS, state="readonly", width=12,
        )
        self.tf_difficulty_menu.pack(side="left", padx=(6, 0))
        self.tf_difficulty_menu.bind("<<ComboboxSelected>>", self._on_tf_difficulty_change)
        self.tf_recommend_var = tk.StringVar(value="")
        tk.Label(tf_tab, textvariable=self.tf_recommend_var, fg="#555",
                 wraplength=330, justify="left").pack(anchor="w", pady=(2, 0))

        tk.Label(tf_tab, text="Statements per item (one true, rest false)"
                 ).pack(anchor="w", pady=(6, 0))
        self._tf_option_buttons = self._build_lettered_options_row(
            tf_tab, self._select_tf_options)
        self.tf_num_options_var = tk.IntVar(value=_MCQ_MIN_OPTIONS)
        self._select_tf_options(_MCQ_MIN_OPTIONS)
        self._on_tf_difficulty_change()

        self.tf_keep_children_var = tk.BooleanVar(value=True)
        self.tf_keep_children_check = tk.Checkbutton(
            tf_tab, text="Keep children nodes (don't strip -- give AI the full branch)",
            variable=self.tf_keep_children_var,
            command=self._sync_keep_children_flag,
        )
        self.tf_keep_children_check.pack(anchor="w", pady=(6, 0))

        tk.Label(tf_tab, text="True/False instructions (topic to quiz on)"
                 ).pack(anchor="w", pady=(6, 0))
        self.tf_instr_text = scrolledtext.ScrolledText(tf_tab, height=6, wrap="word")
        self.tf_instr_text.pack(fill="both", expand=True)

        # --- Fill/Blanks tab ---------------------------------------------
        # Each item is a sentence with a blank in it, plus lettered
        # candidate fills -- exactly one correctly completes the sentence,
        # the rest are plausible-sounding wrong fills. Same underlying
        # letter/options-count/balanced-answer-key machinery as the MCQ's
        # tab again (see _build_fill_blank_format_instructions).
        fb_count_row = tk.Frame(fb_tab)
        fb_count_row.pack(anchor="w", pady=(4, 0))
        tk.Label(fb_count_row, text="Number of items").pack(side="left")
        self.fb_count_var = tk.IntVar(value=30)
        self.fb_count_spin = tk.Spinbox(
            fb_count_row, from_=10, to=500, increment=10,
            textvariable=self.fb_count_var, width=6, justify="center",
        )
        self.fb_count_spin.pack(side="left", padx=(6, 0))
        self.fb_count_spin.bind("<MouseWheel>", self._on_fb_count_scroll)
        self.fb_count_spin.bind("<Button-4>", self._on_fb_count_scroll)
        self.fb_count_spin.bind("<Button-5>", self._on_fb_count_scroll)

        fb_diff_row = tk.Frame(fb_tab)
        fb_diff_row.pack(anchor="w", pady=(6, 0))
        tk.Label(fb_diff_row, text="Difficulty").pack(side="left")
        self.fb_difficulty_var = tk.StringVar(value=_DIFFICULTY_LEVELS[0])
        self.fb_difficulty_menu = ttk.Combobox(
            fb_diff_row, textvariable=self.fb_difficulty_var,
            values=_DIFFICULTY_LEVELS, state="readonly", width=12,
        )
        self.fb_difficulty_menu.pack(side="left", padx=(6, 0))
        self.fb_difficulty_menu.bind("<<ComboboxSelected>>", self._on_fb_difficulty_change)
        self.fb_recommend_var = tk.StringVar(value="")
        tk.Label(fb_tab, textvariable=self.fb_recommend_var, fg="#555",
                 wraplength=330, justify="left").pack(anchor="w", pady=(2, 0))

        tk.Label(fb_tab, text="Candidate fills per blank"
                 ).pack(anchor="w", pady=(6, 0))
        self._fb_option_buttons = self._build_lettered_options_row(
            fb_tab, self._select_fb_options)
        self.fb_num_options_var = tk.IntVar(value=_MCQ_MIN_OPTIONS)
        self._select_fb_options(_MCQ_MIN_OPTIONS)
        self._on_fb_difficulty_change()

        self.fb_keep_children_var = tk.BooleanVar(value=True)
        self.fb_keep_children_check = tk.Checkbutton(
            fb_tab, text="Keep children nodes (don't strip -- give AI the full branch)",
            variable=self.fb_keep_children_var,
            command=self._sync_keep_children_flag,
        )
        self.fb_keep_children_check.pack(anchor="w", pady=(6, 0))

        tk.Label(fb_tab, text="Fill/Blanks instructions (topic to quiz on)"
                 ).pack(anchor="w", pady=(6, 0))
        self.fb_instr_text = scrolledtext.ScrolledText(fb_tab, height=6, wrap="word")
        self.fb_instr_text.pack(fill="both", expand=True)

        # --- QA tab ----------------------------------------------------
        qa_count_row = tk.Frame(qa_tab)
        qa_count_row.pack(anchor="w", pady=(4, 0))
        tk.Label(qa_count_row, text="Number of questions").pack(side="left")
        self.qa_count_var = tk.IntVar(value=20)
        self.qa_count_spin = tk.Spinbox(
            qa_count_row, from_=5, to=500, increment=5,
            textvariable=self.qa_count_var, width=6, justify="center",
        )
        self.qa_count_spin.pack(side="left", padx=(6, 0))
        # Same mouse-wheel wiring as the MCQ's tab's count spinbox -- Tk's
        # Spinbox has no built-in wheel handling, so scrolling over it
        # would otherwise do nothing at all.
        self.qa_count_spin.bind("<MouseWheel>", self._on_qa_count_scroll)
        self.qa_count_spin.bind("<Button-4>", self._on_qa_count_scroll)
        self.qa_count_spin.bind("<Button-5>", self._on_qa_count_scroll)

        diff_row = tk.Frame(qa_tab)
        diff_row.pack(anchor="w", pady=(6, 0))
        tk.Label(diff_row, text="Difficulty").pack(side="left")
        self.qa_difficulty_var = tk.StringVar(value=_DEFAULT_DIFFICULTY)
        self.qa_difficulty_menu = ttk.Combobox(
            diff_row, textvariable=self.qa_difficulty_var,
            values=_DIFFICULTY_LEVELS, state="readonly", width=12,
        )
        self.qa_difficulty_menu.pack(side="left", padx=(6, 0))

        # Same reasoning as the MCQ's tab's own checkbox: QA generation
        # almost always wants the fuller context (the node plus every
        # subnode beneath it) rather than just a bare name, so the AI has
        # real material to write questions from.
        self.qa_keep_children_var = tk.BooleanVar(value=True)
        self.qa_keep_children_check = tk.Checkbutton(
            qa_tab, text="Keep children nodes (don't strip -- give AI the full branch)",
            variable=self.qa_keep_children_var,
            command=self._sync_keep_children_flag,
        )
        self.qa_keep_children_check.pack(anchor="w", pady=(6, 0))

        tk.Label(qa_tab, text="QA instructions (topic to quiz on)"
                 ).pack(anchor="w", pady=(6, 0))
        self.qa_instr_text = scrolledtext.ScrolledText(qa_tab, height=6, wrap="word")
        self.qa_instr_text.pack(fill="both", expand=True)

        self.status_var = tk.StringVar(value="Idle")
        tk.Label(root, textvariable=self.status_var, fg="#555", wraplength=340,
                 justify="left").pack(anchor="w", padx=8, pady=(4, 0))

        # No manual "Ask AI -> Paste" button anymore -- every request now
        # comes in automatically via the AHK bridge (RButton + XButton2),
        # see _poll_bridge/_handle_bridge_request below. _busy replaces the
        # old "is the button disabled" check as the in-flight guard.
        self._busy = False

        # Each request started gets its own increasing id. When AHK signals
        # a cancel (XButton1 turned OFF), the in-flight id is recorded in
        # _cancelled_request_ids so that if its worker thread's network call
        # is still running in the background and eventually finishes anyway,
        # _on_success/_on_error can tell it's stale and discard it silently
        # instead of pasting a reply to a session that was already killed.
        self._request_seq = 0
        self._current_request_id = None
        self._cancelled_request_ids = set()

        self._sync_keep_children_flag()

        root.after(100, self._grab_own_hwnd)
        root.after(self.POLL_MS, self._poll_foreground)
        root.after(self.BRIDGE_POLL_MS, self._poll_bridge)
        root.after(self.BRIDGE_POLL_MS, self._poll_cancel)
        root.after(self.BRIDGE_POLL_MS, self._poll_exit)
        root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _on_close(self):
        # Just hide the window rather than destroying it: F11 in the AHK
        # script re-shows the SAME window (WinShow/WinActivate) rather than
        # relaunching this script, so the persistent Chromium session, the
        # Node/Note tab you left selected, and any typed instructions all
        # survive between F11 presses. The browser is only actually shut
        # down when this process really exits (see main()/mainloop ending).
        self.root.withdraw()

    def _grab_own_hwnd(self):
        # Tk's toplevel window id IS its real Win32 HWND.
        self._own_hwnd = self.root.winfo_id()

    def _poll_foreground(self):
        fg = get_foreground_hwnd()
        if fg and fg != self._own_hwnd:
            self.last_external_hwnd = fg
        self.root.after(self.POLL_MS, self._poll_foreground)

    def _set_status(self, text: str):
        self.status_var.set(text)

    def _get_active_page(self) -> str:
        # "Node" and "Note" come from the outer notebook; when the outer
        # tab is "Note", the inner note_subnotebook decides whether it's
        # really the Content page, or one of the nested MCQ's/True-False/
        # Fill-Blanks/QA pages. Returns one of "Node", "Note", "MCQ's",
        # "True/False", "Fill/Blanks", "QA" -- the same values used
        # throughout _handle_bridge_request/_start_ai_request/_on_success.
        top = self.notebook.tab(self.notebook.select(), "text")
        if top != "Note":
            return top
        sub = self.note_subnotebook.tab(self.note_subnotebook.select(), "text")
        if sub in ("MCQ's", "True/False", "Fill/Blanks", "QA"):
            return sub
        return "Note"

    def _sync_keep_children_flag(self):
        # Creates/deletes _BRIDGE_KEEP_CHILDREN so it always matches
        # "the active tab's own checkbox is checked AND that tab (MCQ's,
        # True/False, Fill/Blanks, or QA) is currently active", regardless
        # of whether it was a checkbox or the active tab that just
        # changed. Called from every one of those checkboxes' own
        # command=, from both notebooks' <<NotebookTabChanged>>, and once
        # at startup.
        active_page = self._get_active_page()
        if active_page == "MCQ's":
            want_on = bool(self.mcq_keep_children_var.get())
        elif active_page == "True/False":
            want_on = bool(self.tf_keep_children_var.get())
        elif active_page == "Fill/Blanks":
            want_on = bool(self.fb_keep_children_var.get())
        elif active_page == "QA":
            want_on = bool(self.qa_keep_children_var.get())
        else:
            want_on = False
        try:
            if want_on:
                os.makedirs(self._BRIDGE_DIR, exist_ok=True)
                with open(self._BRIDGE_KEEP_CHILDREN, "w") as f:
                    f.write("1")
            else:
                if os.path.isfile(self._BRIDGE_KEEP_CHILDREN):
                    os.remove(self._BRIDGE_KEEP_CHILDREN)
        except OSError:
            # Same spirit as the rest of the bridge I/O here -- a failed
            # write/remove shouldn't crash the GUI, just leave the flag
            # stale until the next sync gets a chance to retry.
            pass

    def _apply_note_preset(self, preset_text: str):
        # REPLACES the Note tab's Instructions box outright (not appended)
        # so clicking a different number swaps the preset cleanly rather
        # than piling text up. You can still edit the result by hand
        # before triggering a request.
        self.note_instr_text.delete("1.0", "end")
        self.note_instr_text.insert("1.0", preset_text)

    def _step_var_from_wheel(self, var: tk.IntVar, event, step: int, minimum: int):
        """Shared mouse-wheel step logic behind every tab's own count-
        spinbox scroll handler (MCQ's, True/False, Fill/Blanks, and QA
        all wire their own <MouseWheel>/<Button-4>/<Button-5> to a thin
        wrapper around this). Windows/Mac deliver a signed event.delta
        (Windows: +/-120 per notch); Linux/X11 has no delta at all -- it
        sends separate Button-4 (scroll up) / Button-5 (scroll down)
        events instead. Either way, one notch/click moves the value by
        `step`, clamped to not go below `minimum`."""
        if getattr(event, "num", None) == 4:
            delta = step
        elif getattr(event, "num", None) == 5:
            delta = -step
        else:
            delta = step if event.delta > 0 else -step
        try:
            current = var.get()
        except (tk.TclError, ValueError):
            current = minimum
        var.set(max(minimum, current + delta))
        return "break"

    def _on_mcq_count_scroll(self, event):
        return self._step_var_from_wheel(self.mcq_count_var, event, 10, 10)

    def _on_tf_count_scroll(self, event):
        return self._step_var_from_wheel(self.tf_count_var, event, 10, 10)

    def _on_fb_count_scroll(self, event):
        return self._step_var_from_wheel(self.fb_count_var, event, 10, 10)

    def _on_qa_count_scroll(self, event):
        # QA's own spinbox uses a smaller increment (5) than the other
        # three tabs' (10), so it gets its own step value here.
        return self._step_var_from_wheel(self.qa_count_var, event, 5, 5)

    def _build_lettered_options_row(self, parent: tk.Frame, on_click) -> dict:
        """Builds the same 10-button, 5-per-row grid of options-count
        buttons shared by the MCQ's, True/False, and Fill/Blanks tabs --
        button "1" maps to _MCQ_MIN_OPTIONS (4), button "2" to 5, and so
        on up through button "10" -> _MCQ_MAX_OPTIONS (13). The numbers
        on the buttons are just an index, same as the Note tab's preset
        buttons -- not the option/statement/fill count itself. Returns
        the {n_options: Button} dict the caller should stash (as e.g.
        self._mcq_option_buttons) for its own _select_*_options() method
        to keep highlighted."""
        OPTIONS_PER_ROW = 5
        row = tk.Frame(parent)
        row.pack(anchor="w", pady=(2, 2))
        buttons = {}
        span = _MCQ_MAX_OPTIONS - _MCQ_MIN_OPTIONS + 1
        for i in range(span):
            n_options = _MCQ_MIN_OPTIONS + i
            btn = tk.Button(
                row, text=str(i + 1), width=3,
                font=("Segoe UI", 10, "bold"),
                command=lambda n=n_options: on_click(n),
            )
            btn.grid(row=i // OPTIONS_PER_ROW, column=i % OPTIONS_PER_ROW,
                     padx=2, pady=2)
            btn.bind("<Enter>", lambda e, n=n_options: self._set_status(f"{n} options"))
            btn.bind("<Leave>", lambda e: self._set_status("Idle"))
            buttons[n_options] = btn
        return buttons

    def _select_lettered_options(self, num_options_var: tk.IntVar, buttons: dict, n_options: int):
        """Shared select/highlight logic behind the MCQ's, True/False and
        Fill/Blanks tabs' own _select_*_options() wrappers below."""
        num_options_var.set(n_options)
        for n, btn in buttons.items():
            if n == n_options:
                btn.config(relief="sunken", bg="#cde8ff")
            else:
                btn.config(relief="raised", bg="SystemButtonFace")

    def _select_mcq_options(self, n_options: int):
        self._select_lettered_options(self.mcq_num_options_var, self._mcq_option_buttons, n_options)

    def _select_tf_options(self, n_options: int):
        self._select_lettered_options(self.tf_num_options_var, self._tf_option_buttons, n_options)

    def _select_fb_options(self, n_options: int):
        self._select_lettered_options(self.fb_num_options_var, self._fb_option_buttons, n_options)

    def _recommend_options_text(self, difficulty: str) -> str:
        # Suggestion only -- see the comment above the MCQ's tab's own
        # difficulty combobox for why this no longer auto-selects a
        # button. Worded as a recommendation you can take or leave,
        # never as something that already happened.
        n = _difficulty_to_num_options(difficulty)
        return (f"Recommendation for {difficulty}: about {n} options "
                "(question difficulty and option count are independent "
                "though -- pick whichever count you actually want above).")

    def _on_mcq_difficulty_change(self, event=None):
        difficulty = self.mcq_difficulty_var.get() or _DEFAULT_DIFFICULTY
        self.mcq_recommend_var.set(self._recommend_options_text(difficulty))

    def _on_tf_difficulty_change(self, event=None):
        difficulty = self.tf_difficulty_var.get() or _DEFAULT_DIFFICULTY
        self.tf_recommend_var.set(self._recommend_options_text(difficulty))

    def _on_fb_difficulty_change(self, event=None):
        difficulty = self.fb_difficulty_var.get() or _DEFAULT_DIFFICULTY
        self.fb_recommend_var.set(self._recommend_options_text(difficulty))

    def _poll_bridge(self):
        # Looks for a request the AHK script (RButton held + XButton2)
        # dropped in the bridge folder. request.ready is only ever written
        # AFTER request.txt, so its presence alone means a full request is
        # waiting -- no partial reads are possible.
        try:
            if os.path.isfile(self._BRIDGE_FLAG):
                captured_text = ""
                try:
                    # "utf-8-sig" rather than "utf-8": AHK's FileAppend with
                    # the "UTF-8" encoding option writes a byte-order-mark
                    # (U+FEFF) at the start of the file every time, since the
                    # file is deleted and recreated on every request. Reading
                    # with plain "utf-8" leaves that BOM character sitting on
                    # the front of the captured text (invisible, but it was
                    # landing inside the AI prompt). "utf-8-sig" strips it if
                    # present and is a no-op otherwise.
                    with open(self._BRIDGE_REQUEST, "r", encoding="utf-8-sig") as f:
                        captured_text = f.read()
                except Exception:
                    captured_text = ""
                for path in (self._BRIDGE_FLAG, self._BRIDGE_REQUEST):
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                self._handle_bridge_request(captured_text)
        except Exception as e:
            # This ran under pythonw.exe -- there is NO console to print to,
            # so a swallowed exception here would be completely invisible
            # (bridge request silently dropped, nothing pasted, no clue why).
            # Surface it in the status line instead.
            self._set_status(f"Bridge request error: {e}")
        self.root.after(self.BRIDGE_POLL_MS, self._poll_bridge)

    def _poll_cancel(self):
        try:
            if os.path.isfile(self._BRIDGE_CANCEL):
                try:
                    os.remove(self._BRIDGE_CANCEL)
                except OSError:
                    pass
                self._handle_cancel_request()
        except Exception as e:
            self._set_status(f"Cancel-poll error: {e}")
        self.root.after(self.BRIDGE_POLL_MS, self._poll_cancel)

    def _poll_exit(self):
        try:
            if os.path.isfile(self._BRIDGE_EXIT):
                try:
                    os.remove(self._BRIDGE_EXIT)
                except OSError:
                    pass
                self._exit_app()
                return  # don't reschedule -- the process is on its way out
        except Exception:
            # No console under pythonw.exe -- if the check itself fails,
            # just keep polling rather than getting stuck.
            pass
        self.root.after(self.BRIDGE_POLL_MS, self._poll_exit)

    def _exit_app(self):
        # Unlike _on_close (which only withdraws the window so F11 can
        # bring the same session back), this really ends the process: it
        # tears down the Tk mainloop so main() returns and the interpreter
        # shuts down normally, which is what lets the atexit-registered
        # shutdown_browser() actually run and close the persistent
        # Chromium browser instead of leaving it orphaned.
        try:
            if os.path.isfile(self._BRIDGE_KEEP_CHILDREN):
                os.remove(self._BRIDGE_KEEP_CHILDREN)
        except OSError:
            pass
        try:
            if os.path.isfile(self._BRIDGE_BUSY):
                os.remove(self._BRIDGE_BUSY)
        except OSError:
            pass
        try:
            self.root.destroy()
        except Exception:
            pass

    def _handle_cancel_request(self):
        # XButton2 was just pressed with features OFF on the AHK side (it no
        # longer happens merely from XButton1 going OFF). Whatever request is (or
        # was) in flight is abandoned: mark its id as cancelled so a
        # still-running worker thread's eventual reply gets silently
        # discarded instead of pasted, and free up _busy right away so a
        # fresh request can start as soon as features come back ON.
        if self._current_request_id is not None:
            self._cancelled_request_ids.add(self._current_request_id)
        self._current_request_id = None
        if self._busy:
            self._busy = False
            set_toolbar_noactivate(self._own_hwnd, False)
            self._set_status("F11 session terminated (XButton2 while features OFF) -- nothing pasted.")

    def _handle_bridge_request(self, raw_text: str):
        # AHK now prefixes the payload with a "NODE" or "NOTE" header line
        # -- that's what PerformAISearch() actually captured (a node's own
        # name, with no note open; or the currently-open note's full
        # content), decided by AHK's own noteOpen state. This is NOT the
        # same thing as which tab (Node/Note) happens to be selected here,
        # and the two can disagree (e.g. you RM+XButton2 a plain node with
        # no note open while the Note tab is selected in this toolbar --
        # that's still a NODE capture). Routing on this tag instead of
        # guessing from the active tab is what fixes that mismatch.
        kind, _, captured_text = raw_text.partition("\n")
        kind = kind.strip()
        captured_text = captured_text.strip()
        if not captured_text:
            return
        if self._busy:
            # A request is already in flight -- drop this one rather than
            # stepping on it.
            return

        # The active tab still decides OUTPUT mode (which prompt gets
        # built) and which Instructions box to read -- it just no longer
        # decides what the captured text itself means.
        current_tab = self._get_active_page()
        if current_tab == "Node":
            instr_box = self.node_instr_text
        elif current_tab == "Note":
            instr_box = self.note_instr_text
        elif current_tab == "True/False":
            instr_box = self.tf_instr_text
        elif current_tab == "Fill/Blanks":
            instr_box = self.fb_instr_text
        elif current_tab == "QA":
            instr_box = self.qa_instr_text
        else:
            instr_box = self.mcq_instr_text

        if kind == "NODE":
            # A node's own name was captured. That's always the node name,
            # regardless of which tab is active -- the instructions
            # describing what to do with that node come from whichever
            # tab's own box you're looking at right now, never from the
            # capture itself.
            node_name = captured_text
            instructions = instr_box.get("1.0", "end").strip()
        else:
            # kind == "NOTE" (or an old/unrecognized payload from before
            # this tagging existed): the currently-open note's own content
            # was captured. Whatever you've typed into the active tab's
            # own Instructions box takes priority -- that's the box you
            # can see and edit, so it's what should drive the request.
            # Only if that box is EMPTY do we fall back to using the
            # note's own captured content as the instructions, in which
            # case we also echo it into the box so you can see what was
            # sent. There's no "Node name" field anymore to source a node
            # name from here, so it's simply left blank -- _start_ai_request
            # omits the "Node name:" line entirely when it's empty.
            node_name = ""
            manual_instructions = instr_box.get("1.0", "end").strip()
            if manual_instructions:
                instructions = manual_instructions
            else:
                instructions = captured_text
                instr_box.delete("1.0", "end")
                instr_box.insert("1.0", captured_text)

        self._start_ai_request(node_name, instructions, current_tab, self.last_external_hwnd)

    def _start_ai_request(self, node_name: str, instructions: str, current_tab: str, target_hwnd: int):
        if current_tab == "Node":
            size_tier = self.size_var.get() or _NODE_DEFAULT_SIZE_TIER
            format_instructions = _NODE_FORMAT_INSTRUCTIONS_BY_SIZE[size_tier]
            strip_central = bool(self.strip_central_var.get())
            # Node tab: the size-tier rules above (one of the 5 options --
            # Very Short/Short/Medium/Super/Ultra) are PRIORITY 1 and must
            # always be followed exactly. Whatever is typed into the Node
            # tab's Instructions box is PRIORITY 2 -- extra guidance about
            # the topic/scope to apply only where it doesn't conflict with
            # the size-tier's format, depth, and naming rules.
            priority_note = (
                "\n\n---\n\nPRIORITY NOTICE: Everything above this line (the "
                "size-tier rules) is your FIRST priority and must be "
                "followed exactly, with no exceptions. The \"Instructions\" "
                "line below is your SECOND priority -- extra guidance about "
                "the topic to apply only where it does not conflict with "
                "the rules above."
            )
        elif current_tab == "Note":
            size_tier = None
            format_instructions = _NOTE_FORMAT_INSTRUCTIONS
            strip_central = False
            # Note tab: no priority notice here -- ensure_h1_headers()/
            # build_note_html() force the heading format deterministically
            # in code regardless of what the AI does with the instructions,
            # so there's nothing left for a priority notice to arbitrate.
            priority_note = ""
        elif current_tab == "QA":
            # QA tab. count/difficulty come from its own spinbox and
            # dropdown -- same reasoning as the MCQ's tab below, the exact
            # layout is spelled out in full inside the builder so there's
            # nothing else competing with it to arbitrate.
            size_tier = None
            qa_count = self.qa_count_var.get() or 10
            qa_difficulty = self.qa_difficulty_var.get() or _DEFAULT_DIFFICULTY
            format_instructions = _build_qa_format_instructions(qa_count, qa_difficulty)
            strip_central = False
            priority_note = ""
        elif current_tab == "True/False":
            # True/False tab. count/num_options/difficulty come from its
            # own spinbox, numbered options-count button, and difficulty
            # dropdown -- same independence between difficulty and option
            # count as the MCQ's tab below (see _recommend_options_text).
            size_tier = None
            tf_count = self.tf_count_var.get() or 10
            tf_num_options = self.tf_num_options_var.get() or _MCQ_MIN_OPTIONS
            tf_difficulty = self.tf_difficulty_var.get() or _DEFAULT_DIFFICULTY
            format_instructions = _build_true_false_format_instructions(
                tf_count, tf_num_options, tf_difficulty
            )
            strip_central = False
            priority_note = ""
        elif current_tab == "Fill/Blanks":
            # Fill/Blanks tab. Same shape again -- own spinbox, numbered
            # options-count button, and difficulty dropdown.
            size_tier = None
            fb_count = self.fb_count_var.get() or 10
            fb_num_options = self.fb_num_options_var.get() or _MCQ_MIN_OPTIONS
            fb_difficulty = self.fb_difficulty_var.get() or _DEFAULT_DIFFICULTY
            format_instructions = _build_fill_blank_format_instructions(
                fb_count, fb_num_options, fb_difficulty
            )
            strip_central = False
            priority_note = ""
        else:
            # MCQ's tab (the fallback/default branch). count/num_options
            # come from the spinbox and the currently-selected numbered
            # options button -- difficulty (below) only affects question
            # wording, it does not drive num_options (see
            # _recommend_options_text for why). Both size_tier and
            # priority_note stay unused (None/"") same as the Note tab,
            # since the exact layout is spelled out in full below and
            # there's nothing else competing with it to arbitrate.
            size_tier = None
            mcq_count = self.mcq_count_var.get() or 10
            mcq_num_options = self.mcq_num_options_var.get() or _MCQ_MIN_OPTIONS
            mcq_difficulty = self.mcq_difficulty_var.get() or _DEFAULT_DIFFICULTY
            format_instructions = _build_mcq_format_instructions(
                mcq_count, mcq_num_options, mcq_difficulty
            )
            strip_central = False
            priority_note = ""

        # node_name is normally a single line (just the selected node's own
        # name). It's only ever multi-line when the MCQ's/True-False/Fill-
        # Blanks/QA tab's "Keep children nodes" checkbox sent the whole tab-indented branch
        # through (see XMindAI_BridgeKeepChildren on the AHK side) -- in
        # that case, present it as a labeled, indented bullet tree instead
        # of cramming several lines after "Node name:", so the AI can
        # actually read the hierarchy it's meant to quiz on. Without more,
        # the model tends to read the outline itself AS the subject and
        # writes questions about the tree shape (which node is the parent
        # of which, depth, siblings, etc.) instead of real quiz content --
        # the trailing note below heads that off explicitly.
        if "\n" in node_name.strip("\r\n"):
            node_section = (
                "Nodes Names:\n\n" + format_node_tree_as_bullets(node_name) +
                "\n\n(The list above is a topic outline showing what to "
                "cover -- it is NOT the subject of the quiz. Write real "
                "subject-matter questions about what each item actually "
                "is, using your own knowledge -- facts, properties, "
                "differences, uses, examples, and so on. Never ask about "
                "the outline itself: no questions about which item is the "
                "parent/child/sibling of another, root/leaf status, depth, "
                "or any other structural relationship in the list.)"
            )
        elif node_name.strip():
            node_section = f"Node name: {node_name}"
        else:
            # No node name at all -- happens for a NOTE capture now that
            # there's no "Node name" field to source one from. Just skip
            # that line rather than send "Node name: " with nothing after
            # the colon.
            node_section = ""
        prompt_parts = [format_instructions + priority_note]
        if node_section:
            prompt_parts.append(node_section)
        prompt_parts.append(f"Instructions: {instructions}")
        prompt = "\n\n".join(prompt_parts).strip()
        self._busy = True
        self._request_seq += 1
        request_id = self._request_seq
        self._current_request_id = request_id
        mode_label = f"{current_tab} mode, {size_tier} size" if size_tier else f"{current_tab} mode"
        if current_tab == "MCQ's":
            mode_label = f"{current_tab} mode ({mcq_count} Qs, {mcq_num_options} opts, {mcq_difficulty})"
        elif current_tab == "True/False":
            mode_label = f"{current_tab} mode ({tf_count} items, {tf_num_options} statements, {tf_difficulty})"
        elif current_tab == "Fill/Blanks":
            mode_label = f"{current_tab} mode ({fb_count} items, {fb_num_options} fills, {fb_difficulty})"
        elif current_tab == "QA":
            mode_label = f"{current_tab} mode ({qa_count} Qs, {qa_difficulty})"
        self._set_status(f"Asking AI ({mode_label})...")
        # Make the toolbar itself unable to steal foreground focus back from
        # XMind for the rest of this sequence -- see set_toolbar_noactivate.
        set_toolbar_noactivate(self._own_hwnd, True)

        def worker():
            try:
                reply = ask_deepseek(prompt)
                self.root.after(0, lambda: self._on_success(reply, request_id, current_tab, strip_central))
            except Exception as e:
                msg = str(e)
                self.root.after(0, lambda: self._on_error(msg, request_id))

        threading.Thread(target=worker, daemon=True).start()

    def _on_success(self, reply: str, request_id: int, mode: str, strip_central: bool):
        # A worker thread's network call can still be running after
        # XButton1 turned the whole thing off (or after a newer request
        # superseded it) -- when that's this id, discard it silently:
        # nothing gets pasted for a session that was already killed.
        if request_id != self._current_request_id or request_id in self._cancelled_request_ids:
            self._cancelled_request_ids.discard(request_id)
            return

        if mode == "Node" and strip_central:
            reply = strip_central_topic_line(reply)

        used_plain_fallback = False
        if mode in ("Note", "MCQ's", "True/False", "Fill/Blanks", "QA"):
            # Don't just trust the prompt -- build the real "<h1>" heading
            # ourselves, deterministically, and try to put it on the
            # clipboard as actual rich text (CF_HTML) so XMind renders a
            # real formatted heading rather than literal '#' characters.
            # Applied to MCQ's, True/False, Fill/Blanks, and QA the same
            # as Note: every non-blank line (question/statement/fill-
            # sentence, each lettered line, the "Answer:" line, the
            # "Reason:" line) becomes its own H1.
            plain_fallback = ensure_h1_headers(reply)
            html_fragment = build_note_html(reply)
            try:
                wrote_html = set_clipboard_html(html_fragment, plain_fallback)
            except Exception:
                wrote_html = False
            if not wrote_html:
                # Couldn't get real formatting onto the clipboard at all --
                # fall back to the markdown ("# ...") version via %TEMP%.
                used_plain_fallback = True
                set_clipboard_text(plain_fallback, self.root)
        else:
            set_clipboard_text(reply, self.root)

        # Re-write the SAME content once more right before handing off to
        # AHK for the actual paste. A DeepSeek query can take a while (up to
        # the 120s timeout), and during that whole window something else can
        # silently overwrite the clipboard -- most notably the AHK script's
        # own _BackgroundHeadingCheck timer, which runs every 20ms while TTS
        # is on and does `Clipboard := ""` + `Send ^c` with NO backup/
        # restore (see GetCurrentHeadingFast in the .ahk file). Writing our
        # content again right before signaling closes that race regardless
        # of what caused it.
        if mode in ("Note", "MCQ's", "True/False", "Fill/Blanks", "QA"):
            try:
                if not set_clipboard_html(html_fragment, plain_fallback):
                    set_clipboard_text(plain_fallback, self.root)
            except Exception:
                set_clipboard_text(plain_fallback, self.root)
        else:
            set_clipboard_text(reply, self.root)

        fallback_note = " (used plain '#' fallback, not a real heading)" if used_plain_fallback else ""

        # Hand the actual "bring XMind to front and press Ctrl+V" step off
        # to the AHK script instead of doing it from here. This process
        # trying to do it itself (SetForegroundWindow + a synthetic
        # SendInput Ctrl+V) was reliably copying the reply but never
        # visibly pasting it -- AHK already brings this exact XMind window
        # forward and sends it synthetic keystrokes successfully everywhere
        # else in that script, so it does this part too now.
        try:
            os.makedirs(self._BRIDGE_DIR, exist_ok=True)
            with open(self._BRIDGE_PASTE_READY, "w") as f:
                f.write("ready")
            self._set_status(f"Copied to clipboard{fallback_note} -- pasting into XMind...")
        except Exception as e:
            self._set_status(f"Copied to clipboard{fallback_note}, but couldn't signal AHK to paste ({e}) -- paste manually (Ctrl+V).")

        set_toolbar_noactivate(self._own_hwnd, False)
        self._busy = False

    def _on_error(self, message: str, request_id: int):
        if request_id != self._current_request_id or request_id in self._cancelled_request_ids:
            self._cancelled_request_ids.discard(request_id)
            return
        self._set_status("Error -- see popup.")
        set_toolbar_noactivate(self._own_hwnd, False)
        self._busy = False
        messagebox.showerror("AI query failed", message)


def main():
    print(f"[xmind_ai_note_assistant] profile folder: {_PROFILE_DIR}")
    has_data = os.path.isdir(_PROFILE_DIR) and len(os.listdir(_PROFILE_DIR)) > 0
    print(f"[xmind_ai_note_assistant] profile has data: {has_data} "
          f"({'looks logged in to something' if has_data else 'log in via --login or the other script first'})")
    if "--login" in sys.argv:
        run_login_setup(log=print)
        return
    # The window's own close button now just hides it (see
    # FloatingToolbar._on_close) so F11 in the AHK script can bring back
    # the SAME running session instead of relaunching this script. The
    # persistent Chromium browser is instead cleaned up here, whenever this
    # process actually exits (normal interpreter shutdown, Ctrl+C, a plain
    # `taskkill` without /F) -- a hard-killed process can still leave it
    # orphaned, same as before this change.
    atexit.register(shutdown_browser)
    root = tk.Tk()
    FloatingToolbar(root)
    root.mainloop()


if __name__ == "__main__":
    main()
