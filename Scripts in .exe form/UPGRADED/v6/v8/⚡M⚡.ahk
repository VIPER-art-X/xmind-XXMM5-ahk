; xmind_enhanced_balcon.ahk
; XMind-only mouse behavior — with normal mouse restored when XButton1 is OFF
; Enhanced with Balcon TTS integration - DUAL DETECTION SYSTEM
; NEW: Heading TTS System activated by Middle Mouse Button
; NEW: Hierarchical "then under" mode (Mode 4) for heading TTS
; NEW: Conversational mode (Mode 5) with natural speech variations
; NEW: F2 Number Suppression - prevents reading numbers in content while preserving F1 level announcements
; NEW: Hybrid TTS with nircmd audio routing for BOTH direct and file-based methods
; NEW: Loop Mode System (F3) - Persistent global loop for all TTS
; NEW: Mode 6 (5 key) - Hybrid loop mode with alternating speech patterns
; REMOVED: F4 Pause/Resume feature

#SingleInstance Force
#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
SetTitleMatchMode, 2

speedMultiplier := 1.0    
; 20,000 words would take about 27 minutes and 47 seconds at speed of 10 in balcon and 1.5 in speedMultiplier.
; ===========================================================
; CONFIGURATION SECTION - ORGANIZED INTO FOUR CATEGORIES
; ===========================================================

; ==================== SECTION 1: BASIC SETTINGS ====================
; These are the main settings you'll want to adjust for daily use


; ============================================
; SOUND PATHS - MUST be at the VERY TOP of script
; before any hotkeys, returns, or functions
; ============================================
SoundPath_On  := "F:\XMIND TTS SYSTEM\sounds\ON.wav"  ; xbutton1 ON
SoundPath_Off := "F:\XMIND TTS SYSTEM\sounds\OFF.wav"   ; xbutton1 OFF

; ============================================
; XMIND AI NOTE ASSISTANT INTEGRATION (F11 + RButton&XButton2)
; ============================================
; F11 launches/shows/hides the Python floating toolbar (Node/Note settings GUI).
; Holding RButton and pressing XButton2 sends the selected node (or the open
; note's content) to it for an AI "search" -- see PerformAISearch() below.
XMindAI_PythonPath := "pythonw.exe"                                      ; pythonw.exe -- set full path if it's not on PATH
XMindAI_ScriptPath := A_ScriptDir . "\xmind_ai_note_assistant.py"        ; Same folder as this .ahk file -- keep both files together
XMindAI_WinTitle   := "XMind AI Note Assistant"                          ; Must match the Python GUI's window title -- don't change one without the other

; Bridge files used to hand captured node/note text to the running Python
; process without disturbing its window (it polls for these in the background).
XMindAI_BridgeDir     := A_Temp . "\xmind_ai_bridge"
XMindAI_BridgeRequest := XMindAI_BridgeDir . "\request.txt"
XMindAI_BridgeFlag    := XMindAI_BridgeDir . "\request.ready"

; Reverse-direction flag: Python writes this the moment the AI reply is
; sitting on the clipboard, to ask AHK -- not Python -- to actually bring
; XMind to the foreground and press Ctrl+V. Python's own attempt to do that
; itself (SetForegroundWindow + a synthetic SendInput Ctrl+V) was copying
; the text fine but never visibly pasting it. AHK already brings this exact
; XMind window to the front and sends it synthetic keystrokes reliably
; elsewhere in this script (all the Ctrl+A/Ctrl+C capture routines above),
; so the actual paste keystroke is handed off here instead of trusting a
; second, separate process to do it.
XMindAI_BridgePasteReady := XMindAI_BridgeDir . "\paste.ready"

; Forward-direction cancel flag: written here by TerminateF11Session() --
; i.e. when XButton2 (Shift Scroll) is pressed while XButton1 features are
; OFF -- so Python abandons whatever AI request is in flight/queued and
; pastes nothing. (Merely turning XButton1 OFF no longer does this.)
XMindAI_BridgeCancel := XMindAI_BridgeDir . "\cancel.request"

; Reverse-direction flag: Python creates this the moment it starts working on
; an AI request and deletes it when that request finishes, errors, or is
; cancelled. Together with request.ready/request.txt/paste.ready it lets
; IsF11SessionOngoing() tell whether an F11 AI session is currently alive.
XMindAI_BridgeBusy := XMindAI_BridgeDir . "\busy.flag"

; Forward-direction flag: Python writes/deletes this file to tell AHK
; whether the active tab's own "Keep children nodes" checkbox (MCQ's or
; QA -- each has its own) is currently checked AND that tab is the active
; one. When present, PerformAISearch()'s
; NODE-search branch keeps the WHOLE captured branch (the node plus every
; subnode beneath it, still tab-indented) instead of trimming down to just
; the selected node's own first line -- see the keepChildren check inside
; PerformAISearch() below.
XMindAI_BridgeKeepChildren := XMindAI_BridgeDir . "\keep_children.flag"

; Shutdown flag: written by CleanupBeforeExit() when THIS script exits, so
; the Python AI assistant (which normally just hides its window and keeps
; running in the background -- see F11/_on_close) exits together with it
; instead of being left running. Python polls for this and does a clean
; interpreter shutdown itself (so its own atexit browser cleanup still
; runs) rather than being hard-killed from this side.
XMindAI_BridgeExit := XMindAI_BridgeDir . "\exit.request"

; PID of the launched pythonw.exe process (set by F11's Run call), used by
; CleanupBeforeExit() to confirm it actually exited, and to force-kill it
; as a last resort if it doesn't.
global XMindAI_PID := 0


; TTS Configuration - Controls text-to-speech behavior
balconPath := "F:\XMIND TTS SYSTEM\balcon\balcon.exe"  ; Path to Balcon executable
balconVoice := "Cortana"          ; Voice: "Cortana", "Microsoft David Desktop", "Microsoft Zira Desktop", "Microsoft Hazel Desktop"
balconSpeed := 5                  ; Speech speed: 0-10 (5=normal, lower=slower, higher=faster) [ in 8 minutes it can read 3060 words at speed of 7] ✅ Words per second = 6.375 wps  ✅ Words per hour = 22,950
balconPitch := 0                  ; Voice pitch: -10 to +10 (0=normal)
balconVolume := 100               ; Volume: 0-100 (100=maximum)

; === AUDIO ROUTING CONFIGURATION ===
CABLE_DEVICE := "CABLE Input"      ; Virtual cable device for TTS routing
REAL_DEVICE := "Headphones"        ; Your actual speakers/headphones
NIRCMD_PATH := "F:\XMIND TTS SYSTEM\nircmd\nircmd.exe"  ; Path to nircmd.exe

; === ULTIMATE MASSIVE CONTENT SYSTEM ===
; Handles 100K+ words by chunking into optimized file segments
chunkSizeChars := 50000           ; 50K chars ≈ 8,000-10,000 words per chunk
maxMemoryBuffer := 200000         ; 150K char threshold (~15K words) - triggers file mode
clipboardTimeoutMs := 10000       ; 10 sec timeout for massive clipboard operations
enableMassiveContentSystem := true  ; FORCE ENABLE for all large content

; In SECTION 1
forceHeadingFileMode := false      ; ALWAYS use file mode for headings





; === AUDIO LOCK FEATURE (F9) ===
audioLockEnabled := false      ; Default OFF - F9 toggles this
audioLockActive := false       ; Track if currently locked






maxTempFilesAllowed := 1000  ; Emergency: Stop if more than 3 temp .txt files exist

; Loop Gap Control - Adjust silence between loop iterations (milliseconds)
; Increase if you need longer gaps, decrease for faster restarts
loopGapMs := 150      ; 50ms = consistent tiny gap, 0 = instant restart, 500 = half second pause

maxContentLength := 150000  ; 150KB max before forcing file mode





; Mouse Gesture Sensitivity - Adjust these to change how gestures feel
gestureThreshold := 10            ; Mouse movement sensitivity: Lower = more sensitive (5-20)
gesturePollMs := 30               ; Ultra-fast gesture polling
clickMoveThreshold := 6           ; Max mouse movement to count as click (not drag): Lower = stricter (3-10)

; Zoom Controls - Adjust zoom behavior
zoomStepPercent := 5              ; Zoom percentage change per scroll step (2-10)
minZoomPercent := 10              ; Minimum zoom level allowed
maxZoomPercent := 500             ; Maximum zoom level allowed



; Controls how many heading levels to read (F6/F7)
maxHeadingLevels := 0               ; 0 = unlimited (default), 1+ = max levels to read



noteWordsPerLine := 0     ; Note words per line mode (0 = disabled, -1 to -10 = words per line)

; ==================== SPEED MULTIPLIER INFORMATION(THE VARIABLE IS AT THE TOP OF THE SCRIPT)====================
; Speed Multiplier - Simulates speeds beyond balcon's 0-10 limit; Default: normal speed

;Set speedMultiplierrrr to 1.5 in your config. This is the sweet spot:
;	Removes unnecessary pauses and filler words
;	Keeps all important content
;	Sounds natural, just faster
;	You can understand it easily on first listen
;
;When to Go Higher
;	2.0x: You've read the content before and just need a refresher
;	3.0x+: Only for scanning keywords in content you already know well
;
;When to Stay at 1.0
;	Learning complex new information
;	Technical material with precise language
;	You need to catch every detail

;| Multiplier | Text Removed | Text Remains | Effective Speed | Readability | What Gets Deleted                                                                   |
;| ---------- | ------------ | ------------ | --------------- | ----------- | ----------------------------------------------------------------------------------- |
;| **1.0x**   | 0%           | 100%         | **10x**         | Perfect     | Nothing (pure balcon)                                                               |
;| **1.5x**   | ~33%         | 67%          | **15x**         | Excellent   | Extra spaces, commas, semicolons                                                    |
;| **2.0x**   | ~50%         | 50%          | **20x**         | Very Good   | + Paragraph breaks, filler words (the, a, and, but)                                 |
;| **2.5x**   | ~60%         | 40%          | **25x**         | Good        | + More complex conjunctions                                                         |
;| **3.0x**   | **~67%**     | **33%**      | **30x**         | **Fair**    | **+ Prepositions (in, on, at), pronouns (it, we, they), auxiliary verbs (is, are)** |
;| **3.5x**   | ~71%         | 29%          | **35x**         | Fair        | + Short phrases, more aggressive filtering                                          |
;| **4.0x**   | ~75%         | 25%          | **40x**         | Moderate    | + All prepositions, most pronouns                                                   |
;| **4.5x**   | ~78%         | 22%          | **45x**         | Moderate    | + Short conjunctions, complex phrases                                               |
;| **5.0x**   | ~80%         | 20%          | **50x**         | Low         | + Heavy abbreviation ("for example" → "eg")                                         |
;| **5.5x**   | ~82%         | 18%          | **55x**         | Low         | + More abbreviations, less common words                                             |
;| **6.0x**   | ~85%         | 15%          | **60x**         | Poor        | + All 3-letter-or-less words                                                        |
;| **6.5x**   | ~87%         | 13%          | **65x**         | Poor        | + Aggressive short word removal                                                     |
;| **7.0x**   | ~88%         | 12%          | **70x**         | Very Poor   | + Internal vowels from long words ("project" → "prjct")                             |
;| **7.5x**   | ~90%         | 10%          | **75x**         | Very Poor   | + More vowel removal, compressed structure                                          |
;| **8.0x**   | ~91%         | 9%           | **80x**         | Barely      | + Extreme vowel removal, minimal grammar                                            |
;| **8.5x**   | ~92%         | 8%           | **85x**         | Barely      | + Almost all structure removed                                                      |
;| **9.0x**   | ~93%         | 7%           | **90x**         | Gibberish   | + Maximum compression, only keywords remain 

;| Multiplier | Time to Read    | Comprehension Level        |
;| ---------- | --------------- | -------------------------- |
;| **1.0x**   | 3 min 20 sec    | Full understanding         |
;| **2.0x**   | 1 min 40 sec    | Very good                  |
;| **3.0x**   | **1 min 7 sec** | **Fair (key points only)** |
;| **4.0x**   | 50 sec          | Moderate (outline only)    |
;| **5.0x**   | 40 sec          | Low (main ideas)           |
;| **6.0x**   | 33 sec          | Poor (key terms only)      |
;| **7.0x**   | 29 sec          | Very poor (scanning)       |
;| **8.0x**   | 25 sec          | Barely (keyword spotting)  |
;| **9.0x**   | 22 sec          | Gibberish (only sounds)    |
                                        |
;| Multiplier | Speed      | Comprehension | Best For                             |
;| ---------- | ---------- | ------------- | ------------------------------------ |
;| **1.0**    | **Normal** | **100%**      | Learning new material, dense content |
;| **1.5**    | 1.5x       | **95%**       | Standard speed-reading, comfortable  |
;| **2.0**    | 2x         | **85%**       | Familiar topics, review mode         |
;| **2.5**    | 2.5x       | **70%**       | Skimming, catching main points       |


; === F4/F5 SPEED CONTROL TOOLTIP COLORS ===
; Message: Speed Multiplier: X.x★ [CERULEAN BLUE + DARK BLUE BORDER]
SpeedControl_BG := "007BA7"
SpeedControl_TXT := "FFFFFF"
SpeedControl_BORDER := "000033"
SpeedControl_DURATION := 1800
SpeedControl_WIDTH := 205
SpeedControl_HEIGHT := 30
SpeedControl_ALIGN := "center"
SpeedControl_FONT_SIZE := 10
SpeedControl_FONT_BOLD := "true"


; ==================== SECTION 2: TOOLTIP MESSAGES ====================
; Customize all the messages that appear as tooltips

; Feature Status Messages
Message_FeaturesOn := "Features: ON"                 ; Shows when enabling features (XButton1)
Message_FeaturesOff := "Features: OFF"               ; Shows when disabling features (XButton1)

; TTS Status Messages  
Message_TTSStart := "▶ Reading Note TTS"            ; Shows when starting TTS (XButton2)
Message_TTSStop := "TTS Stopped"                     ; Shows when manually stopping TTS
Message_TTSFinished := "TTS Finished"                ; Shows when TTS completes naturally

; Heading TTS Messages
Message_HeadingTTSStart := "🌳 Reading heading structure" ; Shows when starting heading TTS (MButton)
Message_HeadingTTSStop := "Heading TTS Stopped"        ; Shows when stopping heading TTS
Message_HeadingTTSFinished := "Heading TTS finished"   ; Shows when heading TTS completes
Message_NoHeadingSelected := "No heading selected - click a topic first" ; Shows when no heading is selected

; Error Messages
Message_NoText := "No text to read"                  ; Shows when note is empty
Message_NoNoteOpen := "No note open - click a note first" ; Shows when no note is open
Message_NoteEmpty := "Note is empty - no text to read" ; Shows when note has no content
Message_NoteLoading := "Loading note content..."    ; Shows when reading large notes
Message_XButton2Disabled := "Heading TTS running - use MM Button to stop it"   ; Shows when u press xbutton2 while xbutton 1 is ON and heading tts is running

; Zoom Mode Messages
Message_ZoomOn := "Middle Zoom: ON"                  ; Shows when entering zoom mode
Message_ZoomOff := "Middle Zoom: OFF"                ; Shows when exiting zoom mode

; Script Control Messages
Message_ScriptPaused := "Script PAUSED"              ; Shows when pausing script (ScrollLock)
Message_ScriptResumed := "Script RESUMED"            ; Shows when resuming script (ScrollLock)

; TTS Lock Messages (FOR BOTH SYSTEMS)
Message_TTSLockOn := "TTS LOCK: ON (Both Systems)"   ; Shows when enabling TTS lock for both
Message_TTSLockOff := "TTS LOCK: OFF"                ; Shows when disabling TTS lock

; Dual Detection Toggle Messages
Message_DualDetectionOn := "Dual Detection: ON"      ; Shows when enabling dual detection
Message_DualDetectionOff := "Dual Detection: OFF"    ; Shows when disabling dual detection

; Analytical Mode Toggle Messages
Message_AnalyticalOn := "Analytical Mode: ON"        ; Shows when enabling analytical mode
Message_AnalyticalOff := "Analytical Mode: OFF"      ; Shows when disabling analytical mode

; Number Suppression Messages
Message_SuppressNumbersOn := "Number Suppression: ON"   ; Shows when enabling number suppression (F2)
Message_SuppressNumbersOff := "Number Suppression: OFF" ; Shows when disabling number suppression (F2)

; Loop Mode Messages
Message_LoopOn := "Loop Mode: ON"              ; Shows when enabling loop mode (F3)
Message_LoopOff := "Loop Mode: OFF"            ; Shows when disabling loop mode (F3)

; Level Announcement Messages
Message_LevelOn := "Level Announce: ON - Press 1/2/3/4/5 in 3 sec for mode (press 4/5 twice for Conversational)" ; Shows when enabling level announcement
Message_LevelOff := "Level Announce: OFF"            ; Shows when disabling level announcement
Message_ModeNumbers := "Mode: Level (lvl 1, lvl 2, lvl 3)"    ; Shows when number mode selected
Message_ModeDotted := "Mode: Dotted (1.1.1)"        ; Shows when dotted mode selected  
Message_ModeAlphabet := "Mode: Alphabet (a, b, c)"  ; Shows when alphabet mode selected
Message_ModeHierarchy := "Mode: Hierarchical (then under...)"  ; Shows when hierarchical mode selected
Message_ModeConversational := "Mode: Conversational (natural speech)"  ; Shows when conversational mode selected
Message_ModeHybridLoop := "Mode: Hybrid Loop (alternating patterns)" ; NEW: Shows when hybrid loop mode selected
Message_Countdown3 := "3..."                        ; Countdown messages
Message_Countdown2 := "2..."
Message_Countdown1 := "1..."
Message_DefaultSelected := "Default: Numbers (1, 2, 3, 4, 5)"
Message_ModeMinimal := "Mode: Numbers (1, 2, 3)"  ; NEW: For 1-key double press

; Balcon Speed Control Message
Message_Speed := "Balcon Speed: "          ; Base message for speed changes

; Shift Scroll Messages
Message_ShiftScrollOn := "Shift Scroll: ON"
Message_ShiftScrollOff := "Shift Scroll: OFF"
Message_F11SessionTerminated := "F11 ongoing session terminated"   ; Shows right after the Shift Scroll tooltip when XButton2 (features OFF) killed an in-flight F11 AI session


Message_MaxLevels := "Max Levels: " ; Tooltip message prefix

; Words/Line mode messages
Message_F6ModeWords := "Mode: Note words/line : "
Message_WordsPerLine := "Note words/line : "


; F7 GUI Messages
Message_F4F5Control := "F4/F5 controls level:"
Message_F4F5Tooltip := "Level "

; Transitioning Toggle Messages
Message_TransitioningOn := "Transitioning: ON"
Message_TransitioningOff := "Transitioning: OFF"

; ==================== SECTION 3: ADVANCED SETTINGS ====================
; These are technical settings - adjust only if you know what you're doing

; Timing and Performance Settings - INCREASED for 100k+ word content
selectionSleep := 15                ; Selection sleep: increased for large content stability
copySleep := 15                     ; Copy sleep: increased for large content stability
clipWaitTimeout := 5                ; Clipboard wait timeout (seconds): increased for 100k+ words

; Configuration - Ultra-fast base timing
baseCopyDelay := 0        ; 10ms = 0.01s for instant response
maxWaitTime := 5000        ; 5 second absolute maximum for massive maps
checkInterval := 5         ; Check every 5ms for progressive detection

; Note Detection Settings
noteOpenRetryAttempts := 7          ; 8 How many times to retry detecting note opening
noteOpenRetryDelay := 100            ; 100 Faster note detection    ;$LButton Up::

; TTS Limits
maxDirectTextLength := 3000         ; Use direct method for text under this length (characters)

; ==================== SECTION 4: HEADING TTS CONFIGURATION ====================
; Settings specific to the new heading TTS system

; Heading Reading Behavior
headingReadIndentLevels := true     ; Read indentation levels (e.g., "Main topic, Subtopic, Sub-subtopic")
headingIncludeEmptyNodes := false   ; Include empty nodes in reading
headingMaxDepth := 10               ; Maximum depth to read in the hierarchy
headingSpeechPauseMs := 150         ; Pause between headings in milliseconds

; ==================== SECTION 4b: ENHANCED LEVEL ANNOUNCEMENT CONFIGURATION ====================
; F1-controlled level announcement system with 6 modes

levelAnnounceEnabled := false       ; Default state - F1 toggles this
levelAnnounceMode := 1              ; 1 = Numbers, 2 = Dotted, 3 = Alphabet, 4 = Hierarchical, 5 = Conversational, 6 = Hybrid Loop
levelPrefix := "Level"              ; Customizable prefix word




; ==================== SECTION 4C: F6 TOGGLE MODE SYSTEM ====================
; F6 toggles between SpeedMultiplier and mmHeadings level Filter control
f6Mode := "level"  ; "level" = mmHeadings level Filter, "speed" = SpeedMultiplier (default: level)

; Mode switch messages
Message_F6ModeSpeed := "SpeedMultiplier"
Message_F6ModeLevel := "mmHeadings level Filter"
Message_F6ModeWords := "Note words/line : "
Message_MaxLevel := "Max level: "  ; For F4/F5 adjustments
Message_WordsPerLine := "Note words/line : "

; ===== Mode Switch Tooltip Styling =====
; SpeedMultiplier mode: Blue (matches old speed control)
F6ModeSpeed_BG := "007BA7"
F6ModeSpeed_TXT := "FFFFFF"
F6ModeSpeed_BORDER := "000033"
F6ModeSpeed_DURATION := 1500
F6ModeSpeed_WIDTH := 200
F6ModeSpeed_HEIGHT := 30
F6ModeSpeed_ALIGN := "center"
F6ModeSpeed_FONT_SIZE := 10
F6ModeSpeed_FONT_BOLD := "true"

; mmHeadings level Filter mode: Dark Green (matches old max levels)
F6ModeLevel_BG := "006400"
F6ModeLevel_TXT := "FFFFFF"
F6ModeLevel_BORDER := "002200"
F6ModeLevel_DURATION := 1500
F6ModeLevel_WIDTH := 225
F6ModeLevel_HEIGHT := 30
F6ModeLevel_ALIGN := "center"
F6ModeLevel_FONT_SIZE := 10
F6ModeLevel_FONT_BOLD := "true"


; ===== Max Levels Tooltip Styling =====
; Message: Max Levels: ALL [DARK GREEN + BLUE BORDER]
MaxLevelsOn_BG := "006400"
MaxLevelsOn_TXT := "FFFFFF"
MaxLevelsOn_BORDER := "000033"
MaxLevelsOn_DURATION := 1500
MaxLevelsOn_WIDTH := 120
MaxLevelsOn_HEIGHT := 30
MaxLevelsOn_ALIGN := "center"
MaxLevelsOn_FONT_SIZE := 10
MaxLevelsOn_FONT_BOLD := "true"


; ===== Words/Line Tooltip Styling =====
; Mode: Note words/line : [PURPLE + DARK PURPLE BORDER]
F6ModeWords_BG := "9932CC"
F6ModeWords_TXT := "FFFFFF"
F6ModeWords_BORDER := "220033"
F6ModeWords_DURATION := 1500
F6ModeWords_WIDTH := 155
F6ModeWords_HEIGHT := 30
F6ModeWords_ALIGN := "center"
F6ModeWords_FONT_SIZE := 10
F6ModeWords_FONT_BOLD := "true"

; Note words/line adjustment [DARK PURPLE + BLACK BORDER]
WordsPerLine_BG := "6A0DAD"
WordsPerLine_TXT := "FFFFFF"
WordsPerLine_BORDER := "2D013A"
WordsPerLine_DURATION := 1500
WordsPerLine_WIDTH := 155
WordsPerLine_HEIGHT := 30
WordsPerLine_ALIGN := "center"
WordsPerLine_FONT_SIZE := 10
WordsPerLine_FONT_BOLD := "true"


; ==================== SECTION 5: ADVANCED TOOLTIP STYLING CONFIGURATION ====================
; FULL CONTROL: Customize colors, borders, size, text alignment for every tooltip
; LEAVE ALL VALUES EMPTY ("" or 0) TO USE SIMPLE DEFAULT TOOLTIPS (backwards compatible)

; ===== Feature Status Tooltips =====
; Message: Features: ON [LIME GREEN + DARK GRAY BORDER]
FeaturesOn_BG := "00FF00"
FeaturesOn_TXT := "111111"
FeaturesOn_BORDER := "111111"
FeaturesOn_DURATION := 800
FeaturesOn_WIDTH := 105
FeaturesOn_HEIGHT := 25
FeaturesOn_ALIGN := "center"
FeaturesOn_FONT_SIZE := 10
FeaturesOn_FONT_BOLD := "true"

; Message: Features: OFF [CRIMSON RED + DARK RED BORDER]
FeaturesOff_BG := "DC143C"
FeaturesOff_TXT := "FFFFFF"
FeaturesOff_BORDER := "330000"
FeaturesOff_DURATION := 800
FeaturesOff_WIDTH := 115
FeaturesOff_HEIGHT := 25
FeaturesOff_ALIGN := "center"
FeaturesOff_FONT_SIZE := 10
FeaturesOff_FONT_BOLD := "true"

; ===== TTS Status Tooltips =====
; Message: ▶ Reading Note TTS [ROYAL BLUE + DARK BLUE BORDER]
TTSStart_BG := "4169E1"
TTSStart_TXT := "FFFFFF"
TTSStart_BORDER := "000033"
TTSStart_DURATION := 800
TTSStart_WIDTH := 120
TTSStart_HEIGHT := 25
TTSStart_ALIGN := "left"
TTSStart_FONT_SIZE := 9
TTSStart_FONT_BOLD := "false"

; Message: TTS Stopped [dull green + DARK MAGENTA BORDER]
TTSStop_BG := "0CE6CF"
TTSStop_TXT := "111111"
TTSStop_BORDER := "330033"
TTSStop_DURATION := 1000
TTSStop_WIDTH := 110
TTSStop_HEIGHT := 25
TTSStop_ALIGN := "left"
TTSStop_FONT_SIZE := 9
TTSStop_FONT_BOLD := "true"

; Message: TTS Finished [DEEP PURPLE + DARK PURPLE BORDER]
TTSFinished_BG := "9400D3"
TTSFinished_TXT := "000000"
TTSFinished_BORDER := "330033"
TTSFinished_DURATION := 1200
TTSFinished_WIDTH := 100
TTSFinished_HEIGHT := 25
TTSFinished_ALIGN := "left"
TTSFinished_FONT_SIZE := 9
TTSFinished_FONT_BOLD := "false"

; ===== Heading TTS Tooltips =====
; Message: Reading heading structure [TEAL + DARK TEAL BORDER]
HeadingTTSStart_BG := "008080"
HeadingTTSStart_TXT := "FFFFFF"
HeadingTTSStart_BORDER := "002222"
HeadingTTSStart_DURATION := 800
HeadingTTSStart_WIDTH := 170
HeadingTTSStart_HEIGHT := 25
HeadingTTSStart_ALIGN := "center"
HeadingTTSStart_FONT_SIZE := 9
HeadingTTSStart_FONT_BOLD := "false"

; Message: Heading TTS Stopped [MAGENTA + DARK MAGENTA BORDER]
HeadingTTSStop_BG := "FF00FF"
HeadingTTSStop_TXT := "111111"
HeadingTTSStop_BORDER := "330033"
HeadingTTSStop_DURATION := 1000
HeadingTTSStop_WIDTH := 200
HeadingTTSStop_HEIGHT := 25
HeadingTTSStop_ALIGN := "center"
HeadingTTSStop_FONT_BOLD := "true"

; Message: Heading TTS Finished [GOLD + DARK BROWN BORDER]
HeadingTTSFinished_BG := "FFD700"
HeadingTTSFinished_TXT := "111111"
HeadingTTSFinished_BORDER := "332211"
HeadingTTSFinished_DURATION := 1200
HeadingTTSFinished_WIDTH := 140
HeadingTTSFinished_HEIGHT := 25
HeadingTTSFinished_ALIGN := "center"
HeadingTTSFinished_FONT_BOLD := "false"

; Message: No heading selected - click a topic first [SLATE GRAY + DARK GRAY BORDER]
NoHeadingSelected_BG := "708090"
NoHeadingSelected_TXT := "FFFFFF"
NoHeadingSelected_BORDER := "111111"
NoHeadingSelected_DURATION := 1200
NoHeadingSelected_WIDTH := 260
NoHeadingSelected_HEIGHT := 25
NoHeadingSelected_ALIGN := "center"
NoHeadingSelected_FONT_SIZE := 9
NoHeadingSelected_FONT_BOLD := "false"

; ===== Error Tooltips =====

; Message: No note open - click a note first [BROWN + DARK BROWN BORDER]
NoNoteOpen_BG := "A52A2A"
NoNoteOpen_TXT := "000000"
NoNoteOpen_BORDER := "221100"
NoNoteOpen_DURATION := 1200
NoNoteOpen_WIDTH := 240
NoNoteOpen_HEIGHT := 25
NoNoteOpen_ALIGN := "center"
NoNoteOpen_FONT_SIZE := 9
NoNoteOpen_FONT_BOLD := "true"

; Message: Features OFF - press XButton1 first [KHAKI + DARK BROWN BORDER]
FeaturesDisabled_BG := "6F1493"
FeaturesDisabled_TXT := "000000"
FeaturesDisabled_BORDER := "332211"
FeaturesDisabled_DURATION := 1200
FeaturesDisabled_WIDTH := 240
FeaturesDisabled_HEIGHT := 25
FeaturesDisabled_ALIGN := "center"
FeaturesDisabled_FONT_SIZE := 9
FeaturesDisabled_FONT_BOLD := "true"

; Message: Note is empty - no text to read [SALMON + DARK RED BORDER]
NoteEmpty_BG := "0A8072"
NoteEmpty_TXT := "000000"
NoteEmpty_BORDER := "441122"
NoteEmpty_DURATION := 1200
NoteEmpty_WIDTH := 240
NoteEmpty_HEIGHT := 25
NoteEmpty_ALIGN := "center"
NoteEmpty_FONT_SIZE := 9
NoteEmpty_FONT_BOLD := "true"

; Message: Loading note content... [TURQUOISE + DARK CYAN BORDER]
NoteLoading_BG := "40E0D0"
NoteLoading_TXT := "000000"
NoteLoading_BORDER := "003333"
NoteLoading_DURATION := 0
NoteLoading_WIDTH := 200
NoteLoading_HEIGHT := 25
NoteLoading_ALIGN := "center"
NoteLoading_FONT_SIZE := 9
NoteLoading_FONT_BOLD := "false"


; Message: ❌ Heading TTS running - use Middle Mouse Button to stop [ORANGE + DARK BROWN BORDER]
XButton2Disabled_BG := "9C27B0"
XButton2Disabled_TXT := "000000"
XButton2Disabled_BORDER := "442200"
XButton2Disabled_DURATION := 1200
XButton2Disabled_WIDTH := 320
XButton2Disabled_HEIGHT := 25
XButton2Disabled_ALIGN := "center"
XButton2Disabled_FONT_SIZE := 9
XButton2Disabled_FONT_BOLD := "true"

; ===== Zoom Tooltips =====
; Message: Middle Zoom: ON [SPRING GREEN + DARK GREEN BORDER]
ZoomOn_BG := "00FF7F"
ZoomOn_TXT := "111111"
ZoomOn_BORDER := "003311"
ZoomOn_DURATION := 500
ZoomOn_WIDTH := 160
ZoomOn_HEIGHT := 38
ZoomOn_ALIGN := "center"
ZoomOn_FONT_SIZE := 9
ZoomOn_FONT_BOLD := "true"

; Message: Middle Zoom: OFF [DARK ORANGE + DARK BROWN BORDER]
ZoomOff_BG := "FF8C00"
ZoomOff_TXT := "111111"
ZoomOff_BORDER := "442200"
ZoomOff_DURATION := 500
ZoomOff_WIDTH := 105
ZoomOff_HEIGHT := 25
ZoomOff_ALIGN := "center"
ZoomOn_FONT_SIZE := 9
ZoomOn_FONT_BOLD := "false"

; ===== Script Control Tooltips =====
; Message: Script PAUSED [SILVER + DARK GRAY BORDER]
ScriptPaused_BG := "C0C0C0"
ScriptPaused_TXT := "000000"
ScriptPaused_BORDER := "111111"
ScriptPaused_DURATION := 800
ScriptPaused_WIDTH := 200
ScriptPaused_HEIGHT := 25
ScriptPaused_ALIGN := "center"
ScriptPaused_FONT_SIZE := 9
ScriptPaused_FONT_BOLD := "false"

; Message: Script RESUMED [INDIGO + DARK PURPLE BORDER]
ScriptResumed_BG := "4B0082"
ScriptResumed_TXT := "FFFFFF"
ScriptResumed_BORDER := "110022"
ScriptResumed_DURATION := 800
ScriptResumed_WIDTH := 200
ScriptResumed_HEIGHT := 25
ScriptResumed_ALIGN := "center"
ScriptResumed_FONT_SIZE := 9
ScriptResumed_FONT_BOLD := "false"

; ===== TTS Lock Tooltips =====
; Message: TTS LOCK: ON (Both Systems) [NAVY + DARK BLUE BORDER]
TTSLockOn_BG := "000080"
TTSLockOn_TXT := "FFFFFF"
TTSLockOn_BORDER := "000033"
TTSLockOn_DURATION := 1500
TTSLockOn_WIDTH := 240
TTSLockOn_HEIGHT := 25
TTSLockOn_ALIGN := "center"
TTSLockOn_FONT_SIZE := 9
TTSLockOn_FONT_BOLD := "false"

; Message: TTS LOCK: OFF [MAROON + DARK RED BORDER]
TTSLockOff_BG := "800000"
TTSLockOff_TXT := "FFFFFF"
TTSLockOff_BORDER := "220000"
TTSLockOff_DURATION := 1500
TTSLockOff_WIDTH := 180
TTSLockOff_HEIGHT := 25
TTSLockOff_ALIGN := "center"
TTSLockOff_FONT_SIZE := 9
TTSLockOff_FONT_BOLD := "false"

; ===== Unknown Tooltip =====

; Message: No text to read [DEEP PINK + DARK MAROON BORDER]
NoText_BG := "FF1493"
NoText_TXT := "FFFFFF"
NoText_BORDER := "331122"
NoText_DURATION := 1200
NoText_WIDTH := 180
NoText_HEIGHT := 25
NoText_ALIGN := "center"
NoText_FONT_SIZE := 9
NoText_FONT_BOLD := "false"

; ===== Dual Detection Tooltips =====
; Message: Dual Detection: ON [SKY BLUE + DARK BLUE BORDER]
DualDetectionOn_BG := "87CEEB"
DualDetectionOn_TXT := "111111"
DualDetectionOn_BORDER := "112233"
DualDetectionOn_DURATION := 1500
DualDetectionOn_WIDTH := 220
DualDetectionOn_HEIGHT := 25
DualDetectionOn_ALIGN := "center"
DualDetectionOn_FONT_SIZE := 9
DualDetectionOn_FONT_BOLD := "true"

; Message: Dual Detection: OFF [DIM GRAY + DARK GRAY BORDER]
DualDetectionOff_BG := "696969"
DualDetectionOff_TXT := "FFFFFF"
DualDetectionOff_BORDER := "111111"
DualDetectionOff_DURATION := 1500
DualDetectionOff_WIDTH := 220
DualDetectionOff_HEIGHT := 25
DualDetectionOff_ALIGN := "center"
DualDetectionOff_FONT_SIZE := 9
DualDetectionOff_FONT_BOLD := "false"

; ===== Analytical Mode Tooltips =====
; Message: Analytical Mode: ON [VIOLET + DARK PURPLE BORDER]
AnalyticalOn_BG := "EE82EE"
AnalyticalOn_TXT := "111111"
AnalyticalOn_BORDER := "221133"
AnalyticalOn_DURATION := 1500
AnalyticalOn_WIDTH := 220
AnalyticalOn_HEIGHT := 25
AnalyticalOn_ALIGN := "center"
AnalyticalOn_FONT_SIZE := 9
AnalyticalOn_FONT_BOLD := "true"

; Message: Analytical Mode: OFF [TOMATO + DARK RED BORDER]
AnalyticalOff_BG := "FF6347"
AnalyticalOff_TXT := "000000"
AnalyticalOff_BORDER := "441100"
AnalyticalOff_DURATION := 1500
AnalyticalOff_WIDTH := 220
AnalyticalOff_HEIGHT := 25
AnalyticalOff_ALIGN := "center"
AnalyticalOn_FONT_SIZE := 9
AnalyticalOn_FONT_BOLD := "false"

; ===== Number Suppression Tooltips =====
; Message: Number Suppression: ON [KHAKI + DARK BROWN BORDER]
SuppressNumbersOn_BG := "F0E68C"
SuppressNumbersOn_TXT := "111111"
SuppressNumbersOn_BORDER := "332211"
SuppressNumbersOn_DURATION := 1500
SuppressNumbersOn_WIDTH := 220
SuppressNumbersOn_HEIGHT := 25
SuppressNumbersOn_ALIGN := "center"
SuppressNumbersOn_FONT_SIZE := 9
SuppressNumbersOn_FONT_BOLD := "true"

; Message: Number Suppression: OFF [CHOCOLATE + DARK BROWN BORDER]
SuppressNumbersOff_BG := "D2691E"
SuppressNumbersOff_TXT := "FFFFFF"
SuppressNumbersOff_BORDER := "221100"
SuppressNumbersOff_DURATION := 1500
SuppressNumbersOff_WIDTH := 220
SuppressNumbersOff_HEIGHT := 25
SuppressNumbersOff_ALIGN := "center"
SuppressNumbersOff_FONT_SIZE := 9
SuppressNumbersOff_FONT_BOLD := "true"

; ===== Level Announcement Tooltips =====
; Message: Level Announce: ON - Press 1/2/3/4/5 in 3 sec for mode (press 4/5 twice for Conversational) [DARK CYAN + DARK CYAN BORDER]
LevelOn_BG := "008B8B"
LevelOn_TXT := "111111"
LevelOn_BORDER := "002222"
LevelOn_DURATION := 1500
LevelOn_WIDTH := 420
LevelOn_HEIGHT := 36
LevelOn_ALIGN := "center"
LevelOn_FONT_SIZE := 9
LevelOn_FONT_BOLD := "true"

; Message: Level Announce: OFF [OLIVE + DARK OLIVE BORDER]
LevelOff_BG := "808000"
LevelOff_TXT := "FFFFFF"
LevelOff_BORDER := "222200"
LevelOff_DURATION := 1500
LevelOff_WIDTH := 180
LevelOff_HEIGHT := 25
LevelOff_ALIGN := "center"
LevelOff_FONT_SIZE := 10
LevelOff_FONT_BOLD := "true"

; Message: Mode: Numbers (1, 2, 3) [ORCHID + DARK PURPLE BORDER]
ModeNumbers_BG := "DA70D6"
ModeNumbers_TXT := "000000"
ModeNumbers_BORDER := "331144"
ModeNumbers_DURATION := 1500
ModeNumbers_WIDTH := 220
ModeNumbers_HEIGHT := 25
ModeNumbers_ALIGN := "center"
ModeNumbers_FONT_SIZE := 9
ModeNumbers_FONT_BOLD := "false"

; Message: Mode: Minimal (N: heading) [DARK ORANGE + DARK RED BORDER]
ModeMinimal_BG := "FF6600"
ModeMinimal_TXT := "FFFFFF"
ModeMinimal_BORDER := "330000"
ModeMinimal_DURATION := 1500
ModeMinimal_WIDTH := 220
ModeMinimal_HEIGHT := 25
ModeMinimal_ALIGN := "center"
ModeMinimal_FONT_SIZE := 9
ModeMinimal_FONT_BOLD := "true"

; Message: Mode: Dotted (1.1.1) [SIENNA + DARK BROWN BORDER]
ModeDotted_BG := "A0522D"
ModeDotted_TXT := "FFFFFF"
ModeDotted_BORDER := "221100"
ModeDotted_DURATION := 1500
ModeDotted_WIDTH := 220
ModeDotted_HEIGHT := 25
ModeDotted_ALIGN := "center"
ModeDotted_FONT_SIZE := 9
ModeDotted_FONT_BOLD := "false"

; Message: Mode: Alphabet (a, b, c) [CHARTREUSE + DARK GREEN BORDER]
ModeAlphabet_BG := "7FFF00"
ModeAlphabet_TXT := "000000"
ModeAlphabet_BORDER := "223300"
ModeAlphabet_DURATION := 1500
ModeAlphabet_WIDTH := 220
ModeAlphabet_HEIGHT := 25
ModeAlphabet_ALIGN := "center"
ModeAlphabet_FONT_SIZE := 9
ModeAlphabet_FONT_BOLD := "false"

; 4-Key Single Press: Hierarchical Mode (Blue) [CORNFLOWER BLUE + DARK BLUE BORDER]
ModeHierarchy_BG := "6495ED"
ModeHierarchy_TXT := "111111"
ModeHierarchy_BORDER := "001144"
ModeHierarchy_DURATION := 1500
ModeHierarchy_WIDTH := 260
ModeHierarchy_HEIGHT := 25
ModeHierarchy_ALIGN := "center"
ModeHierarchy_FONT_SIZE := 9
ModeHierarchy_FONT_BOLD := "true"

; 4-Key Double Press: Conversational Mode (Cyan) [AQUAMARINE + DARK CYAN BORDER]
ModeConversational_BG := "7FFFD4"
ModeConversational_TXT := "111111"
ModeConversational_BORDER := "003333"
ModeConversational_DURATION := 1500
ModeConversational_WIDTH := 280
ModeConversational_HEIGHT := 25
ModeConversational_ALIGN := "center"
ModeConversational_FONT_SIZE := 9
ModeConversational_FONT_BOLD := "true"

; 5-Key Single Press: Hierarchical Mode (Purple Alternative) [MEDIUM SEA GREEN + DARK GREEN BORDER]
ModeHierarchyAlt_BG := "3CB371"
ModeHierarchyAlt_TXT := "111111"
ModeHierarchyAlt_BORDER := "002211"
ModeHierarchyAlt_DURATION := 1500
ModeHierarchyAlt_WIDTH := 260
ModeHierarchyAlt_HEIGHT := 25
ModeHierarchyAlt_ALIGN := "center"
ModeHierarchyAlt_FONT_SIZE := 9
ModeHierarchyAlt_FONT_BOLD := "true"

; 5-Key Double Press: Hybrid Loop Mode (Magenta) [DARK ORCHID + DARK PURPLE BORDER]
ModeHybridLoop_BG := "9932CC"
ModeHybridLoop_TXT := "111111"
ModeHybridLoop_BORDER := "220033"
ModeHybridLoop_DURATION := 1500
ModeHybridLoop_WIDTH := 320
ModeHybridLoop_HEIGHT := 25
ModeHybridLoop_ALIGN := "center"
ModeHybridLoop_FONT_SIZE := 9
ModeHybridLoop_FONT_BOLD := "true"

; Message: 3... [GOLD + DARK BROWN BORDER]
Countdown3_BG := "FFD700"
Countdown3_TXT := "111111"
Countdown3_BORDER := "332211"
Countdown3_DURATION := 1000
Countdown3_WIDTH := 80
Countdown3_HEIGHT := 30
Countdown3_ALIGN := "center"
Countdown3_FONT_SIZE := 12
Countdown3_FONT_BOLD := "true"

; Message: 2... [GOLD + DARK BROWN BORDER]
Countdown2_BG := "FFD700"
Countdown2_TXT := "111111"
Countdown2_BORDER := "332211"
Countdown2_DURATION := 1000
Countdown2_WIDTH := 80
Countdown2_HEIGHT := 30
Countdown2_ALIGN := "center"
Countdown2_FONT_SIZE := 12
Countdown2_FONT_BOLD := "true"

; Message: 1... [GOLD + DARK BROWN BORDER]
Countdown1_BG := "FFD700"
Countdown1_TXT := "111111"
Countdown1_BORDER := "332211"
Countdown1_DURATION := 1000
Countdown1_WIDTH := 80
Countdown1_HEIGHT := 30
Countdown1_ALIGN := "center"
Countdown1_FONT_SIZE := 12
Countdown1_FONT_BOLD := "true"

; Message: Default: Numbers (1, 2, 3, 4, 5) [STEEL BLUE + DARK SLATE BORDER]
DefaultSelected_BG := "4682B4"
DefaultSelected_TXT := "FFFFFF"
DefaultSelected_BORDER := "2F4F4F"
DefaultSelected_DURATION := 1500
DefaultSelected_WIDTH := 260
DefaultSelected_HEIGHT := 25
DefaultSelected_ALIGN := "center"
DefaultSelected_FONT_SIZE := 9
DefaultSelected_FONT_BOLD := "false"

; ===== Debug/Analytical Tooltips (Internal) =====
; Message: (Debug messages) [DARK SLATE GRAY + VERY DARK GRAY BORDER]
Debug_BG := "2F4F4F"
Debug_TXT := "FFFF00"
Debug_BORDER := "1C1C1C"
Debug_DURATION := 800
Debug_WIDTH := 240
Debug_HEIGHT := 25
Debug_ALIGN := "left"
Debug_FONT_SIZE := 8
Debug_FONT_BOLD := "false"

; ===== Loop Mode Tooltips =====
; Message: Loop Mode: ON [MEDIUM SPRING GREEN + DARK GREEN BORDER]
LoopOn_BG := "00FA9A"
LoopOn_TXT := "111111"
LoopOn_BORDER := "003311"
LoopOn_DURATION := 1500
LoopOn_WIDTH := 200
LoopOn_HEIGHT := 25
LoopOn_ALIGN := "center"
LoopOn_FONT_SIZE := 9
LoopOn_FONT_BOLD := "false"

; Message: Loop Mode: OFF [FIRE BRICK + DARK RED BORDER]
LoopOff_BG := "B22222"
LoopOff_TXT := "FFFFFF"
LoopOff_BORDER := "220000"
LoopOff_DURATION := 1500
LoopOn_WIDTH := 200
LoopOn_HEIGHT := 25
LoopOn_ALIGN := "center"
LoopOn_FONT_BOLD := "false"

; ===== NEW: Loop Notification Tooltips (for looping messages) =====
; Message: Looping note/heading TTS... [DARK SLATE BLUE + DARK SLATE BORDER]
LoopNotification_BG := "483D8B"
LoopNotification_TXT := "00FFFF"
LoopNotification_BORDER := "2F2F4F"
LoopNotification_DURATION := 800
LoopNotification_WIDTH := 220
LoopNotification_HEIGHT := 25
LoopNotification_ALIGN := "center"
LoopNotification_FONT_SIZE := 9
LoopNotification_FONT_BOLD := "true"


; ===== Balcon Speed Control Tooltips (Orange theme) =====
VoiceSpeed_BG := "FF6600"
VoiceSpeed_TXT := "FFFFFF"
VoiceSpeed_BORDER := "331100"
VoiceSpeed_DURATION := 1200
VoiceSpeed_WIDTH := 145     ; Base width for normal speeds 2-9
VoiceSpeed_HEIGHT := 25
VoiceSpeed_ALIGN := "center"
VoiceSpeed_FONT_SIZE := 10
VoiceSpeed_FONT_BOLD := "true"

; ===== Shift Scroll Tooltips (Unique Identity) =====
; Message: Shift Scroll: ON [CYAN BLUE + DARK BLUE BORDER]
ShiftScrollOn_BG := "00AAFF"
ShiftScrollOn_TXT := "111111"
ShiftScrollOn_BORDER := "003366"
ShiftScrollOn_DURATION := 1000
ShiftScrollOn_WIDTH := 160
ShiftScrollOn_HEIGHT := 25
ShiftScrollOn_ALIGN := "center"
ShiftScrollOn_FONT_SIZE := 9
ShiftScrollOn_FONT_BOLD := "true"

; Message: Shift Scroll: OFF [BRIGHT RED + DARK RED BORDER]
ShiftScrollOff_BG := "FF4444"
ShiftScrollOff_TXT := "FFFFFF"
ShiftScrollOff_BORDER := "660000"
ShiftScrollOff_DURATION := 800
ShiftScrollOff_WIDTH := 160
ShiftScrollOff_HEIGHT := 25
ShiftScrollOff_ALIGN := "center"
ShiftScrollOff_FONT_SIZE := 9
ShiftScrollOff_FONT_BOLD := "true"


; ===== Audio Lock Tooltips =====
; Message: Audio Lock: ON (CABLE) [DARK BLUE + GOLD BORDER]
AudioLockOn_BG := "00008B"
AudioLockOn_TXT := "FFFFFF"
AudioLockOn_BORDER := "FFD700"
AudioLockOn_DURATION := 1500
AudioLockOn_WIDTH := 200
AudioLockOn_HEIGHT := 25
AudioLockOn_ALIGN := "center"
AudioLockOn_FONT_SIZE := 9
AudioLockOn_FONT_BOLD := "true"

; Message: Audio Lock: OFF (Auto) [GRAY + DARK GRAY BORDER]
AudioLockOff_BG := "808080"
AudioLockOff_TXT := "FFFFFF"
AudioLockOff_BORDER := "333333"
AudioLockOff_DURATION := 1500
AudioLockOff_WIDTH := 200
AudioLockOff_HEIGHT := 25
AudioLockOff_ALIGN := "center"
AudioLockOff_FONT_SIZE := 9
AudioLockOff_FONT_BOLD := "true"

; ===== Transitioning Toggle Tooltips =====
; Message: Transitioning: ON [TEAL + DARK TEAL BORDER]
TransitioningOn_BG := "008080"
TransitioningOn_TXT := "FFFFFF"
TransitioningOn_BORDER := "002222"
TransitioningOn_DURATION := 1500
TransitioningOn_WIDTH := 200
TransitioningOn_HEIGHT := 25
TransitioningOn_ALIGN := "center"
TransitioningOn_FONT_SIZE := 9
TransitioningOn_FONT_BOLD := "true"

; Message: Transitioning: OFF [DARK ORANGE + DARK BROWN BORDER]
TransitioningOff_BG := "FF8C00"
TransitioningOff_TXT := "111111"
TransitioningOff_BORDER := "442200"
TransitioningOff_DURATION := 1500
TransitioningOff_WIDTH := 200
TransitioningOff_HEIGHT := 25
TransitioningOff_ALIGN := "center"
TransitioningOff_FONT_SIZE := 9
TransitioningOff_FONT_BOLD := "true"

; ===== XMind AI Note Assistant Tooltips (F11 + RButton & XButton2) =====
; Message: Launching AI Note Assistant... [DODGER BLUE + DARK NAVY BORDER]
AILaunch_BG := "1E90FF"
AILaunch_TXT := "FFFFFF"
AILaunch_BORDER := "0A2A55"
AILaunch_DURATION := 1200
AILaunch_WIDTH := 260
AILaunch_HEIGHT := 26
AILaunch_ALIGN := "center"
AILaunch_FONT_SIZE := 9
AILaunch_FONT_BOLD := "true"

; Message: AI Assistant settings (shown/activated) [DEEP SKY BLUE + DARK NAVY BORDER]
AIShow_BG := "00BFFF"
AIShow_TXT := "111111"
AIShow_BORDER := "003355"
AIShow_DURATION := 800
AIShow_WIDTH := 240
AIShow_HEIGHT := 25
AIShow_ALIGN := "center"
AIShow_FONT_SIZE := 9
AIShow_FONT_BOLD := "true"

; Message: AI Assistant hidden — F11 to reopen [STEEL BLUE + DARK SLATE BORDER]
AIHide_BG := "4682B4"
AIHide_TXT := "FFFFFF"
AIHide_BORDER := "1B2A38"
AIHide_DURATION := 900
AIHide_WIDTH := 280
AIHide_HEIGHT := 25
AIHide_ALIGN := "center"
AIHide_FONT_SIZE := 9
AIHide_FONT_BOLD := "false"

; Message: Node sent to AI Assistant [LIME GREEN + DARK GREEN BORDER]
NodeSearchSent_BG := "32CD32"
NodeSearchSent_TXT := "111111"
NodeSearchSent_BORDER := "0B330B"
NodeSearchSent_DURATION := 1000
NodeSearchSent_WIDTH := 260
NodeSearchSent_HEIGHT := 25
NodeSearchSent_ALIGN := "center"
NodeSearchSent_FONT_SIZE := 9
NodeSearchSent_FONT_BOLD := "true"

; Message: Note sent to AI Assistant [SEA GREEN + DARK GREEN BORDER]
NoteSearchSent_BG := "3CB371"
NoteSearchSent_TXT := "FFFFFF"
NoteSearchSent_BORDER := "0B3320"
NoteSearchSent_DURATION := 1000
NoteSearchSent_WIDTH := 260
NoteSearchSent_HEIGHT := 25
NoteSearchSent_ALIGN := "center"
NoteSearchSent_FONT_SIZE := 9
NoteSearchSent_FONT_BOLD := "true"

; Message: No node selected for search [FIREBRICK + DARK RED BORDER]
NoNodeSearch_BG := "B22222"
NoNodeSearch_TXT := "FFFFFF"
NoNodeSearch_BORDER := "330000"
NoNodeSearch_DURATION := 1500
NoNodeSearch_WIDTH := 280
NoNodeSearch_HEIGHT := 25
NoNodeSearch_ALIGN := "center"
NoNodeSearch_FONT_SIZE := 9
NoNodeSearch_FONT_BOLD := "true"

; Message: Note is empty, nothing to search [DARK RED + DARK RED BORDER]
NoNoteSearch_BG := "8B0000"
NoNoteSearch_TXT := "FFFFFF"
NoNoteSearch_BORDER := "220000"
NoNoteSearch_DURATION := 1500
NoNoteSearch_WIDTH := 280
NoNoteSearch_HEIGHT := 25
NoNoteSearch_ALIGN := "center"
NoNoteSearch_FONT_SIZE := 9
NoNoteSearch_FONT_BOLD := "true"

; Message: AI Assistant isn't running / never appeared [CRIMSON + DARK RED BORDER]
AINotRunning_BG := "DC143C"
AINotRunning_TXT := "FFFFFF"
AINotRunning_BORDER := "330000"
AINotRunning_DURATION := 2500
AINotRunning_WIDTH := 360
AINotRunning_HEIGHT := 40
AINotRunning_ALIGN := "center"
AINotRunning_FONT_SIZE := 9
AINotRunning_FONT_BOLD := "true"

; Message: F11 ongoing session terminated [ORANGE + DARK BROWN BORDER]
F11Terminated_BG := "FF8C00"
F11Terminated_TXT := "111111"
F11Terminated_BORDER := "3D2200"
F11Terminated_DURATION := 1500
F11Terminated_WIDTH := 250
F11Terminated_HEIGHT := 25
F11Terminated_ALIGN := "center"
F11Terminated_FONT_SIZE := 9
F11Terminated_FONT_BOLD := "true"

; ==================== END CONFIGURATION ====================


; Heading Filter GUI Messages
Message_HeadingFilterGUI := "Heading Level Filter Config"
Message_ResetInputs := "Reset Input Values"
Message_CompressGUI := "─"
Message_ExpandGUI := "▢"
Message_AddLevel := "+"





; ===========================================================
; VALIDATION ON STARTUP - AUDIO TOOLS CHECK
; ===========================================================
; PURPOSE: Verify required audio tools exist before script runs
; STRATEGY: Check file paths for balcon.exe and nircmd.exe
; BENEFITS: Prevents script errors with clear error messages

ValidateAudioTools() {
    global balconPath, NIRCMD_PATH
    
    if (!FileExist(balconPath)) {
        MsgBox, 16, CRITICAL ERROR, Balcon not found at: %balconPath%
        return false
    }
    
    if (!FileExist(NIRCMD_PATH)) {
        MsgBox, 16, CRITICAL ERROR, nircmd.exe not found at: %NIRCMD_PATH%`n`nDownload from: https://www.nirsoft.net/utils/nircmd.html  
        return false
    }
    
    return true
}

; Run validation immediately on startup
if (!ValidateAudioTools())
    ExitApp

; ===========================================================
; SMART TOOLTIP SYSTEM - BACKWARDS COMPATIBLE
; ===========================================================
; PURPOSE: Show tooltips with full customization or fallback to simple defaults
; USAGE: ShowSmartTooltip(message, type, duration := -1)
;        duration = -1 uses configured duration, 0 = permanent, >0 = custom ms
; FEATURES: Custom colors, borders, fonts, alignment, auto-positioning
; STRATEGY: Check for type-specific styling variables, fallback to simple ToolTip if none found

global currentTooltipGui := 0
global tooltipTimerActive := false

ShowSmartTooltip(message, type := "", duration := -1) {
    global currentTooltipGui, tooltipTimerActive
    
    ; Hide any existing tooltip first to prevent stacking
    HideSmartTooltip()
    
    ; If type is provided, check for custom styling configuration
    if (type != "") {
        hasCustom := false
        
        ; Check if any custom parameters are defined for this type
        bgColor := type . "_BG"
        txtColor := type . "_TXT"
        borderColor := type . "_BORDER"
        dur := type . "_DURATION"
        width := type . "_WIDTH"
        height := type . "_HEIGHT"
        align := type . "_ALIGN"
        fontSize := type . "_FONT_SIZE"
        fontBold := type . "_FONT_BOLD"
        
        ; Evaluate the variables to get their values
        bgVal := %bgColor%
        txtVal := %txtColor%
        borderVal := %borderColor%
        durVal := %dur%
        widthVal := %width%
        heightVal := %height%
        alignVal := %align%
        fontSizeVal := %fontSize%
        fontBoldVal := %fontBold%
        
        ; Check if any customization is active
        if (bgVal != "" || txtVal != "" || borderVal != "" || widthVal > 0 || heightVal > 0 || fontSizeVal > 0) {
            hasCustom := true
        }
    }
    
    ; Use duration from config if not specified
    if (duration = -1 && type != "") {
        duration := durVal
    } else if (duration = -1) {
        duration := 1200  ; Default duration
    }
    
    ; If no custom styling or type is "Simple", use original tooltip
    if (!hasCustom || type = "" || type = "Simple") {
        ToolTip, %message%
        if (duration > 0) {
            SetTimer, HideSmartTooltip, -%duration%
        }
        return
    }
    
    ; Create enhanced GUI tooltip with custom styling
    currentTooltipGui++
    
    ; Default values if not specified in configuration
    if (!bgVal)
        bgVal := "333333"
    if (!txtVal)
        txtVal := "FFFFFF"
    if (!widthVal)
        widthVal := 200
    if (!heightVal)
        heightVal := 25
    if (!fontSizeVal)
        fontSizeVal := 9
    if (!alignVal)
        alignVal := "center"
    if (!borderVal)
        borderVal := ""  ; No border by default
    
    ; ===== INTEGRATED BORDER METHOD: Two GUI windows =====
    ; Border window (parent)
    ; FIX: -Border removes the thin window sizing-frame that made this look like a
    ; real desktop window instead of a floating tooltip. +E0x08000000 is the
    ; WS_EX_NOACTIVATE extended style, which makes it IMPOSSIBLE for this window to
    ; ever become the active/foreground window - the "NoActivate" show-option alone
    ; only asks nicely and can still momentarily flash-activate a brand-new window;
    ; baking WS_EX_NOACTIVATE in at creation time closes that gap completely.
    Gui, Border%currentTooltipGui%:New, +AlwaysOnTop +ToolWindow -Caption -Border +E0x08000000
    Gui, Border%currentTooltipGui%:Color, %borderVal%
    
    ; Content window (child of border)
    if (borderVal && borderVal != "") {
        Gui, Content%currentTooltipGui%:New, +AlwaysOnTop +ToolWindow -Caption -Border +E0x08000000 +ParentBorder%currentTooltipGui%
        Gui, Content%currentTooltipGui%:Color, %bgVal%
        
        contentW := widthVal - 4  ; 2px border each side
        contentH := heightVal - 4
        
        ; Build font string
        fontStr := "s" . fontSizeVal . " c" . txtVal
        if (fontBoldVal = "true") {
            fontStr .= " bold"
        }
        Gui, Content%currentTooltipGui%:Font, %fontStr%
        
        ; Text position with padding
        textX := 5
        textY := 3
        textW := contentW - 10
        textH := contentH - 6
        
        ; Add text control with transparent background
        alignFlag := (alignVal = "center" ? "Center" : (alignVal = "right" ? "Right" : ""))
        Gui, Content%currentTooltipGui%:Add, Text, x%textX% y%textY% w%textW% h%textH% BackgroundTrans %alignFlag%, %message%
        
        ; Get mouse position for positioning
        CoordMode, Mouse, Screen
        MouseGetPos, mX, mY
        
        ; Position tooltip near mouse
        posX := mX + 10
        posY := mY + 10
        
        ; Adjust for screen boundaries
        SysGet, screenWidth, 78
        SysGet, screenHeight, 79
        if (posX + widthVal > screenWidth) {
            posX := screenWidth - widthVal - 10
        }
        if (posY + heightVal > screenHeight) {
            posY := screenHeight - heightVal - 10
        }
        
        ; Show border window
        Gui, Border%currentTooltipGui%:Show, x%posX% y%posY% h%heightVal% w%widthVal% NoActivate
        
        ; Show content window at offset
        Gui, Content%currentTooltipGui%:Show, x2 y2 h%contentH% w%contentW% NoActivate
    } else {
        ; No border - use single window method
        ; FIX: same -Border / WS_EX_NOACTIVATE hardening as the bordered variant above.
        Gui, %currentTooltipGui%:New, +AlwaysOnTop +ToolWindow -Caption -Border +E0x08000000
        Gui, Color, %bgVal%
        
        ; Build font string
        fontStr := "s" . fontSizeVal . " c" . txtVal
        if (fontBoldVal = "true") {
            fontStr .= " bold"
        }
        Gui, Font, %fontStr%
        
        ; Add text
        alignFlag := (alignVal = "center" ? "Center" : (alignVal = "right" ? "Right" : ""))
        Gui, Add, Text, x10 y5 w%widthVal% h%heightVal% %alignFlag% -Wrap, %message%
        
        ; Position and show
        CoordMode, Mouse, Screen
        MouseGetPos, mX, mY
        posX := mX + 10
        posY := mY + 10
        
        SysGet, screenWidth, 78
        SysGet, screenHeight, 79
        if (posX + widthVal > screenWidth) {
            posX := screenWidth - widthVal - 10
        }
        if (posY + heightVal > screenHeight) {
            posY := screenHeight - heightVal - 10
        }
        
        Gui, %currentTooltipGui%:Show, x%posX% y%posY% h%heightVal% w%widthVal% NoActivate
    }
    
    ; Set auto-hide timer if duration > 0
    if (duration > 0) {
        SetTimer, HideSmartTooltip, -%duration%
        tooltipTimerActive := true
    }
}

HideSmartTooltip() {
    global currentTooltipGui, tooltipTimerActive
    
    ; Hide simple tooltip
    ToolTip
    
    ; Destroy both border and content windows if they exist
    if (currentTooltipGui) {
        Gui, Border%currentTooltipGui%:Destroy
        Gui, Content%currentTooltipGui%:Destroy
        currentTooltipGui := 0
    }
    
    tooltipTimerActive := false
}

; ===========================================================
; CLIPBOARD MANAGEMENT SYSTEM
; ===========================================================
; PURPOSE: Manages separate clipboards for XMind and system to prevent interference
; FEATURES: Backup/restore system clipboard, mark script-generated content for cleanup
; USAGE: Used during TTS operations to avoid corrupting user's clipboard

global SystemClipboardBackup := ""  ; Backup of system clipboard when working with XMind
global XMindClipboard := ""        ; Separate clipboard for XMind content
global ClipboardMarkers := {}      ; Track what clipboard content belongs to our script

; Save system clipboard and switch to XMind clipboard
SwitchToXMindClipboard() {
    global SystemClipboardBackup, XMindClipboard
    SystemClipboardBackup := ClipboardAll  ; Backup system clipboard
    if (XMindClipboard != "") {
        Clipboard := XMindClipboard  ; Restore XMind clipboard
        Sleep, 10
    }
}

; Save XMind clipboard and restore system clipboard
SwitchToSystemClipboard() {
    global SystemClipboardBackup, XMindClipboard
    XMindClipboard := ClipboardAll  ; Backup XMind clipboard
    if (SystemClipboardBackup != "") {
        Clipboard := SystemClipboardBackup  ; Restore system clipboard
        Sleep, 10
    }
}

; Mark clipboard content as belonging to our script
MarkClipboardContent(content) {
    global ClipboardMarkers
    if (content != "") {
        hash := HashString(content)
        ClipboardMarkers[hash] = true
        if (analyticalMode) {
            ShowSmartTooltip("📋 MARKED: " . SubStr(content, 1, 30) . "...", "Debug", 800)
        }
    }
}

; Check if clipboard content belongs to our script
IsMarkedClipboardContent(content) {
    global ClipboardMarkers
    if (content = "") {
        return false
    }
    hash := HashString(content)
    return ClipboardMarkers.HasKey(hash)
}

; Simple string hash function for content identification
HashString(str) {
    hash := 0
    Loop, Parse, str
        hash := ((hash << 5) - hash) + Asc(A_LoopField)
    return hash
}

; Clean up all marked clipboard content and reset tracking
CleanupClipboard() {
    global ClipboardMarkers, SystemClipboardBackup, XMindClipboard
    global originalHeading, differentHeadingDetected, headingHashTable
    
    ; Clear all markers
    ClipboardMarkers := {}
    
    ; Clear clipboard backups
    SystemClipboardBackup := ""
    XMindClipboard := ""
    
    ; Clear heading detection data
    originalHeading := ""
    differentHeadingDetected := false
    headingHashTable := {}
    
    ; Clear actual clipboard if it contains our marked content
    currentClip := Clipboard
    if (IsMarkedClipboardContent(currentClip)) {
        Clipboard := ""
        Sleep, 50
        if (analyticalMode) {
            ShowSmartTooltip("🧹 CLIPBOARD CLEANED", "Debug", 800)
        }
    }
}

; ===========================================================
; NEW: ROBUST CLIPBOARD RETRIEVAL SYSTEM
; ===========================================================
; PURPOSE: Handle large content reliably with progressive retry logic
; FEATURES: Dynamic timeout scaling, retry mechanism, loading feedback
; USAGE: Use instead of raw Send ^c + Sleep for critical operations

; Robust clipboard retrieval with automatic retry for large content
GetClipboardContentWithRetry(operationType := "note") {
    global selectionSleep, copySleep, clipWaitTimeout, Message_NoteLoading
    global analyticalMode
    
    ; Show loading message for large content
    ShowSmartTooltip(Message_NoteLoading, "NoteLoading", 0)
    
    ; Use XMind clipboard for the operation
    SwitchToXMindClipboard()
    
    ; Clear clipboard first
    Clipboard := ""
    Sleep, 50  ; Ensure clipboard is cleared
    
    ; Perform copy operation
    if (operationType = "note") {
        Send, ^a
        Sleep, %selectionSleep%
        Send, ^c
        Sleep, %copySleep%
    } else if (operationType = "heading") {
        Send, ^c
        Sleep, %headingTTSCopyDelay%
    }
    
    ; Progressive retry logic for clipboard content
    maxWaitTime := clipWaitTimeout * 1000  ; Convert to milliseconds
    currentWait := 100  ; Start with 100ms
    totalWaited := 0
    
    Loop {
        ; Wait for clipboard to contain data
        ClipWait, %currentWait%, 1
        
        if (ErrorLevel = 0) {
            ; Success - clipboard has content
            content := Clipboard
            
            ; Mark this content
            MarkClipboardContent(content)
            
            ; Clear tooltip
            HideSmartTooltip()
            
            ; Switch back to system clipboard
            SwitchToSystemClipboard()
            
            if (analyticalMode) {
                ShowSmartTooltip("✅ Clipboard ready after " . totalWaited + currentWait . "ms", "Debug", 800)
            }
            
            return content
        }
        
        ; Increment wait time
        totalWaited += currentWait
        
        ; Check if we've exceeded max wait time
        if (totalWaited >= maxWaitTime) {
            ; ALWAYS clear tooltip on timeout
            HideSmartTooltip()
            ShowSmartTooltip("Clipboard timeout", "Warning", 1200)
            Sleep, 500
            HideSmartTooltip()
            SwitchToSystemClipboard()
            return ""
        }
        
        ; Exponential backoff for next attempt
        currentWait := Min(currentWait * 2, 500)  ; Max 500ms per attempt
        
        if (analyticalMode) {
            ShowSmartTooltip("⏳ Waiting for clipboard... (" . totalWaited . "ms)", "Debug", 800)
        }
    }
}

; ===========================================================
; NUMBER SUPPRESSION SYSTEM
; ===========================================================
; PURPOSE: Prevents TTS from reading numbers in content while preserving F1 level announcements
; FEATURES: Toggle with F2, applies to both note and heading content, leaves system-generated numbers intact

; Strip numbers from text while preserving level announcement content
StripNumbersFromText(text) {
    global suppressNumbersEnabled
    if (suppressNumbersEnabled && text != "") {
        ; Remove all digit characters (0-9)
        strippedText := RegExReplace(text, "\d", "")
        return strippedText
    }
    return text
}

; ===========================================================
; NOTE WORDS PER LINE FORMATTING
; ===========================================================
; PURPOSE: Format text to have N words per line (for slow reading)
; PARAMETERS: wordsPerLine = 0 (disabled) or -1 to -10 (words per line)

FormatWordsPerLine(text, wordsPerLine) {
    if (wordsPerLine >= 0 || text = "")
        return text
    
    wordCount := Abs(wordsPerLine)
    
    ; Normalize whitespace and split into words
    normalizedText := RegExReplace(text, "\s+", " ")
    words := StrSplit(normalizedText, " ")
    
    result := ""
    lineWordCount := 0
    
    for index, word in words {
        if (Trim(word) = "")
            continue
        
        result .= word
        lineWordCount++
        
        if (lineWordCount >= wordCount) {
            result .= "`n"
            lineWordCount := 0
        } else {
            result .= " "
        }
    }
    
    return Trim(result)
}
; ===========================================================
; END OF CONFIGURATION - DON'T MODIFY BELOW UNLESS YOU KNOW WHAT YOU'RE DOING
; ===========================================================

; ======================================================================================================================
; ======================================================================================================================
; ======================================================================================================================
; STATE VARIABLES AND INITIALIZATION
; ======================================================================================================================
; ======================================================================================================================
; ======================================================================================================================

; PURPOSE: Track script state across different operations
; ORGANIZATION: Grouped by functionality for clarity

; Core feature state tracking
global noteToggleEnabled := false
global gestureToggleEnabled := false
global middleZoomActive := false

global shiftZoomActive := false

; Transitioning toggle state
global transitioningEnabled := false

; Note management state
global noteOpen := false
global noteWindowID := ""
global noteControl := ""

; TTS state management
global balconRunning := false
global headingTTSRunning := false
global balconPID := 0
global headingBalconPID := 0

; FIX: Real OS process handles for balcon.exe (note/heading).
; Windows recycles PIDs — after enough loop restarts, a closed balcon.exe's PID
; can get reassigned to some unrelated process. "Process, Exist, %balconPID%"
; only compares the number, so it can falsely report "still running" and freeze
; the loop after a few iterations. A handle opened at launch time always points
; to that exact process, so checking it is immune to PID reuse.
global balconProcessHandle := 0
global headingBalconProcessHandle := 0

; Dual detection system state
global originalHeading := ""
global differentHeadingDetected := false
global headingDetectionActive := false
global backgroundDetectionActive := false
global dualDetectionEnabled := false

; Advanced feature states
global ttsLocked := true
global analyticalMode := false

; Heading TTS specific state
global headingHashTable := {}

; Enhanced Level Announcement system
global levelAnnounceEnabled := false
global levelAnnounceMode := 1
global levelSelectionActive := false
global levelSelectionTimer := 0

; Double press detection for mode selection
global key1PressCount := 0
global key1LastPressTime := 0
global key1DoublePressThreshold := 400  ; 400ms threshold

; Double press detection for mode selection
global key4PressCount := 0
global key4LastPressTime := 0
global key4DoublePressThreshold := 400

global key5PressCount := 0
global key5LastPressTime := 0
global key5DoublePressThreshold := 400

; Automatic TTS control
global pendingNoteTTSAfterHeadingStop := false

; File management for large TTS operations
global currentNoteTTSFile := ""
global currentHeadingTTSFile := ""

; Mouse gesture tracking
global _lbtn_down_x := 0
global _lbtn_down_y := 0
global _lbtn_was_down := false

; Number suppression state
global suppressNumbersEnabled := false
global originalSuppressNumbersState := false  ; NEW: Store original state for heading TTS

; Loop mode state
global loopMode := false
global currentNoteContent := ""
global currentHeadingContent := ""
global currentNoteOriginalContent := ""        ; NEW: Stores unfiltered note content

; NEW: Hybrid loop mode state
global currentHeadingRawStructure := ""
global currentHeadingOriginalStructure := ""   ; NEW: Stores unfiltered heading structure
global loopPatternToggle := false

; GUI tooltip tracking (for borders)
global currentTooltipGui := 0
global tooltipTimerActive := false

; Loop audio suppression - prevents device switching during active loops
global loopModeSuppressAudioSwitch := false

; Zero-gap looping state
global immediateRestartActive := false

; File-based loop system
global loopNoteFile := ""      ; Persistent file for note loops
global loopHeadingFile := ""   ; Persistent file for heading loops

; Mode 4 caching for consistent patterns
global cachedMode4Content := ""    ; Cache hierarchical processed text

; Loop gap control - consistent silence between loop iterations (milliseconds)
global loopGapMs  ; 50ms = consistent tiny gap, increase if needed

; Add these new global variables
global loopChunkMode := false      ; NEW: Track if we're in chunked loop mode
global loopChunkFiles := []        ; NEW: Persistent chunk files for loop mode
global originalContentFile := ""   ; NEW: Store original content file path

; Gap state management
global isInGapPhase := false      ; NEW: Track when between loop iterations
global manualLoopKill := false     ; Your existing flag

; TTS type tracking for clean transitions (during gaps)
global activeTTSType := ""     ; "note" or "heading" or ""
global isTransitioning := false ; Track if TTS started from opposite type


; Gap state management
global isInGapPhase := false
global manualLoopKill := false

; Loop tooltip throttling
global loopNoteJustRestarted := false
global loopHeadingJustRestarted := false

; Add this if not present
global speedMultiplier


; Note words per line mode
global noteWordsPerLine := 0






; F6 toggle state
global f6Mode := "level"





; Add these to your GLOBAL VARIABLES section at the top of the script:
global innatePanningActive := false
global mbuttonHoldStart := 0


; === GLOBAL VARIABLES (Add to SECTION 1) ===
global specificIndexModeEnabled := false

; ===========================================================
; HEADING FILTER GUI VARIABLES (200 Levels)
; ===========================================================
; These 200 checkbox variables (CB1-200) + 199 combo variables (Combo2-200) are 
; required for AutoHotkey v1.1 GUI control creation. Level 1 has no combo box.

global headingFilterCB1, headingFilterCB2, headingFilterCB3, headingFilterCB4, headingFilterCB5
global headingFilterCB6, headingFilterCB7, headingFilterCB8, headingFilterCB9, headingFilterCB10
global headingFilterCB11, headingFilterCB12, headingFilterCB13, headingFilterCB14, headingFilterCB15
global headingFilterCB16, headingFilterCB17, headingFilterCB18, headingFilterCB19, headingFilterCB20
global headingFilterCB21, headingFilterCB22, headingFilterCB23, headingFilterCB24, headingFilterCB25
global headingFilterCB26, headingFilterCB27, headingFilterCB28, headingFilterCB29, headingFilterCB30
global headingFilterCB31, headingFilterCB32, headingFilterCB33, headingFilterCB34, headingFilterCB35
global headingFilterCB36, headingFilterCB37, headingFilterCB38, headingFilterCB39, headingFilterCB40
global headingFilterCB41, headingFilterCB42, headingFilterCB43, headingFilterCB44, headingFilterCB45
global headingFilterCB46, headingFilterCB47, headingFilterCB48, headingFilterCB49, headingFilterCB50
global headingFilterCB51, headingFilterCB52, headingFilterCB53, headingFilterCB54, headingFilterCB55
global headingFilterCB56, headingFilterCB57, headingFilterCB58, headingFilterCB59, headingFilterCB60
global headingFilterCB61, headingFilterCB62, headingFilterCB63, headingFilterCB64, headingFilterCB65
global headingFilterCB66, headingFilterCB67, headingFilterCB68, headingFilterCB69, headingFilterCB70
global headingFilterCB71, headingFilterCB72, headingFilterCB73, headingFilterCB74, headingFilterCB75
global headingFilterCB76, headingFilterCB77, headingFilterCB78, headingFilterCB79, headingFilterCB80
global headingFilterCB81, headingFilterCB82, headingFilterCB83, headingFilterCB84, headingFilterCB85
global headingFilterCB86, headingFilterCB87, headingFilterCB88, headingFilterCB89, headingFilterCB90
global headingFilterCB91, headingFilterCB92, headingFilterCB93, headingFilterCB94, headingFilterCB95
global headingFilterCB96, headingFilterCB97, headingFilterCB98, headingFilterCB99, headingFilterCB100
global headingFilterCB101, headingFilterCB102, headingFilterCB103, headingFilterCB104, headingFilterCB105
global headingFilterCB106, headingFilterCB107, headingFilterCB108, headingFilterCB109, headingFilterCB110
global headingFilterCB111, headingFilterCB112, headingFilterCB113, headingFilterCB114, headingFilterCB115
global headingFilterCB116, headingFilterCB117, headingFilterCB118, headingFilterCB119, headingFilterCB120
global headingFilterCB121, headingFilterCB122, headingFilterCB123, headingFilterCB124, headingFilterCB125
global headingFilterCB126, headingFilterCB127, headingFilterCB128, headingFilterCB129, headingFilterCB130
global headingFilterCB131, headingFilterCB132, headingFilterCB133, headingFilterCB134, headingFilterCB135
global headingFilterCB136, headingFilterCB137, headingFilterCB138, headingFilterCB139, headingFilterCB140
global headingFilterCB141, headingFilterCB142, headingFilterCB143, headingFilterCB144, headingFilterCB145
global headingFilterCB146, headingFilterCB147, headingFilterCB148, headingFilterCB149, headingFilterCB150
global headingFilterCB151, headingFilterCB152, headingFilterCB153, headingFilterCB154, headingFilterCB155
global headingFilterCB156, headingFilterCB157, headingFilterCB158, headingFilterCB159, headingFilterCB160
global headingFilterCB161, headingFilterCB162, headingFilterCB163, headingFilterCB164, headingFilterCB165
global headingFilterCB166, headingFilterCB167, headingFilterCB168, headingFilterCB169, headingFilterCB170
global headingFilterCB171, headingFilterCB172, headingFilterCB173, headingFilterCB174, headingFilterCB175
global headingFilterCB176, headingFilterCB177, headingFilterCB178, headingFilterCB179, headingFilterCB180
global headingFilterCB181, headingFilterCB182, headingFilterCB183, headingFilterCB184, headingFilterCB185
global headingFilterCB186, headingFilterCB187, headingFilterCB188, headingFilterCB189, headingFilterCB190
global headingFilterCB191, headingFilterCB192, headingFilterCB193, headingFilterCB194, headingFilterCB195
global headingFilterCB196, headingFilterCB197, headingFilterCB198, headingFilterCB199, headingFilterCB200

; SpinBox controls (levels 2-200)
global headingFilterSpin2, headingFilterSpin3, headingFilterSpin4, headingFilterSpin5
global headingFilterSpin6, headingFilterSpin7, headingFilterSpin8, headingFilterSpin9, headingFilterSpin10
global headingFilterSpin11, headingFilterSpin12, headingFilterSpin13, headingFilterSpin14, headingFilterSpin15
global headingFilterSpin16, headingFilterSpin17, headingFilterSpin18, headingFilterSpin19, headingFilterSpin20
global headingFilterSpin21, headingFilterSpin22, headingFilterSpin23, headingFilterSpin24, headingFilterSpin25
global headingFilterSpin26, headingFilterSpin27, headingFilterSpin28, headingFilterSpin29, headingFilterSpin30
global headingFilterSpin31, headingFilterSpin32, headingFilterSpin33, headingFilterSpin34, headingFilterSpin35
global headingFilterSpin36, headingFilterSpin37, headingFilterSpin38, headingFilterSpin39, headingFilterSpin40
global headingFilterSpin41, headingFilterSpin42, headingFilterSpin43, headingFilterSpin44, headingFilterSpin45
global headingFilterSpin46, headingFilterSpin47, headingFilterSpin48, headingFilterSpin49, headingFilterSpin50
global headingFilterSpin51, headingFilterSpin52, headingFilterSpin53, headingFilterSpin54, headingFilterSpin55
global headingFilterSpin56, headingFilterSpin57, headingFilterSpin58, headingFilterSpin59, headingFilterSpin60
global headingFilterSpin61, headingFilterSpin62, headingFilterSpin63, headingFilterSpin64, headingFilterSpin65
global headingFilterSpin66, headingFilterSpin67, headingFilterSpin68, headingFilterSpin69, headingFilterSpin70
global headingFilterSpin71, headingFilterSpin72, headingFilterSpin73, headingFilterSpin74, headingFilterSpin75
global headingFilterSpin76, headingFilterSpin77, headingFilterSpin78, headingFilterSpin79, headingFilterSpin80
global headingFilterSpin81, headingFilterSpin82, headingFilterSpin83, headingFilterSpin84, headingFilterSpin85
global headingFilterSpin86, headingFilterSpin87, headingFilterSpin88, headingFilterSpin89, headingFilterSpin90
global headingFilterSpin91, headingFilterSpin92, headingFilterSpin93, headingFilterSpin94, headingFilterSpin95
global headingFilterSpin96, headingFilterSpin97, headingFilterSpin98, headingFilterSpin99, headingFilterSpin100
global headingFilterSpin101, headingFilterSpin102, headingFilterSpin103, headingFilterSpin104, headingFilterSpin105
global headingFilterSpin106, headingFilterSpin107, headingFilterSpin108, headingFilterSpin109, headingFilterSpin110
global headingFilterSpin111, headingFilterSpin112, headingFilterSpin113, headingFilterSpin114, headingFilterSpin115
global headingFilterSpin116, headingFilterSpin117, headingFilterSpin118, headingFilterSpin119, headingFilterSpin120
global headingFilterSpin121, headingFilterSpin122, headingFilterSpin123, headingFilterSpin124, headingFilterSpin125
global headingFilterSpin126, headingFilterSpin127, headingFilterSpin128, headingFilterSpin129, headingFilterSpin130
global headingFilterSpin131, headingFilterSpin132, headingFilterSpin133, headingFilterSpin134, headingFilterSpin135
global headingFilterSpin136, headingFilterSpin137, headingFilterSpin138, headingFilterSpin139, headingFilterSpin140
global headingFilterSpin141, headingFilterSpin142, headingFilterSpin143, headingFilterSpin144, headingFilterSpin145
global headingFilterSpin146, headingFilterSpin147, headingFilterSpin148, headingFilterSpin149, headingFilterSpin150
global headingFilterSpin151, headingFilterSpin152, headingFilterSpin153, headingFilterSpin154, headingFilterSpin155
global headingFilterSpin156, headingFilterSpin157, headingFilterSpin158, headingFilterSpin159, headingFilterSpin160
global headingFilterSpin161, headingFilterSpin162, headingFilterSpin163, headingFilterSpin164, headingFilterSpin165
global headingFilterSpin166, headingFilterSpin167, headingFilterSpin168, headingFilterSpin169, headingFilterSpin170
global headingFilterSpin171, headingFilterSpin172, headingFilterSpin173, headingFilterSpin174, headingFilterSpin175
global headingFilterSpin176, headingFilterSpin177, headingFilterSpin178, headingFilterSpin179, headingFilterSpin180
global headingFilterSpin181, headingFilterSpin182, headingFilterSpin183, headingFilterSpin184, headingFilterSpin185
global headingFilterSpin186, headingFilterSpin187, headingFilterSpin188, headingFilterSpin189, headingFilterSpin190
global headingFilterSpin191, headingFilterSpin192, headingFilterSpin193, headingFilterSpin194, headingFilterSpin195
global headingFilterSpin196, headingFilterSpin197, headingFilterSpin198, headingFilterSpin199, headingFilterSpin200

; RadioBox controls (levels 2-200)
global headingFilterRadioBox2, headingFilterRadioBox3, headingFilterRadioBox4, headingFilterRadioBox5
global headingFilterRadioBox6, headingFilterRadioBox7, headingFilterRadioBox8, headingFilterRadioBox9, headingFilterRadioBox10
global headingFilterRadioBox11, headingFilterRadioBox12, headingFilterRadioBox13, headingFilterRadioBox14, headingFilterRadioBox15
global headingFilterRadioBox16, headingFilterRadioBox17, headingFilterRadioBox18, headingFilterRadioBox19, headingFilterRadioBox20
global headingFilterRadioBox21, headingFilterRadioBox22, headingFilterRadioBox23, headingFilterRadioBox24, headingFilterRadioBox25
global headingFilterRadioBox26, headingFilterRadioBox27, headingFilterRadioBox28, headingFilterRadioBox29, headingFilterRadioBox30
global headingFilterRadioBox31, headingFilterRadioBox32, headingFilterRadioBox33, headingFilterRadioBox34, headingFilterRadioBox35
global headingFilterRadioBox36, headingFilterRadioBox37, headingFilterRadioBox38, headingFilterRadioBox39, headingFilterRadioBox40
global headingFilterRadioBox41, headingFilterRadioBox42, headingFilterRadioBox43, headingFilterRadioBox44, headingFilterRadioBox45
global headingFilterRadioBox46, headingFilterRadioBox47, headingFilterRadioBox48, headingFilterRadioBox49, headingFilterRadioBox50
global headingFilterRadioBox51, headingFilterRadioBox52, headingFilterRadioBox53, headingFilterRadioBox54, headingFilterRadioBox55
global headingFilterRadioBox56, headingFilterRadioBox57, headingFilterRadioBox58, headingFilterRadioBox59, headingFilterRadioBox60
global headingFilterRadioBox61, headingFilterRadioBox62, headingFilterRadioBox63, headingFilterRadioBox64, headingFilterRadioBox65
global headingFilterRadioBox66, headingFilterRadioBox67, headingFilterRadioBox68, headingFilterRadioBox69, headingFilterRadioBox70
global headingFilterRadioBox71, headingFilterRadioBox72, headingFilterRadioBox73, headingFilterRadioBox74, headingFilterRadioBox75
global headingFilterRadioBox76, headingFilterRadioBox77, headingFilterRadioBox78, headingFilterRadioBox79, headingFilterRadioBox80
global headingFilterRadioBox81, headingFilterRadioBox82, headingFilterRadioBox83, headingFilterRadioBox84, headingFilterRadioBox85
global headingFilterRadioBox86, headingFilterRadioBox87, headingFilterRadioBox88, headingFilterRadioBox89, headingFilterRadioBox90
global headingFilterRadioBox91, headingFilterRadioBox92, headingFilterRadioBox93, headingFilterRadioBox94, headingFilterRadioBox95
global headingFilterRadioBox96, headingFilterRadioBox97, headingFilterRadioBox98, headingFilterRadioBox99, headingFilterRadioBox100
global headingFilterRadioBox101, headingFilterRadioBox102, headingFilterRadioBox103, headingFilterRadioBox104, headingFilterRadioBox105
global headingFilterRadioBox106, headingFilterRadioBox107, headingFilterRadioBox108, headingFilterRadioBox109, headingFilterRadioBox110
global headingFilterRadioBox111, headingFilterRadioBox112, headingFilterRadioBox113, headingFilterRadioBox114, headingFilterRadioBox115
global headingFilterRadioBox116, headingFilterRadioBox117, headingFilterRadioBox118, headingFilterRadioBox119, headingFilterRadioBox120
global headingFilterRadioBox121, headingFilterRadioBox122, headingFilterRadioBox123, headingFilterRadioBox124, headingFilterRadioBox125
global headingFilterRadioBox126, headingFilterRadioBox127, headingFilterRadioBox128, headingFilterRadioBox129, headingFilterRadioBox130
global headingFilterRadioBox131, headingFilterRadioBox132, headingFilterRadioBox133, headingFilterRadioBox134, headingFilterRadioBox135
global headingFilterRadioBox136, headingFilterRadioBox137, headingFilterRadioBox138, headingFilterRadioBox139, headingFilterRadioBox140
global headingFilterRadioBox141, headingFilterRadioBox142, headingFilterRadioBox143, headingFilterRadioBox144, headingFilterRadioBox145
global headingFilterRadioBox146, headingFilterRadioBox147, headingFilterRadioBox148, headingFilterRadioBox149, headingFilterRadioBox150
global headingFilterRadioBox151, headingFilterRadioBox152, headingFilterRadioBox153, headingFilterRadioBox154, headingFilterRadioBox155
global headingFilterRadioBox156, headingFilterRadioBox157, headingFilterRadioBox158, headingFilterRadioBox159, headingFilterRadioBox160
global headingFilterRadioBox161, headingFilterRadioBox162, headingFilterRadioBox163, headingFilterRadioBox164, headingFilterRadioBox165
global headingFilterRadioBox166, headingFilterRadioBox167, headingFilterRadioBox168, headingFilterRadioBox169, headingFilterRadioBox170
global headingFilterRadioBox171, headingFilterRadioBox172, headingFilterRadioBox173, headingFilterRadioBox174, headingFilterRadioBox175
global headingFilterRadioBox176, headingFilterRadioBox177, headingFilterRadioBox178, headingFilterRadioBox179, headingFilterRadioBox180
global headingFilterRadioBox181, headingFilterRadioBox182, headingFilterRadioBox183, headingFilterRadioBox184, headingFilterRadioBox185
global headingFilterRadioBox186, headingFilterRadioBox187, headingFilterRadioBox188, headingFilterRadioBox189, headingFilterRadioBox190
global headingFilterRadioBox191, headingFilterRadioBox192, headingFilterRadioBox193, headingFilterRadioBox194, headingFilterRadioBox195
global headingFilterRadioBox196, headingFilterRadioBox197, headingFilterRadioBox198, headingFilterRadioBox199, headingFilterRadioBox200









; Heading Filter GUI State
global headingFilterGUIActive := false
global headingFilterGUIVisible := false
global headingFilterLevelCount := 10
global headingFilterCheckboxes := []
; Initialize all levels to true (matches GUI default where all checkboxes are checked)
Loop, 200 {
    headingFilterCheckboxes[A_Index] := true
}
global headingFilterInputValues := []
global headingFilterRadioStates := []
global f7HoldStart := 0
global f7LongPressActive := false
global lastFocusLossTime := 0


; ===========================================================
; HEADING FILTER GUI PAGINATION VARIABLES
; ===========================================================
global currentHeadingFilterPage := 1
global totalHeadingFilterPages := 1
global levelsPerPage := 20  ; 20 levels per page

; ** Pagination control variables (must be declared globally) **
; GUI Control Variables
global LevelCountDD, PrevPageBtn, NextPageBtn, F4F5OverrideCB, F4F5OverrideLevel



; F4/F5 Level Override Feature
global f4f5OverrideActive := false     ; Checkbox state
global f4f5OverrideLevel := 2          ; Which level to control
global f4f5CurrentHeadingNum := 0      ; Current heading number
global f4f5LastMode := ""              ; Store last F6 mode before override


; F4/F5 GUI Control Variables
global F4F5OverrideCB


; ======================================================================================================================
; ======================================================================================================================
; ======================================================================================================================
; TIMER AND EVENT SYSTEM SETUP
; ======================================================================================================================
; ======================================================================================================================
; ======================================================================================================================
; PURPOSE: Set up periodic checks and event handlers
; TIMING: Each timer has specific intervals for optimal performance

; Core monitoring timers
SetTimer, _CheckNoteFocusTimer, 50     ; How often to check note focus in milliseconds
SetTimer, _CheckAppFocusTimer, 100

; Reverted to original timing - file system handles persistence
SetTimer, _CheckTTSFinished, 20
SetTimer, _CheckHeadingTTSFinished, 20

; High-performance detection timers
SetTimer, _BackgroundHeadingCheck, 20
SetTimer, _CheckPendingNoteTTS, 50

; Maintenance timers
SetTimer, _CleanupTempFile, 30000

SetTimer, _HeadingFilterFocusCheck, 500

; Watches for Python's "AI reply is on the clipboard, please paste it" signal
SetTimer, _PollAIPasteReady, 120

; Cleanup on script exit
OnExit("CleanupBeforeExit")

; ===========================================================
; ANALYTICAL MESSAGES SYSTEM
; ===========================================================
; PURPOSE: Provide debug and analysis information when analytical mode is enabled
; USAGE: Helps developers understand script behavior and troubleshoot issues

ShowAnalyticalMessage(message) {
    return  ; Add this line to disable all analytical tooltips; If you don't need debug messages, disable them permanently; 5-10x faster all operations
    global analyticalMode, dualDetectionEnabled
    if (analyticalMode && dualDetectionEnabled) {
        ; Truncate long messages to 50 characters
        truncatedMessage := TruncateString(message, 50)
        ShowSmartTooltip(truncatedMessage, "Debug", 1200)
    }
}

ShowAnalyticalDebug(message) {
    global analyticalMode, dualDetectionEnabled
    if (analyticalMode && dualDetectionEnabled) {
        ; Truncate long messages to 50 characters
        truncatedMessage := TruncateString(message, 50)
        ShowSmartTooltip(truncatedMessage, "Debug", 800)
    }
}

; Function to truncate strings with ellipsis for clean display
TruncateString(str, maxLength) {
    if (StrLen(str) <= maxLength) {
        return str
    }
    return SubStr(str, 1, maxLength - 3) . "..."
}

; ===========================================================
; SPEED PREPROCESSOR - SIMULATES FASTER SPEECH (1.0x to 9.0x)
; ===========================================================
; =================================================================
; FIX: RELIABLE PROCESS-END DETECTION (immune to Windows PID reuse)
; =================================================================
; Opens a real OS handle to the process with this PID, right after launching it.
; Call this immediately after every "Run ..., , Hide, balconPID/headingBalconPID".
OpenBalconHandle(PID) {
    if (!PID) {
        return 0
    }
    ; SYNCHRONIZE access (0x00100000) is enough to wait on the handle.
    return DllCall("OpenProcess", "UInt", 0x00100000, "Int", 0, "UInt", PID, "Ptr")
}

; Closes a previously-opened handle and clears the variable.
CloseBalconHandle(ByRef hProcess) {
    if (hProcess) {
        DllCall("CloseHandle", "Ptr", hProcess)
    }
    hProcess := 0
}

; Returns true only when the exact process behind hProcess has actually exited.
; Unlike "Process, Exist, PID", this cannot be fooled by the PID being reused
; by a different, unrelated process after balcon.exe closes.
HasBalconProcessExited(hProcess) {
    if (!hProcess) {
        return true  ; No handle to wait on - treat as already gone
    }
    ; WaitForSingleObject with 0 timeout: returns 0 (WAIT_OBJECT_0) if signaled/exited,
    ; 258 (WAIT_TIMEOUT) if still running.
    result := DllCall("WaitForSingleObject", "Ptr", hProcess, "UInt", 0, "UInt")
    return (result = 0)
}

PreprocessTextForSpeed(text, multiplier) {
    if (multiplier <= 1.0 || text = "")
        return text
    
    result := text
    
    ; LEVEL 1 (1.2x-1.5x): Clean whitespace and remove long pauses
    if (multiplier >= 1.2) {
        result := RegExReplace(result, "\s+", " ")  ; Normalize spaces
        result := RegExReplace(result, "\.+\s*", ". ")  ; Standardize periods
        result := RegExReplace(result, "[,;:]+\s*", " ")  ; Remove pause punctuation
        result := Trim(result)
    }
    
    ; LEVEL 2 (1.5x-2.0x): Remove paragraph breaks
    if (multiplier >= 1.5) {
        result := StrReplace(result, "`r`n", " ")
        result := StrReplace(result, "`n", " ")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 3 (2.0x-3.0x): Remove common filler words
    if (multiplier >= 2.0) {
        fillerWords := "(\bthe\b|\ba\b|\ban\b|\band\b|\bor\b|\bbut\b|\bis\b|\bare\b|\bwas\b|\bwere\b|\bto\b|\bof\b)"
        result := RegExReplace(result, fillerWords, "", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 4 (3.0x-4.0x): Remove more complex words and shorten phrases
    if (multiplier >= 3.0) {
        complexWords := "(\bthis\b|\bthat\b|\bthese\b|\bthose\b|\bwill\b|\bshall\b|\bshould\b|\bwould\b|\bcould\b|\bcan\b|\bcannot\b)"
        result := RegExReplace(result, complexWords, "", "i")
        result := RegExReplace(result, "\b(for example|for instance)\b", "eg", "i")
        result := RegExReplace(result, "\b(that is)\b", "ie", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 5 (4.0x-5.0x): Remove all prepositions, pronouns, conjunctions
    if (multiplier >= 4.0) {
        allStopWords := "(\babout\b|\babove\b|\bacross\b|\bafter\b|\bagainst\b|\balong\b|\bamong\b|\baround\b|\bbecause\b|\bbefore\b|\bbehind\b|\bbelow\b|\bbeneath\b|\bbeside\b|\bbetween\b|\bbeyond\b|\bbut\b|\bby\b|\bconcerning\b|\bconsidering\b|\bdespite\b|\bdown\b|\bduring\b|\bexcept\b|\bfollowing\b|\bfor\b|\bfrom\b|\bin\b|\binto\b|\blike\b|\bnear\b|\bof\b|\boff\b|\bon\b|\bonce\b|\bonto\b|\bover\b|\bpast\b|\bplus\b|\bsince\b|\bthrough\b|\bthroughout\b|\bto\b|\btoward\b|\bunder\b|\bunderneath\b|\buntil\b|\bup\b|\bupon\b|\bwith\b|\bwithin\b|\bwithout\b|\bhe\b|\bher\b|\bhers\b|\bhim\b|\bhis\b|\bit\b|\bits\b|\bme\b|\bmine\b|\bmy\b|\bours\b|\btheirs\b|\bthem\b|\bthey\b|\bus\b|\bwe\b|\byou\b|\byours\b|\bI\b|\byou\b|\bwe\b|\bthey\b)"
        result := RegExReplace(result, allStopWords, "", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 6 (5.0x-6.0x): Abbreviate common phrases heavily
    if (multiplier >= 5.0) {
        result := RegExReplace(result, "\b(in order to)\b", "2", "i")
        result := RegExReplace(result, "\b(in regards to)\b", "re", "i")
        result := RegExReplace(result, "\b(as well as)\b", "&", "i")
        result := RegExReplace(result, "\b(as soon as possible)\b", " ASAP ", "i")
        result := RegExReplace(result, "\b(with respect to)\b", "wrt", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 7 (6.0x-7.0x): Keep only nouns and verbs (aggressive)
    if (multiplier >= 6.0) {
        ; Remove all words 3 letters or less (aggressive filter)
        result := RegExReplace(result, "\b\w{1,3}\b", "", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 8 (7.0x-8.0x): Remove internal vowels from long words
    if (multiplier >= 7.0) {
        result := RegExReplace(result, "(\b\w{4,})\B[aeiouAEIOU]\B", "$1", "g")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; LEVEL 9 (8.0x-9.0x): Extreme compression - keep only key content words
    if (multiplier >= 8.0) {
        ; Remove all punctuation except sentence breaks
        result := RegExReplace(result, "[^\w\s\.]", "")
        ; Further compress by removing repeated patterns
        result := RegExReplace(result, "(\b\w+\b)(?:\s+\1\b)+", "$1", "i")
        result := RegExReplace(result, "\s+", " ")
    }
    
    ; Final aggressive cleanup for very high multipliers
    if (multiplier >= 9.0) {
        result := RegExReplace(result, "(\b\w{3,})\B[aeiouAEIOU]\B", "$1", "g")  ; Remove ALL internal vowels
    }
    
    ; Final cleanup
    result := RegExReplace(result, "\s+", " ")
    return Trim(result)
}

; ===========================================================
; SMART TTS APPROACH - OPTIMAL PERFORMANCE FOR 100K+ WORDS
; ===========================================================
; PURPOSE: Hybrid TTS with nircmd audio routing for BOTH direct and file-based methods
; STRATEGY: Switch audio device → Run balcon → Restore device on stop
; BENEFITS: Handles unlimited text with proper audio routing for all cases

; ===========================================================
; REVOLUTIONARY DIRECT-FILE SYSTEM - NO CLIPBOARD NEEDED
; ===========================================================
; ===========================================================
; SMART TTS APPROACH - NO CHUNKING, TRUE LOOP SYSTEM
; ===========================================================
; =================================================================
; INITIAL DEVICE SWITCH WHEN TTS STARTS (STAYS IN LOOP)
; =================================================================

; Smart TTS approach - starts with device switch, then STAYS in loop mode
; Smart TTS approach - starts with device switch, then STAYS in loop mode
; FIXED: Loop mode now respects F2 (number suppression) state changes
; Smart TTS approach - starts with device switch, then STAYS in loop mode
; FIXED: Loop mode now respects F2 (number suppression) state changes
; FIXED: Audio lock support - skips device switch when locked
SpeakWithBalconSmart(text, ttsType) {
    global balconPath, balconVoice, balconSpeed, balconPitch, balconVolume
    global balconPID, headingBalconPID, balconRunning, headingTTSRunning
    global balconProcessHandle, headingBalconProcessHandle
    global CABLE_DEVICE, NIRCMD_PATH, analyticalMode, loopMode
    global currentNoteTTSFile, currentHeadingTTSFile, suppressNumbersEnabled
    global audioLockActive  ; <-- ADDED for audio lock feature
    
    ; Apply number suppression if enabled
    cleanText := text
    if (suppressNumbersEnabled && ttsType = "note") {
        cleanText := StripNumbersFromText(text)
    }
    
    ; STEP 1: Audio routing - SKIP if audio lock active
    if (!audioLockActive) {
        Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . CABLE_DEVICE . Chr(34), , Hide
        Sleep, 20  ; ← Reduced for speed
    } else {
        ; Audio locked - already on CABLE, skip switch
        if (analyticalMode) {
            ShowSmartTooltip("🔒 Audio lock active - skip switch to CABLE", "Debug", 400)
        }
    }
    
    ; STEP 2: Create/Use appropriate file
    if (loopMode) {
        ; FIXED: ALWAYS recreate file to respect current suppression state
        if (ttsType = "note") {
            loopNoteFile := A_Temp . "\xmind_loop_note_" . A_TickCount . ".txt"
            FileDelete, %loopNoteFile%
            FileAppend, %cleanText%, %loopNoteFile%
            tempFile := loopNoteFile
            currentNoteTTSFile := tempFile
        } else if (ttsType = "heading") {
            loopHeadingFile := A_Temp . "\xmind_loop_heading_" . A_TickCount . ".txt"
            FileDelete, %loopHeadingFile%
            FileAppend, %cleanText%, %loopHeadingFile%
            tempFile := loopHeadingFile
            currentHeadingTTSFile := tempFile
        }
    } else {
        ; Use temporary file for non-loop mode
        tempFile := A_Temp . "\xmind_tts_" . A_TickCount . ".txt"
        FileDelete, %tempFile%
        FileAppend, %cleanText%, %tempFile%
    }
    
    ; STEP 3: Verify file
    if (!FileExist(tempFile)) {
        ShowSmartTooltip("❌ FILE CREATE FAILED", "Debug", 1200)
        return false
    }
    
    ; STEP 4: Launch balcon
    if (ttsType = "note") {
        currentNoteTTSFile := tempFile
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . tempFile . Chr(34), , Hide, balconPID
        CloseBalconHandle(balconProcessHandle)
        balconProcessHandle := OpenBalconHandle(balconPID)
        balconRunning := true
    } else if (ttsType = "heading") {
        currentHeadingTTSFile := tempFile
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . tempFile . Chr(34), , Hide, headingBalconPID
        CloseBalconHandle(headingBalconProcessHandle)
        headingBalconProcessHandle := OpenBalconHandle(headingBalconPID)
        headingTTSRunning := true
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("📁 TTS FILE: " . StrLen(cleanText) . " chars", "Debug", 800)
    }
    
    return true
}

; NEW: Process massive content with zero memory footprint
; FIXED: Process massive content with robust error handling
; FIXED: Guaranteed massive content processing
ProcessMassiveContent(cleanText, ttsType) {
    global balconPath, balconVoice, balconSpeed, balconPitch, balconVolume
    global balconPID, headingBalconPID, balconRunning, headingTTSRunning
    global loopMode, loopNoteFile, loopHeadingFile, analyticalMode
    global loopChunkMode, loopChunkFiles, originalContentFile
    
    CleanupChunkFiles()
    
    textLength := StrLen(cleanText)
    if (textLength <= maxMemoryBuffer) {
        return ProcessRegularFile(cleanText, ttsType)
    }
    
    ShowSmartTooltip("🧩 Processing " . Format("{:,.0f}", textLength) . " chars...", "NoteLoading", 0)
    
    loopChunkMode := loopMode
    chunkCount := 0
    loopChunkFiles := []
    
    Loop {
        startPos := (chunkCount * chunkSizeChars) + 1
        if (startPos > textLength) {
            break
        }
        
        chunkText := SubStr(cleanText, startPos, chunkSizeChars)
        chunkFile := A_Temp . "\xmind_chunk_" . A_TickCount . "_" . chunkCount . ".txt"
        FileDelete, %chunkFile%
        FileAppend, %chunkText%, %chunkFile%
        
        if (!FileExist(chunkFile)) {
            ShowSmartTooltip("❌ CHUNK FILE CREATION FAILED", "Debug", 1200)
            continue
        }
        
        loopChunkFiles.Push(chunkFile)
        chunkCount++
    }
    
    HideSmartTooltip()
    
    if (loopChunkFiles.Length() = 0) {
        return false
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("🧩 " . loopChunkFiles.Length() . " chunks created", "Debug", 2000)
    }
    
    return PlayNextChunk(ttsType)
}

; NEW: Process regular non-chunked files
ProcessRegularFile(cleanText, ttsType) {
    global loopMode, loopNoteFile, loopHeadingFile
    
    if (loopMode && ttsType = "note") {
        if (loopNoteFile = "" || !FileExist(loopNoteFile)) {
            loopNoteFile := A_Temp . "\xmind_loop_note_" . A_TickCount . ".txt"
            FileDelete, %loopNoteFile%
        }
        tempFile := loopNoteFile
    } else if (loopMode && ttsType = "heading") {
        if (loopHeadingFile = "" || !FileExist(loopHeadingFile)) {
            loopHeadingFile := A_Temp . "\xmind_loop_heading_" . A_TickCount . ".txt"
            FileDelete, %loopHeadingFile%
        }
        tempFile := loopHeadingFile
    } else {
        tempFile := A_Temp . "\xmind_tts_" . A_TickCount . ".txt"
        FileDelete, %tempFile%
    }
    
    FileAppend, %cleanText%, %tempFile%
    
    if (!FileExist(tempFile)) {
        return false
    }
    
    if (ttsType = "note") {
        global currentNoteTTSFile
        currentNoteTTSFile := tempFile
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . tempFile . Chr(34), , Hide, balconPID
        balconRunning := true
    } else if (ttsType = "heading") {
        global currentHeadingTTSFile
        currentHeadingTTSFile := tempFile
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . tempFile . Chr(34), , Hide, headingBalconPID
        headingTTSRunning := true
    }
    
    return true
}

; FIXED: Play next chunk with proper loop support
PlayNextChunk(ttsType) {
    global loopChunkFiles, loopChunkMode, loopGapMs
    global balconPath, balconVoice, balconSpeed, balconPitch, balconVolume
    global balconPID, headingBalconPID, balconRunning, headingTTSRunning
    global currentChunkIndex, analyticalMode
    
    ; Check if we have more chunks
    if (currentChunkIndex >= loopChunkFiles.Length()) {
        ; No more chunks - check if loop mode is enabled
        if (loopChunkMode) {
            ; Restart from first chunk
            currentChunkIndex := 0
            ShowSmartTooltip("🔄 Looping chunks from beginning...", "LoopNotification", 800)
        } else {
            ; End of content
            return false
        }
    }
    
    chunkFile := loopChunkFiles[currentChunkIndex + 1]
    
    if (!FileExist(chunkFile)) {
        ShowSmartTooltip("❌ CHUNK FILE MISSING", "Debug", 1200)
        return false
    }
    
    ; Play the chunk
    if (ttsType = "note") {
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . chunkFile . Chr(34), , Hide, balconPID
        balconRunning := true
    } else if (ttsType = "heading") {
        Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . chunkFile . Chr(34), , Hide, headingBalconPID
        headingTTSRunning := true
    }
    
    currentChunkIndex++
    
    if (analyticalMode) {
        ShowSmartTooltip("🧩 CHUNK " . currentChunkIndex . "/" . loopChunkFiles.Length(), "Debug", 800)
    }
    
    return true
}

; FIXED: Cleanup that handles loop chunk mode
CleanupChunkFiles() {
    global loopChunkFiles, loopChunkMode, originalContentFile
    
    ; Delete all chunk files
    for index, file in loopChunkFiles {
        if (FileExist(file)) {
            FileDelete, %file%
        }
    }
    loopChunkFiles := []
    
    ; Delete master content file if it exists
    if (originalContentFile != "" && FileExist(originalContentFile)) {
        FileDelete, %originalContentFile%
        originalContentFile := ""
    }
    
    ; Reset chunk index
    global currentChunkIndex
    currentChunkIndex := 0
    loopChunkMode := false
}

; ===========================================================
; TEMPORARY FILE CLEANUP SYSTEM
; ===========================================================
; PURPOSE: Clean up temporary TTS files to prevent disk clutter
; STRATEGY: Regular cleanup + immediate cleanup when files are no longer needed

_CleanupTempFile:
    FileDelete, %A_Temp%\xmind_tts_*.txt
    
    ; === FIX: Aggressive cleanup when loop mode is disabled ===
    if (!loopMode) {
        Loop, Files, %A_Temp%\xmind_loop_note*.txt, F
        {
            FileDelete, %A_LoopFileLongPath%
        }
        Loop, Files, %A_Temp%\xmind_loop_heading*.txt, F
        {
            FileDelete, %A_LoopFileLongPath%
        }
    }
    
    ; (rest of the function remains the same)
    global currentNoteTTSFile, currentHeadingTTSFile, balconRunning, headingTTSRunning
    
    if (currentNoteTTSFile != "" && !balconRunning && FileExist(currentNoteTTSFile)) {
        FileDelete, %currentNoteTTSFile%
        currentNoteTTSFile := ""
    }
    
    if (currentHeadingTTSFile != "" && !headingTTSRunning && FileExist(currentHeadingTTSFile)) {
        FileDelete, %currentHeadingTTSFile%
        currentHeadingTTSFile := ""
    }
return

; ===========================================================
; NOTE TTS SYSTEM - CORE FUNCTIONS
; ===========================================================
; PURPOSE: Handle text-to-speech for note content
; FEATURES: Content detection, smart TTS selection, dual detection integration

; Get current heading for dual detection system
; REPLACE GetCurrentHeading() with this adaptive version:
GetCurrentHeading() {
    global baseCopyDelay, checkInterval, analyticalMode, dualDetectionEnabled
    
    ; Ultra-fast for background detection
    Clipboard := ""
    Sleep, 5
    Send, ^c
    Sleep, %baseCopyDelay%  ; 10ms base
    
    ; Quick progressive check (max 100ms for background)
    totalWaited := baseCopyDelay
    Loop, 20 {  ; Max 20 iterations = ~100ms max for background
        if (Clipboard != "") {
            headingText := Clipboard
            MarkClipboardContent(headingText)
            
            if (analyticalMode && dualDetectionEnabled) {
                ShowSmartTooltip("📝 BG: " . StrLen(headingText) . " chars in " . totalWaited . "ms", "Debug", 400)
            }
            return Trim(headingText)
        }
        Sleep, %checkInterval%
        totalWaited += checkInterval
    }
    return ""
}



; NEW: Get file size to bypass clipboard for extremely large content
GetNoteContentFromFile() {
    global analyticalMode
    
    ; Try to save note content directly to file
    tempNoteFile := A_Temp . "\xmind_note_content_" . A_TickCount . ".txt"
    FileDelete, %tempNoteFile%
    
    ; Use clipboard as intermediate but save to file immediately
    Clipboard := ""
    Sleep, 50
    
    Send, ^a
    Sleep, 200
    Send, ^c
    Sleep, 2000  ; Wait for large content
    
    if (Clipboard != "") {
        FileAppend, %Clipboard%, %tempNoteFile%
        Clipboard := ""
    }
    
    if (FileExist(tempNoteFile)) {
        FileRead, noteContent, %tempNoteFile%
        FileDelete, %tempNoteFile%
        
        if (analyticalMode) {
            ShowSmartTooltip("📁 FILE-BASED NOTE: " . StrLen(noteContent) . " chars", "Debug", 1500)
        }
        
        return Trim(noteContent)
    }
    
    return ""
}

; ===========================================================
; NOTE SIZE CHECKER
; ===========================================================
NoteIsLarge() {
    global largeContentThreshold
    
    ; Quick estimate: Select all and check clipboard size
    clipboardBackup := ClipboardAll
    Clipboard := ""
    Sleep, 20
    
    Send, ^a
    Sleep, 50
    Send, ^c
    Sleep, 100
    
    ClipWait, 100, 1
    size := StrLen(Clipboard)
    
    Clipboard := clipboardBackup
    clipboardBackup := ""
    Send, ^{Home}
    
    return (size > largeContentThreshold)
}

; ===========================================================
; NOTE CONTENT VIA FILE - Bypass clipboard for massive notes
; ===========================================================
GetNoteContentViaFile() {
    global analyticalMode
    
    ; Save note to file directly
    tempFile := A_Temp . "\xmind_note_temp_" . A_TickCount . ".txt"
    FileDelete, %tempFile%
    
    Send, ^a
    Sleep, 50
    Send, ^c
    Sleep, 2000  ; Wait for huge content
    
    if (Clipboard != "") {
        FileAppend, %Clipboard%, %tempFile%
    }
    
    ; Read back from file
    if (FileExist(tempFile)) {
        FileRead, content, %tempFile%
        FileDelete, %tempFile%
        
        if (analyticalMode) {
            ShowSmartTooltip("📁 File-mode note: " . StrLen(content) . " chars", "Debug", 1500)
        }
        
        return Trim(content)
    }
    
    return ""
}

; ===========================================================
; CLEANUP LOOP FILES
; ===========================================================
CleanupLoopFiles(ttsType := "") {
    global loopNoteFile, loopHeadingFile, analyticalMode
    global currentNoteContent, currentHeadingContent
    
    ; === FIX: Pattern-based cleanup for loop note files ===
    if (ttsType = "note" || ttsType = "") {
        ; Delete ALL loop note files in temp directory
        Loop, Files, %A_Temp%\xmind_loop_note*.txt, F
        {
            FileDelete, %A_LoopFileLongPath%
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Deleted: " . A_LoopFileName, "Debug", 500)
            }
        }
        
        ; Also clean the tracked file variable (if different)
        if (loopNoteFile != "" && FileExist(loopNoteFile)) {
            FileDelete, %loopNoteFile%
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Deleted tracked: " . loopNoteFile, "Debug", 500)
            }
        }
        loopNoteFile := ""
        currentNoteContent := ""
    }
    
    ; === FIX: Pattern-based cleanup for loop heading files ===
    if (ttsType = "heading" || ttsType = "") {
        ; Delete ALL loop heading files in temp directory
        Loop, Files, %A_Temp%\xmind_loop_heading*.txt, F
        {
            FileDelete, %A_LoopFileLongPath%
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Deleted: " . A_LoopFileName, "Debug", 500)
            }
        }
        
        ; Also clean the tracked file variable (if different)
        if (loopHeadingFile != "" && FileExist(loopHeadingFile)) {
            FileDelete, %loopHeadingFile%
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Deleted tracked: " . loopHeadingFile, "Debug", 500)
            }
        }
        loopHeadingFile := ""
        currentHeadingContent := ""
    }
}

; Main TTS function for note content
SpeakWithBalcon(text) {
    global balconPath, balconVoice, balconSpeed, balconPitch, balconVolume, balconRunning, balconPID
    global Message_NoText
    global headingTTSRunning  ; For mutual exclusion
    
    ; FIXED: Stop heading TTS if it's running (mutual exclusion)
    if (headingTTSRunning) {
        StopHeadingTTS()
        Sleep, 50  ; Give time for heading TTS to fully stop
    }
    
    if (text = "" || text = "`r`n" || text = "`n" || text = " ") {
        ShowSmartTooltip("❌ " . Message_NoText, "NoText", 1200)
        return false
    }
    
    ; Use smart TTS approach (now with hybrid direct/file-based logic)
    if (SpeakWithBalconSmart(text, "note")) {
        balconRunning := true
        
        ; IMMEDIATELY start dual detection system when TTS starts
        StartHeadingDetection()
        
        return true
    }
    
    return false
}

; Stop note TTS and cleanup
; FIXED: Cleanup with verification
; Stop note TTS and cleanup - ERROR-PROOF VERSION
; Stop note TTS and cleanup - ERROR-PROOF VERSION
; Stop note TTS and cleanup - GUARANTEED DEVICE RESTORE
; Stop note TTS - ONLY RESTORE DEVICE IF NOT IN LOOP MODE
; Stop note TTS - ALWAYS restores device (manual stop)
; Stop note TTS - ALWAYS restores device
; Stop note TTS - SETS MANUAL KILL FLAG
; Stop note TTS - CLEANS BOTH TYPES
; Stop note TTS with debounce
; =================================================================
; DEVICE SWITCHING IN STOP FUNCTIONS (ALREADY CORRECT)
; =================================================================

; Stop note TTS - ALWAYS restores device (for final stop)
; Stop note TTS - FIXED: Don't set balconRunning := false here, let timer handle it
; Stop note TTS - ALWAYS restores device (for final stop)
; FIXED: Audio lock support - skips device restore when locked
StopBalcon(silent := false) {
    global balconRunning, balconPID, currentNoteTTSFile, analyticalMode
    global CABLE_DEVICE, REAL_DEVICE, NIRCMD_PATH, loopMode
    global Message_TTSStop, ttsLocked, noteToggleEnabled, manualLoopKill
    global loopNoteFile, audioLockActive, isTransition  ; <-- ADDED for audio lock feature
    
    if (!balconRunning) {
        return
    }
    
    manualLoopKill := true
    
    ; Kill the process
    if (balconPID != 0) {
        Process, Close, %balconPID%
        Sleep, 20
    }
    ; RunWait (not Run) — must finish killing stray balcon.exe processes BEFORE
    ; we return, otherwise a transition that immediately launches a NEW balcon.exe
    ; (for heading TTS) can race with this taskkill and get killed by it right after starting.
    RunWait, taskkill /IM balcon.exe /F, , Hide
    
    ; Let timer handle state cleanup and device switching
    if (!silent && !isTransition) {
        ShowSmartTooltip("⏹️ " . Message_TTSStop, "TTSStop", 1200)
    }
    
    ; CRITICAL: Restore device ONLY if audio lock is NOT active AND not transitioning
    if (!audioLockActive && !isTransition) {
        Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
        Sleep, 50
    } else {
        ; Stay on CABLE despite stop
        if (analyticalMode) {
            ShowSmartTooltip("🔒 Audio lock - stay on CABLE (note TTS stopped)", "Debug", 400)
        }
    }
}


; Timer to detect when TTS finishes naturally
; Timer to detect when TTS finishes naturally
; FIXED: Modified timers for chunked loop support
; FIXED: Infinite loop for Note TTS - NO STOP CONDITIONS
; FIXED: Note TTS with loop counting
; Timer to detect when TTS finishes naturally
; Timer to detect when TTS finishes naturally - ALWAYS RESTORES REAL DEVICE
; Timer to detect when TTS finishes naturally - SEAMLESS LOOPING
; Timer to detect when TTS finishes naturally - WORKING GAP CONTROL
; Timer to detect when TTS finishes naturally - NO DEVICE SWITCHING IN LOOP
; Timer to detect when TTS finishes naturally - NO DEVICE SWITCHING IN LOOP
; Timer to detect when TTS finishes naturally - WORKING GAP CONTROL
; Timer for Note TTS - BULLETPROOF with gap state tracking
; Timer for Note TTS - PROTECTED from heading TTS interference
; Timer for Note TTS - FIXED: Removed blocking logic that prevented loop restart
; =================================================================
; DEVICE SWITCHING FIX FOR LOOP MODE
; =================================================================
; When Loop is ON:
; - Device switches to CABLE once when TTS starts, stays there forever
; - Device switches back to REAL only when TTS stops (manual or automatic)
; - NO device switching during loop gaps

; Timer for Note TTS - FIXED: No device switching during loop gaps
; Timer for Note TTS - FIXED: Shows finished message & restores device on dual-detection stop
; Timer for Note TTS - FIXED: Re-applies filter to original content on each loop
; Timer for Note TTS - FIXED: Re-processes with CURRENT speed on each loop
; Timer for Note TTS - FIXED: Audio lock support
_CheckTTSFinished:
    global balconRunning, balconPID, balconProcessHandle, Message_TTSFinished
    global currentNoteTTSFile, currentNoteContent, currentNoteOriginalContent
    global loopMode, loopNoteFile, loopGapMs, CABLE_DEVICE, NIRCMD_PATH
    global analyticalMode, manualLoopKill, isInGapPhase, activeTTSType
    global REAL_DEVICE, speedMultiplier, suppressNumbersEnabled, noteWordsPerLine
    global maxHeadingLevels, f6Mode, audioLockActive, isTransition
    
    if (!balconRunning || balconPID = 0) {
        return
    }
    
    ; FIX: Handle-based check instead of "Process, Exist, %balconPID%".
    ; A PID-only check can be fooled once Windows reuses a closed balcon.exe's
    ; PID for an unrelated process - that used to make the loop silently freeze
    ; after a few restarts. Checking the handle opened at launch time is immune to that.
    if (!HasBalconProcessExited(balconProcessHandle)) {
        return  ; Still genuinely running
    }
    CloseBalconHandle(balconProcessHandle)
    
    if (true) {  ; Process ended
        
        if (manualLoopKill) {
            manualLoopKill := false
            isInGapPhase := false
            activeTTSType := ""
            balconRunning := false
            currentNoteContent := ""
            
            ; Switch back to REAL on manual stop (only if NOT audio locked AND NOT transitioning)
            if (!audioLockActive && !isTransition) {
                Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
                Sleep, 50
            } else {
                if (analyticalMode) {
                    ShowSmartTooltip("🔒 Staying on CABLE (transition/lock)", "Debug", 400)
                }
            }
            
            if (analyticalMode) {
                ShowSmartTooltip("🛑 Manual stop detected", "Debug", 1200)
            }
            return
        }
        
        
        ; FIX: Do NOT gate on FileExist(loopNoteFile) here. The temp file is only a
        ; transport for balcon and can be legitimately absent for a brief instant
        ; (another timer's cleanup pass, filesystem/AV latency, etc.) without that
        ; meaning the user wants the loop to stop. The only real "stop" signals are
        ; manualLoopKill (explicit stop), loopMode being off, or having no content
        ; left to speak. If the file happens to be missing, the rewrite block below
        ; already deletes/recreates it unconditionally, so it self-heals instead of
        ; ending the loop.
        if (loopMode && currentNoteOriginalContent != "") {
            if (analyticalMode) {
                ShowSmartTooltip("⏱️ Gap: " . loopGapMs . "ms", "Debug", 800)
            }
            
            isInGapPhase := true
            activeTTSType := "note"
            Sleep, % loopGapMs
            isInGapPhase := false
            
            if (manualLoopKill || !loopMode || currentNoteOriginalContent = "") {
                manualLoopKill := false
                activeTTSType := ""
                balconRunning := false
                return
            }
            
            ShowSmartTooltip("🔄 Looping note TTS...", "LoopNotification", 1000)
            
            reprocessedContent := currentNoteOriginalContent
            
            if (speedMultiplier > 1.0) {
                reprocessedContent := PreprocessTextForSpeed(reprocessedContent, speedMultiplier)
            }
            
            if (suppressNumbersEnabled) {
                reprocessedContent := StripNumbersFromText(reprocessedContent)
            }
            
            if (noteWordsPerLine < 0) {
                reprocessedContent := FormatWordsPerLine(reprocessedContent, noteWordsPerLine)
            }
            
            if (f6Mode = "level" && maxHeadingLevels > 0) {
                ; Optional: Add note-specific filtering if needed
            }
            
            ; ========== FIX: Robust file rewrite with verification ==========
            if (loopNoteFile = "" || !InStr(loopNoteFile, "persistent")) {
                loopNoteFile := A_Temp . "\xmind_loop_note_persistent.txt"
            }
            
            FileDelete, %loopNoteFile%
            Loop, 30 {
                if (!FileExist(loopNoteFile))
                    break
                Sleep, 5
            }
            
            FileAppend, %reprocessedContent%, %loopNoteFile%
            
            fileReady := false
            Loop, 30 {
                if (FileExist(loopNoteFile)) {
                    FileGetSize, fileSize, %loopNoteFile%
                    if (fileSize > 0) {
                        fileReady := true
                        break
                    }
                }
                Sleep, 5
            }
            
            if (!fileReady) {
                if (analyticalMode) {
                    ShowSmartTooltip("⚠️ File write failed, retrying...", "Debug", 800)
                }
                FileDelete, %loopNoteFile%
                Sleep, 50
                FileAppend, %reprocessedContent%, %loopNoteFile%
                Sleep, 50
                if (FileExist(loopNoteFile)) {
                    FileGetSize, fileSize, %loopNoteFile%
                    if (fileSize > 0) {
                        fileReady := true
                    }
                }
            }
            
            if (!fileReady) {
                if (analyticalMode) {
                    ShowSmartTooltip("❌ File persistently unavailable, skipping iteration", "Debug", 1200)
                }
                return
            }
            
            ; ========== FIX: NO device switch on loop restart ==========
            ; Device is ALREADY on CABLE from initial TTS start.
            ; Stay on CABLE during all loop iterations.
            ; Only switch back to REAL on manual stop (above) or loop termination (below).
            if (analyticalMode) {
                ShowSmartTooltip("🔁 Loop restart (no device switch)", "Debug", 400)
            }
            
            Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . loopNoteFile . Chr(34), , Hide, balconPID
            balconProcessHandle := OpenBalconHandle(balconPID)
            balconRunning := true
            return
        }
        
        ; Loop is OFF or conditions failed - TTS finished naturally
        ; Switch back to REAL (only if NOT audio locked)
        if (!audioLockActive) {
            Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
            Sleep, 50
        } else {
            if (analyticalMode) {
                ShowSmartTooltip("🔒 Audio lock - stay on CABLE (finished)", "Debug", 400)
            }
        }
        
        isInGapPhase := false
        activeTTSType := ""
        balconRunning := false
        currentNoteContent := ""
        currentNoteOriginalContent := ""
        
        if (!loopMode) {
            if (loopNoteFile != "" && FileExist(loopNoteFile)) {
                FileDelete, %loopNoteFile%
                loopNoteFile := ""
            }
            if (currentNoteTTSFile != "" && FileExist(currentNoteTTSFile)) {
                FileDelete, %currentNoteTTSFile%
                currentNoteTTSFile := ""
            }
        }
        
        StopHeadingDetection()
        
        if (!noteToggleEnabled || !ttsLocked) {
            CleanupClipboard()
        }
        
        balconPID := 0
        ShowSmartTooltip("✅ " . Message_TTSFinished, "TTSFinished", 1200)
    }
return


; ===========================================================
; HEADING TTS SYSTEM - MIND MAP STRUCTURE READING
; ===========================================================
; PURPOSE: Read entire branch structure with indentation levels
; FEATURES: Level announcement, tab detection, multiple numbering systems
; USAGE: Select any topic and press Middle Mouse Button

; Check if a heading is currently selected
IsHeadingSelected() {
    global headingTTSCopyDelay
    
    clipboardBackup := ClipboardAll
    Clipboard := ""
    
    ; Try to copy the selected heading/branch
    Send, ^c
    Sleep, %headingTTSCopyDelay%
    
    hasContent := false
    ClipWait, 0.5, 1
    if (Clipboard != "" && Clipboard != "`r`n" && Clipboard != "`n" && Clipboard != " ") {
        hasContent = true
    }
    
    Clipboard := clipboardBackup
    clipboardBackup := ""
    
    return hasContent
}

; FIXED: Get heading structure with better clipboard clearing
; Get the entire branch structure with hierarchy
; FIXED: Reliable heading extraction for massive mindmaps
; FIXED: Robust heading extraction with extended timeout
; FIXED: Adaptive timeout based on content size
; FIXED: Ultra-fast heading extraction (no hanging waits)
; FIXED: Ultra-robust heading extraction for massive mindmaps
; FIXED: Ultra-fast heading extraction - SINGLE Ctrl+C only
; FIXED: Ultra-fast heading extraction with emergency file fallback
; ULTRA-MINIMAL: Only Ctrl+C, no selection automation
; FIXED: Reliable heading extraction with extended timeout for large maps
; FIXED: Progressive clipboard checking for massive mind maps
; NEW: Adaptive heading extraction with size-based timing
GetHeadingBranchStructureAdaptive() {
    global baseCopyDelay, maxWaitTime, checkInterval, analyticalMode, dualDetectionEnabled
    
    ; PHASE 1: Ultra-fast initial copy
    Clipboard := ""
    Sleep, 5              ; Minimal clear time
    Send, ^c
    Sleep, %baseCopyDelay% ; 10ms base delay
    
    ; PHASE 2: Progressive detection with early exit
    headingText := ""
    totalWaited := baseCopyDelay
    lastSize := 0
    stableCount := 0
    
    Loop {
        currentSize := StrLen(Clipboard)
        
        ; DETECTION LOGIC:
        ; 1. If we have content and it's stable (not growing), we're done
        ; 2. If content is still growing, keep waiting
        ; 3. If max time reached, use what we have
        
        if (currentSize > 0) {
            ; Content detected - check if it's still growing
            if (currentSize = lastSize) {
                stableCount++
                ; If stable for 3 checks (~15ms), content is complete
                if (stableCount >= 3) {
                    headingText := Clipboard
                    break
                }
            } else {
                ; Content still growing - reset stability counter
                stableCount := 0
                lastSize := currentSize
            }
        }
        
        ; Check timeout
        if (totalWaited >= maxWaitTime) {
            headingText := Clipboard
            if (analyticalMode) {
                ShowSmartTooltip("⚠️ Max wait reached: " . currentSize . " chars", "Debug", 1200)
            }
            break
        }
        
        ; Adaptive sleep based on content size
        ; Small content (<1KB): check every 5ms
        ; Large content (>50KB): check every 50ms (growing, needs more time)
        if (currentSize > 0 && currentSize < 1000) {
            Sleep, %checkInterval%      ; 5ms for small content
            totalWaited += checkInterval
        } else if (currentSize >= 1000 && currentSize < 50000) {
            Sleep, 20                   ; 20ms for medium content
            totalWaited += 20
        } else {
            Sleep, 50                   ; 50ms for large/huge content
            totalWaited += 50
        }
    }
    
    ; Mark and return
    if (headingText != "") {
        MarkClipboardContent(headingText)
        if (analyticalMode && dualDetectionEnabled) {
            ShowSmartTooltip("✓ HEADING: " . StrLen(headingText) . " chars in " . totalWaited . "ms", "Debug", 1000)
        }
    }
    
    return Trim(headingText)
}

; ===========================================================
; MODIFIED: Toggle Test Mode (renamed from Index Mode)
; ===========================================================
ToggleIndexMode:
    global specificIndexModeEnabled
    
    specificIndexModeEnabled := !specificIndexModeEnabled
    
    ; Clear radio states when entering test mode
    if (specificIndexModeEnabled) {
        Loop, 200 {
            headingFilterRadioStates[A_Index] := 0
            radioVar := "headingFilterRadioBox" . A_Index
            if (IsObject(%radioVar%)) {
                GuiControl,, %radioVar%, 0
            }
        }
    }
    
    UpdateHeadingFilterControls()
    
    ShowSmartTooltip(specificIndexModeEnabled ? "🔢 Test Mode: ON" : "📝 Normal Mode: ON", "Debug", 1500)
return
; ===========================================================
; MAX LEVELS FILTER - Filter heading structure by max level
; ===========================================================
; ===========================================================
; MODIFIED: Filter heading structure by max level AND per-level limits
; ===========================================================
; ===========================================================
; MODIFIED: Filter heading structure with per-level limits
; ===========================================================
; ===========================================================
; CORRECTED: Filter heading structure by max level AND per-parent limits
; ===========================================================
; ===========================================================
; BULLETPROOF: Filter heading structure with per-parent limits
; ===========================================================
; ===========================================================
; MODIFIED: FilterHeadingByMaxLevels - Radio box integration
; ===========================================================
FilterHeadingByMaxLevels(headingText) {
    global maxHeadingLevels, headingFilterInputValues
    global f4f5OverrideActive, f4f5OverrideLevel, f4f5CurrentHeadingNum
    global headingFilterCheckboxes, headingFilterLevelCount
    global headingFilterRadioStates, specificIndexModeEnabled
    global analyticalMode
    
    if (headingText = "")
        return headingText
    
    ; === INDEX MODE LOGIC ===
    if (specificIndexModeEnabled) {
        
        ; Get all checked levels and their indices
        checkedLevels := []
        Loop, % headingFilterLevelCount {
            if (headingFilterCheckboxes[A_Index]) {
                levelNum := A_Index
                indexValue := headingFilterInputValues[levelNum]
                
                ; Apply F4/F5 override
                if (f4f5OverrideActive && levelNum = f4f5OverrideLevel && f4f5CurrentHeadingNum > 0) {
                    indexValue := f4f5CurrentHeadingNum
                }
                
                checkedLevels.Push({level: levelNum, index: indexValue})
            }
        }
        
        ; If no levels checked, return empty
        if (checkedLevels.Length() = 0)
            return ""
        
        ; Sort checked levels by level number (ascending)
        sortedLevels := []
        for i, item in checkedLevels {
            sortedLevels.Push(item)
        }
        
        ; Simple bubble sort
        Loop, % sortedLevels.Length() - 1 {
            i := A_Index
            Loop, % sortedLevels.Length() - i {
                j := A_Index + i - 1
                if (sortedLevels[j].level > sortedLevels[j+1].level) {
                    temp := sortedLevels[j]
                    sortedLevels[j] := sortedLevels[j+1]
                    sortedLevels[j+1] := temp
                }
            }
        }
        
        ; Debug info
        if (analyticalMode) {
            debugMsg := "Index Mode - Checked Levels:`n"
            for i, target in sortedLevels {
                debugMsg .= "Level " . target.level . ": Index " . target.index . "`n"
            }
            ShowSmartTooltip(debugMsg, "Debug", 2000)
        }
        
        lines := StrSplit(headingText, "`n", "`r")
        result := ""
        
        ; Track current path and counters for each parent branch
        nameStack := []
        pathStack := []
        counters := {}
        
        ; For hierarchical search
        currentFoundLevels := {}
        
        for idx, line in lines {
            line := StrReplace(line, "`r", "")
            line := RTrim(line)
            
            if (line = "")
                continue
            
            ; Calculate indent level
            indentLevel := 0
            Loop, Parse, line
            {
                if (A_LoopField = "`t")
                    indentLevel++
                else
                    break
            }
            
            currentLevel := indentLevel + 1
            headingName := SubStr(line, indentLevel + 1)
            
            ; Update stacks
            if (indentLevel = 0) {
                ; Level 1 - reset everything
                nameStack := [headingName]
                pathStack := [headingName]
                counters := {}
                currentFoundLevels := {}
            } else {
                ; Ensure stacks are right size
                if (nameStack.Length() < currentLevel)
                    nameStack.Push("")
                if (pathStack.Length() < currentLevel)
                    pathStack.Push("")
                
                nameStack[currentLevel] := headingName
                nameStack.Length := currentLevel
                
                ; Build current full path
                currentPath := ""
                Loop, % currentLevel {
                    i := A_Index
                    currentPath .= (currentPath ? ">" : "") . nameStack[i]
                }
                pathStack[currentLevel] := currentPath
                pathStack.Length := currentLevel
            }
            
            ; Get parent path
            parentPath := ""
            if (currentLevel = 1) {
                parentPath := "ROOT"
            } else {
                parentPath := pathStack[currentLevel - 1]
            }
            
            ; Build counter key
            counterKey := parentPath . "|INDEX|" . currentLevel
            
            ; Initialize and increment counter
            if (!counters.HasKey(counterKey))
                counters[counterKey] := 0
            counters[counterKey] += 1
            currentCount := counters[counterKey]
            
            ; Check if this level is in our targets
            isTargetLevel := false
            targetIndex := 0
            for i, target in sortedLevels {
                if (target.level = currentLevel) {
                    isTargetLevel := true
                    targetIndex := target.index
                    break
                }
            }
            
            ; If this is a target level, check if we're at the right index
            if (isTargetLevel) {
                ; Check if index matches (or if index is 0, always match)
                if (targetIndex = 0 || currentCount = targetIndex) {
                    currentFoundLevels[currentLevel] := true
                    
                    ; Check if we have found all shallower target levels
                    allShallowerFound := true
                    for i, target in sortedLevels {
                        if (target.level < currentLevel) {
                            if (!currentFoundLevels.HasKey(target.level)) {
                                allShallowerFound := false
                                break
                            }
                        }
                    }
                    
                    ; If all shallower levels found and this is the deepest target
                    if (allShallowerFound && currentLevel = sortedLevels[sortedLevels.Length()].level) {
                        result .= line . "`n"
                        
                        ; If specific index (not 0), we're done
                        if (targetIndex > 0) {
                            break
                        }
                    }
                } else {
                    ; Wrong index - clear found flag for this level
                    currentFoundLevels.Delete(currentLevel)
                }
            }
        }
        
        return RTrim(result, "`n")
    }
    
    ; === STANDARD MODE WITH RADIO BUTTON SUPPORT ===
    lines := StrSplit(headingText, "`n", "`r")
    filteredLines := []
    
    ; === PER-PARENT COUNTERS ===
    counters := {}          ; For standard mode: parentPath|level -> count of included items
    radioSeenCounters := {} ; For radio mode: parentPath|level -> count of seen items (to find the Nth)
    
    ; === TRACK SKIPPED ITEMS BY FULL PATH ===
    skippedPaths := {}
    
    ; === CURRENT PATH STACK ===
    nameStack := []      ; Just the heading names
    pathStack := []      ; Full paths including current heading
    
    for index, line in lines {
        line := StrReplace(line, "`r", "")
        trimmedLine := Trim(line)
        if (trimmedLine = "")
            continue
        
        ; Calculate indent level
        indentLevel := 0
        Loop, Parse, line
        {
            if (A_LoopField = "`t")
                indentLevel++
            else
                break
        }
        
        levelNum := indentLevel + 1
        
        ; Skip if beyond max heading levels
        if (maxHeadingLevels > 0 && levelNum > maxHeadingLevels)
            continue
        
        ; Get heading text without tabs
        headingTextOnly := SubStr(line, indentLevel + 1)
        
        ; Update stacks
        if (indentLevel = 0) {
            ; Level 1 - start new stacks
            nameStack := [headingTextOnly]
            pathStack := [headingTextOnly]
        } else {
            ; Ensure stacks are right size
            if (nameStack.Length() < levelNum)
                nameStack.Push("")
            if (pathStack.Length() < levelNum)
                pathStack.Push("")
            
            nameStack[levelNum] := headingTextOnly
            nameStack.Length := levelNum
            
            ; Build current full path
            currentPath := ""
            Loop, % levelNum {
                i := A_Index
                currentPath .= (currentPath ? ">" : "") . nameStack[i]
            }
            pathStack[levelNum] := currentPath
            pathStack.Length := levelNum
        }
        
        currentFullPath := pathStack[levelNum]
        
        ; === CHECK IF ANY ANCESTOR WAS SKIPPED ===
        skipDueToAncestor := false
        for i, ancestorPath in pathStack {
            if (i < levelNum && skippedPaths.HasKey(ancestorPath)) {
                skipDueToAncestor := true
                break
            }
        }
        
        if (skipDueToAncestor) {
            skippedPaths[currentFullPath] := true
            continue
        }
        
        ; === CHECK IF LEVEL IS ENABLED (Checkbox) ===
        ; Level 1 is always enabled
        if (levelNum > 1 && !headingFilterCheckboxes[levelNum]) {
            skippedPaths[currentFullPath] := true
            continue
        }
        
        ; === GET LEVEL LIMIT ===
        levelLimit := headingFilterInputValues.HasKey(levelNum) ? headingFilterInputValues[levelNum] : 0
        
        ; Apply F4/F5 override
        if (f4f5OverrideActive && levelNum = f4f5OverrideLevel && f4f5CurrentHeadingNum > 0) {
            levelLimit := f4f5CurrentHeadingNum
        }
        
        ; === CHECK RADIO BUTTON STATE ===
        isRadio := headingFilterRadioStates.HasKey(levelNum) ? headingFilterRadioStates[levelNum] : false
        
        ; Get parent path for counter keys
        parentPath := ""
        if (levelNum = 1) {
            parentPath := "ROOT"
        } else {
            ; Get the path to the parent (one level up)
            parentPath := pathStack[levelNum - 1]
        }
        
        shouldSkip := false
        
        ; === APPLY LIMITS BASED ON RADIO STATE ===
        if (isRadio) {
            ; === RADIO MODE: Include only the specific Nth item ===
            
            ; Build radio counter key
            radioCounterKey := parentPath . "|RADIO|" . levelNum
            
            ; Initialize and increment seen counter for radio mode
            if (!radioSeenCounters.HasKey(radioCounterKey))
                radioSeenCounters[radioCounterKey] := 0
            radioSeenCounters[radioCounterKey] += 1
            currentRadioCount := radioSeenCounters[radioCounterKey]
            
            ; Radio mode logic:
            ; If levelLimit = 0: Include all items (treat like standard mode with no limit)
            ; If levelLimit > 0: Include only the Nth item where N = levelLimit
            if (levelLimit > 0 && currentRadioCount != levelLimit) {
                shouldSkip := true
            }
            ; Note: If levelLimit = 0, don't skip (include all)
            
        } else {
            ; === STANDARD MODE: Per-parent limits ===
            if (levelLimit > 0) {
                ; Build standard counter key
                counterKey := parentPath . "|STANDARD|" . levelNum
                
                ; Initialize counter if needed
                if (!counters.HasKey(counterKey))
                    counters[counterKey] := 0
                
                ; Check if limit reached
                if (counters[counterKey] >= levelLimit) {
                    shouldSkip := true
                }
            }
            ; If levelLimit = 0, always include (no limit)
        }
        
        if (shouldSkip) {
            skippedPaths[currentFullPath] := true
            continue
        }
        
        ; === INCLUDE HEADING ===
        filteredLines.Push(line)
        
        ; Update appropriate counter
        if (isRadio) {
            ; Radio mode: We've already updated the radioSeenCounters above
            ; If we're including this item in radio mode, we don't need additional counters
        } else if (levelLimit > 0) {
            ; Standard mode: Update the inclusion counter
            counterKey := parentPath . "|STANDARD|" . levelNum
            counters[counterKey] := (counters.HasKey(counterKey) ? counters[counterKey] : 0) + 1
        }
    }
    
    ; Build final text
    filteredText := ""
    for index, line in filteredLines {
        filteredText .= line . "`n"
    }
    
    return RTrim(filteredText, "`n")
}


; ===========================================================
; HEADING FILTER GUI SYSTEM
; ===========================================================
; Creates a floating window for configuring per-level heading limits

; ===========================================================
; MODIFIED: Create Heading Filter GUI - Remove old buttons
; ===========================================================
; === MODIFIED: CreateHeadingFilterGUI ===
CreateHeadingFilterGUI() {
    global headingFilterGUIActive, headingFilterGUIVisible, headingFilterLevelCount
    global headingFilterCheckboxes, headingFilterInputValues, maxHeadingLevels
    global f4f5OverrideActive, f4f5OverrideLevel, f4f5CurrentHeadingNum
    global specificIndexModeEnabled
    
    ; Initialize arrays if empty
    if (headingFilterCheckboxes.Length() = 0) {
        Loop, 200 {
            headingFilterCheckboxes.Push(true)
            headingFilterInputValues.Push(0)
        }
    }
    
    headingFilterCheckboxes[1] := true
    headingFilterInputValues[1] := 0
    
    if (maxHeadingLevels = 0) {
        Loop, %headingFilterLevelCount% {
            headingFilterCheckboxes[A_Index] := true
        }
    }
    
    f4f5OverrideActive := false
    f4f5OverrideLevel := 2
    f4f5CurrentHeadingNum := 0
    
    if (!headingFilterGUIActive) {
        Gui, HeadingFilter:New, +AlwaysOnTop +Resize -MaximizeBox, Heading Level Filter Config
        headingFilterGUIActive := true
    }
    
    headingFilterUserClosed := false
    
    ; FIXED: Call the correct function name
    UpdateHeadingFilterControls()
}

; === MODIFIED: UpdateHeadingFilterControls with Index Mode ===
; ===========================================================
; BLACK-THEMED, RESIZABLE GUI WITH SPINBOXES & RADIOBOXES
; ===========================================================
; ===========================================================
; COMPLETE GUI FUNCTION
; ===========================================================
; ===========================================================
; FINAL: UpdateHeadingFilterControls() with BLACK spinbox numbers
; ===========================================================
UpdateHeadingFilterControls() {
    global headingFilterGUIActive, headingFilterLevelCount, currentHeadingFilterPage, totalHeadingFilterPages
    global headingFilterCheckboxes, headingFilterInputValues, maxHeadingLevels
    global LevelCountDD, ManualLevelInputCB, levelsPerPage, f4f5OverrideLevel, f4f5OverrideActive
    global headingFilterGUIVisible, specificIndexModeEnabled, f4f5CurrentHeadingNum
    global lastRadioChecked := {}
    
    if (!headingFilterGUIActive)
        return
    
    ; Fixed size window (maximize disabled)
    Gui, HeadingFilter:Destroy
    Gui, HeadingFilter:New, +AlwaysOnTop -MaximizeBox, Heading Level Filter Config
    Gui, HeadingFilter:Color, 8EB9E6
    
    ; === TEST MODE BUTTON ===
    btnColor := specificIndexModeEnabled ? "c00AA00" : "c666666"
    btnText := specificIndexModeEnabled ? "Test Mode: ON" : "Test Mode: OFF"
    Gui, HeadingFilter:Add, Button, x10 y25 w90 h25 gToggleIndexMode %btnColor%, %btnText%
    
    ; === TOTAL LEVELS SECTION ===
    Gui, HeadingFilter:Add, GroupBox, x110 y10 w300 h45 c3333FF Background8EB9E6, Total Levels
    Gui, HeadingFilter:Add, Text, x120 y28 w80 h20 Right BackgroundTrans, Total Levels:
    
    levelOptions := ""
    Loop, 200 {
        levelOptions .= (A_Index = 1 ? A_Index : "|" . A_Index)
    }
    
    Gui, HeadingFilter:Add, ComboBox, x+5 y25 w80 h150 vLevelCountDD gLevelCountDDChange, %levelOptions%
    GuiControl, ChooseString, LevelCountDD, % headingFilterLevelCount
    
    Gui, HeadingFilter:Add, CheckBox, x+15 y25 w120 h25 vManualLevelInputCB Checked Disabled BackgroundTrans, Use dropdown (1-200)
    
    ; === F4/F5 CONTROL SECTION ===
    Gui, HeadingFilter:Add, Text, x+10 y28 w60 h20 Right BackgroundTrans, Use F4/F5:
    Gui, HeadingFilter:Add, CheckBox, x+5 y25 w20 h20 vF4F5OverrideCB gF4F5OverrideChange BackgroundTrans
    
    Gui, HeadingFilter:Add, Text, x+10 y28 w80 h20 Right BackgroundTrans, to Control Level:
    
    if (f4f5OverrideLevel < 2) {
        f4f5OverrideLevel := 2
    }
    
    ; SPINBOX for Control Level (Edit + UpDown)
    Gui, HeadingFilter:Add, Edit, x+5 y25 w50 h20 vF4F5OverrideLevel gF4F5LevelChange Number, % f4f5OverrideLevel
    Gui, HeadingFilter:Add, UpDown, x+0 y25 w16 h20 Range2-200, % f4f5OverrideLevel
    
    ; === RESET BUTTON ===
    Gui, HeadingFilter:Add, Button, x10 y55 w80 h25 gResetAllLevelInputs, Reset All
    
    ; === PAGINATION CONTROLS ===
    if (headingFilterLevelCount > levelsPerPage) {
        totalHeadingFilterPages := Ceil(headingFilterLevelCount / levelsPerPage)
        
        Gui, HeadingFilter:Add, Button, x220 y70 w30 h25 vPrevPageBtn gHeadingFilterPrevPage, ←
        
        pageLabelX := 250
        Gui, HeadingFilter:Add, Text, x%pageLabelX% y72 w100 h20 Center BackgroundTrans, Page %currentHeadingFilterPage% of %totalHeadingFilterPages%
        
        nextBtnX := 350
        Gui, HeadingFilter:Add, Button, x%nextBtnX% y70 w30 h25 vNextPageBtn gHeadingFilterNextPage, →
        
        gridStartY := 110
    } else {
        totalHeadingFilterPages := 1
        currentHeadingFilterPage := 1
        gridStartY := 110
    }
    
    ; === GRID HEADERS ===
    headerY := gridStartY - 15
    Gui, HeadingFilter:Add, Text, x10 y%headerY% w15 h20 Center BackgroundTrans, R1
    Gui, HeadingFilter:Add, Text, x+55 w20 h20 Center BackgroundTrans, Lvl
    Gui, HeadingFilter:Add, Text, x+1 w100 h20 Center BackgroundTrans, σ
    
    ; Grid layout
    colsPerRow := 4
    cellWidth := 155
    cellHeight := 85
    cellSpacingX := 5
    cellSpacingY := 5
    
    while (headingFilterCheckboxes.Length() < headingFilterLevelCount) {
        headingFilterCheckboxes.Push(true)
        headingFilterInputValues.Push(0)
    }
    
    if (maxHeadingLevels = 0) {
        Loop, %headingFilterLevelCount% {
            headingFilterCheckboxes[A_Index] := true
        }
    }
    
    startLevel := (currentHeadingFilterPage - 1) * levelsPerPage + 1
    endLevel := Min(currentHeadingFilterPage * levelsPerPage, headingFilterLevelCount)
    
    levelsThisPage := endLevel - startLevel + 1
    totalRows := Ceil(levelsThisPage / colsPerRow)
    totalGridHeight := (totalRows * (cellHeight + cellSpacingY)) + 40
    
    Loop, %levelsThisPage% {
        levelNum := startLevel + A_Index - 1
        
        col := Mod(A_Index - 1, colsPerRow)
        row := Floor((A_Index - 1) / colsPerRow)
        
        xPos := 15 + (col * (cellWidth + cellSpacingX))
        yPos := gridStartY + (row * (cellHeight + cellSpacingY))
        
        Gui, HeadingFilter:Add, GroupBox, x%xPos% y%yPos% w%cellWidth% h%cellHeight% c3333FF Background8EB9E6
        
        cellPadding := 10
        contentWidth := cellWidth - (cellPadding * 2)
        
        ; RADIOBOX (top-left) - HIDDEN when Test Mode is ON
        if (levelNum > 1 && !specificIndexModeEnabled) {
            radioX := xPos + cellPadding
            radioY := yPos + cellPadding
            radioVar := "headingFilterRadioBox" . levelNum
            Gui, HeadingFilter:Add, Radio, x%radioX% y%radioY% w15 h15 v%radioVar% gHeadingFilterRadioBoxChange BackgroundTrans, 
        }
        
        ; LEVEL NUMBER (top-middle) - BIGGER FONT
        Gui, HeadingFilter:Font, s13 bold
        levelX := xPos + (cellWidth / 2) - 20
        levelY := yPos + cellPadding
        Gui, HeadingFilter:Add, Text, x%levelX% y%levelY% w50 h30 Center BackgroundTrans, %levelNum%
        Gui, HeadingFilter:Font  ; Reset to default
        
        ; CHECKBOX (top-right)
        checkboxX := xPos + cellWidth - cellPadding - 20
        checkboxY := yPos + cellPadding
        checkboxVar := "headingFilterCB" . levelNum
        
        if (maxHeadingLevels = 0 || levelNum <= maxHeadingLevels) {
            headingFilterCheckboxes[levelNum] := true
            checkedState := "Checked"
        } else {
            headingFilterCheckboxes[levelNum] := false
            checkedState := ""
        }
        
        disabledState := (levelNum = 1) ? "Disabled" : ""
        
        if (levelNum = 1) {
            Gui, HeadingFilter:Add, CheckBox, x%checkboxX% y%checkboxY% w20 h20 v%checkboxVar% %checkedState% %disabledState% BackgroundTrans, 
        } else {
            Gui, HeadingFilter:Add, CheckBox, x%checkboxX% y%checkboxY% w20 h20 v%checkboxVar% gHeadingFilterCheckboxChange %checkedState% %disabledState% BackgroundTrans, 
        }
        
        ; CONTENT
        if (levelNum = 1) {
            messageX := xPos + cellPadding
            messageY := yPos + 30
            messageWidth := contentWidth
            Gui, HeadingFilter:Add, Text, x%messageX% y%messageY% w%messageWidth% h30 Center BackgroundTrans, Level 1`n(Always On)
        } else {
            ; LIMIT LABEL (above spinbox)
            labelX := xPos + cellPadding
            labelY := yPos + 45
            labelWidth := contentWidth
            Gui, HeadingFilter:Add, Text, x%labelX% y%labelY% w%labelWidth% h15 c666666 Center BackgroundTrans, Limit
            
            ; SPINBOX (edit control)
            spinX := xPos + cellPadding
            spinY := yPos + 60
            spinVar := "headingFilterSpin" . levelNum
            
            currentValue := headingFilterInputValues[levelNum]
            
            Gui, HeadingFilter:Add, Edit, x%spinX% y%spinY% w%contentWidth% h20 v%spinVar% gHeadingFilterSpinChange Number, %currentValue%
            
            ; UpDown control
            Gui, HeadingFilter:Add, UpDown, x+0 y%spinY% w16 h20 Range0-1000, %currentValue%
        }
    }
    
    instructionY := gridStartY + totalGridHeight - 35
    
    Gui, HeadingFilter:Add, Text, x10 y%instructionY% w650 h350 c4F81B0 BackgroundTrans
        , `n📖 INSTRUCTIONS:`n`n1. RADIOBOX(circular): This is a condition and It will cause the heading tts to read a single heading/item(limit value) of a lvl, it is meant for creating an address to a branch or a part of a mindmap or just skipping the before and after items/headings and reading only a single item in a level. You can skip the unwanted part of a mindmap and reach directly the part of the mindmap, that u wanna learn, using this feature.`n`n2. CHECKBOX(square): This enables the levels to be read. The more the, levels, checkboxes gets checked the more the levels will be read by the heading tts, however, if u chose 6lvls then it will read 6lvls starting from lvl1. `n`n3. SPINBOX(number box): Limit (0= Read All, N=Specific) - Scroll to adjust; Basically, this options allows you to read  how much headings/item in each lvl.`n`n4. F4/F5(checkbox~top-right): it is meant to control a limit value of a lvl(Control Level[value]) and once it is checked then u can use F4 and F5 to - and + the limit value of a level that you selected in Control level spinbox/input place.Try using this when Loop: ON.`n  - Control level(numberbox~top-right): It has an inputbox/spinbox and if u wanna control a level headings/items(to be read) using F4/F5 then just change the value within the spinbox/inputbox to that level. If u wanna control headings/items(to be read) at lvl4 using F4/F5 then just change the value within the inputbox/spinbox into 4.`n`n5. Test Mode: It is meant to test you regarding the pattern of a mindmap. let say what is the heading name at: lvl2[4], lvl3[7], lvl4[5], lvl5[2]? Once the settings are selected and then guess and then start the heading tts to see if you get it right. `n - Test Mode: ON will read the heading name that is at item 2 in lvl5 that is under item 5 of lvl4 that is under item 7 of lvl3 that is under item 4 of lvl2 that is under item1 lvl1. It will read a single heading ONLY. Just experiment.
    
    windowWidth := 680
    contentHeight := instructionY + 300
    
    ; FIXED SIZE (maximize disabled)
    Gui, HeadingFilter:Show, w%windowWidth% h%contentHeight%
    
    headingFilterGUIVisible := true
    if (f4f5OverrideActive) {
        SetTimer, _LiveReloadF4F5Control, 100
    }
}

; ===========================================================
; EVENT HANDLERS
; ===========================================================

HeadingFilterSpinChange:
    GuiControlGet, newValue,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterSpin")
    
    ; ENFORCE MINIMUM 1 for radio-checked levels (same approach as F4F5LevelChange)
    if (headingFilterRadioStates[levelNum] = 1 && newValue < 1) {
        newValue := 1
        GuiControl,, %A_GuiControl%, 1
    }
    
    if (newValue = "" || newValue < 0)
        newValue := 0
    if (newValue > 1000)
        newValue := 1000
    
    headingFilterInputValues[levelNum] := newValue
    
    ; Sync UpDown control
    upDownVar := "headingFilterSpin" . levelNum . "UD"
    if (IsObject(%upDownVar%)) {
        GuiControl,, %upDownVar%, %newValue%
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("Level " . levelNum . " limit: " . newValue, "Debug", 800)
    }
return



RecalculateMaxHeadingLevels() {
    global headingFilterCheckboxes, headingFilterLevelCount, maxHeadingLevels
    
    maxChecked := 0
    Loop, %headingFilterLevelCount% {
        if (headingFilterCheckboxes[A_Index]) {
            maxChecked := A_Index
        }
    }
    maxHeadingLevels := maxChecked
}


; === NEW: RadioBox Change Handler ===
; === TOGGLEABLE RADIOBOX HANDLER ===
; === TOGGLEABLE RADIOBOX HANDLER ===
; ===========================================================
; MODIFIED: RadioBox Toggle Handler
; ===========================================================
HeadingFilterRadioBoxChange:
    GuiControlGet, radioState,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterRadioBox")
    
    ; Initialize array if needed
    if (headingFilterRadioStates.Length() < 200) {
        Loop, 200 {
            headingFilterRadioStates[A_Index] := 0
        }
    }
    
    ; TOGGLE LOGIC
    if (radioState = 1 && headingFilterRadioStates[levelNum] = 1) {
        ; Already checked -> uncheck this level AND all ABOVE it (higher numbers)
        headingFilterRadioStates[levelNum] := 0
        GuiControl,, %A_GuiControl%, 0
        
        ; Uncheck all SUBSEQUENT levels (levelNum+1 and up)
        Loop, % 200 - levelNum {
            nextLevel := levelNum + A_Index
            nextRadio := "headingFilterRadioBox" . nextLevel
            GuiControl,, %nextRadio%, 0
            headingFilterRadioStates[nextLevel] := 0
        }
        
        ; REMOVED: No longer resetting spinbox values to 0 when unchecking radio
        ; Values stay as they are (1 or whatever they were set to)
        
    } else if (radioState = 1) {
        ; New check - cascade down (check this level and all below down to 1)
        headingFilterRadioStates[levelNum] := 1
        GuiControl,, %A_GuiControl%, 1
        
        ; Check all PREVIOUS levels (down to level 1)
        Loop, % levelNum - 1 {
            prevLevel := levelNum - A_Index
            prevRadio := "headingFilterRadioBox" . prevLevel
            GuiControl,, %prevRadio%, 1
            headingFilterRadioStates[prevLevel] := 1
        }
        
        ; ALSO CHECK ALL LEVEL CHECKBOXES from 1 to levelNum
        Loop, % levelNum {
            checkboxVar := "headingFilterCB" . A_Index
            GuiControl,, %checkboxVar%, 1
            headingFilterCheckboxes[A_Index] := true
        }
        
        ; ENFORCE SPINBOX VALUES: Set to 1 if 0, for all checked radio levels
        Loop, % levelNum {
            targetLevel := A_Index
            spinVar := "headingFilterSpin" . targetLevel
            currentSpinValue := headingFilterInputValues[targetLevel]
            
            ; If spinbox is 0, jump to 1
            if (currentSpinValue = 0 || currentSpinValue = "") {
                headingFilterInputValues[targetLevel] := 1
                GuiControl,, %spinVar%, 1
            }
        }
        
        ; Recalculate max heading levels
        RecalculateMaxHeadingLevels()
        
    } else {
        ; Unchecked by system (clicking an already unchecked box)
        headingFilterRadioStates[levelNum] := 0
    }
return


; ** NEW: F4/F5 Level Change Handler **
F4F5LevelChange:
    GuiControlGet, newLevel,, F4F5OverrideLevel
    global f4f5OverrideLevel
    if (newLevel < 2) {
        newLevel := 2
        GuiControl,, F4F5OverrideLevel, 2
    }
    f4f5OverrideLevel := newLevel
return

; ** NEW: Comprehensive Reset function **
; === MODIFIED: ResetAllLevelInputs - Clear radios too ===
; ===========================================================
; MODIFIED: Reset (only affects spinboxes, not radios)
; ===========================================================
ResetAllLevelInputs:
    global headingFilterInputValues, headingFilterLevelCount, headingFilterRadioStates
    
    ; Reset all spinbox values to 0
    Loop, %headingFilterLevelCount% {
        if (A_Index > 1) {
            headingFilterInputValues[A_Index] := 0
            spinControl := "headingFilterSpin" . A_Index
            upDownControl := "headingFilterSpin" . A_Index . "UD"
            
            ; Check if control exists before trying to set it
            GuiControl,, %spinControl%, 0
            GuiControl,, %upDownControl%, 0
        }
    }
    
    ; Uncheck ALL radio boxes
    Loop, 200 {
        if (A_Index > 1) {
            headingFilterRadioStates[A_Index] := 0
            radioControl := "headingFilterRadioBox" . A_Index
            GuiControl,, %radioControl%, 0
        }
    }
    
    ; Reset F4/F5 controls
    f4f5OverrideActive := false
    f4f5OverrideLevel := 2
    f4f5CurrentHeadingNum := 0
    
    ShowSmartTooltip("✅ All reset", "Debug", 1500)
    
    ; Refresh GUI to show changes
    UpdateHeadingFilterControls()
return


; ===========================================================
; NEW: Level Count Dropdown Change Handler
; ===========================================================
LevelCountDDChange:
    GuiControlGet, selectedLevels,, LevelCountDD
    
    if (selectedLevels = "" || selectedLevels < 1) {
        selectedLevels := 1
    } else if (selectedLevels > 200) {
        selectedLevels := 200
    }
    
    headingFilterLevelCount := selectedLevels
    
    ; ** Recalculate pagination **
    totalHeadingFilterPages := Ceil(headingFilterLevelCount / levelsPerPage)
    currentHeadingFilterPage := 1  ; Reset to first page
    
    UpdateHeadingFilterControls()
return


HeadingFilterPrevPage:
    if (currentHeadingFilterPage > 1) {
        currentHeadingFilterPage -= 1
        UpdateHeadingFilterControls()
    }
return

HeadingFilterNextPage:
    if (currentHeadingFilterPage < totalHeadingFilterPages) {
        currentHeadingFilterPage += 1
        UpdateHeadingFilterControls()
    }
return



; === MODIFIED: F4F5OverrideChange - No longer unchecks radios ===
F4F5OverrideChange:
    GuiControlGet, controlValue,, F4F5OverrideCB
    global f4f5OverrideActive, f4f5OverrideLevel
    
    f4f5OverrideActive := controlValue ? true : false
    
    if (f4f5OverrideActive) {
        GuiControlGet, levelValue,, F4F5OverrideLevel
        
        if (levelValue < 2) {
            levelValue := 2
            GuiControl,, F4F5OverrideLevel, 2
        }
        
        f4f5OverrideLevel := levelValue
        
        ; Auto-enable target level checkbox
        if (f4f5OverrideLevel <= headingFilterCheckboxes.Length()) {
            headingFilterCheckboxes[f4f5OverrideLevel] := true
            GuiControl,, headingFilterCB%f4f5OverrideLevel%, 1
        }
        
        ; REMOVED: No longer unchecks any radio boxes
        
        SetTimer, _LiveReloadF4F5Control, 100
        ShowSmartTooltip("✅ F4/F5 controls level " . f4f5OverrideLevel, "Debug", 1200)
    } else {
        f4f5OverrideLevel := 2
        SetTimer, _LiveReloadF4F5Control, Off
        ShowSmartTooltip("⏮️ F4/F5 restored", "Debug", 1200)
    }
return

HeadingFilterComboChange:
    GuiControlGet, controlValue,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterCombo")
    levelNum := SubStr(levelNum, 1)  ; Extract number
    headingFilterInputValues[levelNum] := controlValue
return

; ===========================================================
; LIVE RELOAD TIMER FOR F4/F5 CONTROL
; ===========================================================
; Runs every 100ms when F4/F5 is active and GUI is open
; Updates ONLY the target level's input box for real-time feedback

; === MODIFIED: _LiveReloadF4F5Control - Sync SpinBox ===
_LiveReloadF4F5Control:
    global f4f5OverrideActive, f4f5OverrideLevel
    
    if (!f4f5OverrideActive || !headingFilterGUIVisible || !headingFilterGUIActive)
        return
    
    if (f4f5OverrideLevel < 2 || f4f5OverrideLevel > 200)
        return
    
    currentValue := headingFilterInputValues[f4f5OverrideLevel]
    spinControl := "headingFilterSpin" . f4f5OverrideLevel
    upDownControl := "headingFilterSpin" . f4f5OverrideLevel . "UD"
    
    GuiControl,, %spinControl%, %currentValue%
    GuiControl,, %upDownControl%, %currentValue%
return

; ===========================================================
; MODIFIED: Heading Filter Checkbox Change with continuous range logic
; ===========================================================
HeadingFilterCheckboxChange:
    GuiControlGet, controlValue,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterCB")
    
    ; Get the current max checked level
    maxCheckedLevel := 0
    Loop, %headingFilterLevelCount% {
        if (headingFilterCheckboxes[A_Index]) {
            maxCheckedLevel := A_Index
        }
    }
    
    ; If checking a box, check all boxes up to this level
    if (controlValue = 1) {
        Loop, %levelNum% {
            headingFilterCheckboxes[A_Index] := true
            checkboxVar := "headingFilterCB" . A_Index
            %checkboxVar% := 1
            GuiControl,, %checkboxVar%, 1
        }
        ; Update max checked level
        if (levelNum > maxCheckedLevel) {
            maxCheckedLevel := levelNum
        }
    } 
    ; If unchecking a box, uncheck all boxes from this level onward
    else if (controlValue = 0) {
        ; Don't allow unchecking level 1
        if (levelNum = 1) {
            GuiControl,, headingFilterCB1, 1
            return
        }
        
        ; Uncheck from this level to the end
        Loop, %headingFilterLevelCount% {
            if (A_Index >= levelNum) {
                headingFilterCheckboxes[A_Index] := false
                checkboxVar := "headingFilterCB" . A_Index
                %checkboxVar% := 0
                GuiControl,, %checkboxVar%, 0
            }
        }
        ; Update max checked level
        maxCheckedLevel := levelNum - 1
        
        ; UNCHECK RADIO BOXES at and above this level
        Loop, % 200 - levelNum + 1 {
            targetLevel := levelNum + A_Index - 1
            radioVar := "headingFilterRadioBox" . targetLevel
            GuiControl,, %radioVar%, 0
            headingFilterRadioStates[targetLevel] := 0
        }
    }
    
    ; Update the global maxHeadingLevels
    global maxHeadingLevels := maxCheckedLevel

    ; Update the global maxHeadingLevels
    RecalculateMaxHeadingLevels()
    
    ; Also update the headingFilterCheckboxes array
    Loop, %headingFilterLevelCount% {
        if (A_Index <= maxCheckedLevel) {
            headingFilterCheckboxes[A_Index] := true
        } else {
            headingFilterCheckboxes[A_Index] := false
        }
    }
return

HeadingFilterInputChange:
    GuiControlGet, controlValue,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterInput")
    headingFilterInputValues[levelNum] := controlValue
    
    dropdownVar := "headingFilterDD" . levelNum
    GuiControl, ChooseString, %dropdownVar%, %controlValue%
return

HeadingFilterDropdownChange:
    GuiControlGet, controlValue,, %A_GuiControl%
    levelNum := StrReplace(A_GuiControl, "headingFilterDD")
    headingFilterInputValues[levelNum] := controlValue
    
    inputVar := "headingFilterInput" . levelNum
    GuiControl,, %inputVar%, %controlValue%
return



; ===========================================================
; MODIFIED: Reset Heading Filter Inputs
; ===========================================================
ResetHeadingFilterInputs:
    ; Reset all limit values to 0 (except level 1 which doesn't have one)
    Loop, %headingFilterLevelCount% {
        if (A_Index > 1) {
            headingFilterInputValues[A_Index] := 0
            comboVar := "headingFilterCombo" . A_Index
            if (IsObject(%comboVar%)) {
                GuiControl, ChooseString, %comboVar%, 0
            }
        }
    }
    
    ; Also reset F4/F5 override
    f4f5OverrideActive := false
    f4f5OverrideLevel := 1
    f4f5CurrentHeadingNum := 0
    
    ShowSmartTooltip("✅ All input values reset to 0", "Debug", 1200)
return

global headingFilterUserClosed := false

; Custom close button handler
; ===========================================================
; MODIFIED: Heading Filter GUI Close - properly close and don't reopen
; ===========================================================
HeadingFilterGUIClose:
    Gui, HeadingFilter:Destroy
    headingFilterGUIVisible := false
    headingFilterGUIActive := false
    headingFilterUserClosed := true
    
    ; ** STOP LIVE RELOAD TIMER **
    SetTimer, _LiveReloadF4F5Control, Off
return



; ===========================================================
; MODIFIED: Heading Filter Focus Check - only reopen if not user-closed
; ===========================================================
_HeadingFilterFocusCheck:
    global headingFilterGUIActive, headingFilterGUIVisible, lastFocusLossTime, headingFilterUserClosed
    
    ; Don't reopen if user explicitly closed it
    if (headingFilterUserClosed)
        return
    
    ; Only reopen if GUI was active but not visible, and we're in XMind
    if (headingFilterGUIActive && !headingFilterGUIVisible && WinActive("ahk_exe XMind.exe")) {
        if (A_TickCount - lastFocusLossTime > 500) {
            headingFilterGUIVisible := true
            Gui, HeadingFilter:Show
        }
    }
    
    ; Track focus loss time
    if (!WinActive("ahk_exe XMind.exe")) {
        lastFocusLossTime := A_TickCount
    }
return

; ===========================================================
; NEW: Function to properly destroy GUI when needed
; ===========================================================
DestroyHeadingFilterGUI() {
    global headingFilterGUIActive, headingFilterGUIVisible, headingFilterUserClosed
    
    if (headingFilterGUIActive) {
        Gui, HeadingFilter:Destroy
        headingFilterGUIVisible := false
        headingFilterGUIActive := false
        headingFilterUserClosed := true
    }
}















; FIXED: Single heading detection - ALWAYS returns true for any text
; FIXED: Detect ANY length single heading
; FIXED: Detect ANY content as single heading
IsSingleHeading(headingText) {
    if (headingText = "" || StrLen(headingText) < 1) {
        return false
    }
    
    ; Remove whitespace for checking
    trimmed := Trim(headingText)
    if (trimmed = "") {
        return false
    }
    
    ; If no hierarchy markers, it's a single heading
    if (!InStr(trimmed, "`t") && !InStr(trimmed, "`n")) {
        return true
    }
    
    ; Count actual lines
    lines := StrSplit(trimmed, "`n", "`r")
    nonEmptyLines := 0
    for _, line in lines {
        if (Trim(line) != "") {
            nonEmptyLines++
        }
        if (nonEmptyLines > 1) {
            return false
        }
    }
    
    return (nonEmptyLines = 1)
}

; ===========================================================
; ENHANCED LEVEL NUMBERING SYSTEM
; ===========================================================
; PURPOSE: Convert numbers to hierarchical numbering systems
; FEATURES: Six modes (Numbers, Dotted, Alphabet, Hierarchical, Conversational, Hybrid Loop), proper hierarchy tracking

; Convert number to letter for alphabet mode (1 = a, 2 = b, ..., 27 = aa, etc.)
NumberToLetter(num) {
    if (num <= 0) {
        return ""
    }
    
    letters := ""
    while (num > 0) {
        mod := Mod(num - 1, 26)
        letters := Chr(97 + mod) . letters  ; 97 = 'a' in ASCII
        num := (num - 1) // 26
    }
    return letters
}

; ===========================================================
; MODE 7: MINIMAL NUMBERING (N: heading)
; For advanced users - concise numbering format
; ===========================================================
ProcessHeadingStructureMinimal(headingText, speedMultiplier := 1.0) {
    global headingReadIndentLevels, headingIncludeEmptyNodes, headingMaxDepth
    global analyticalMode, dualDetectionEnabled, suppressNumbersEnabled
    
    if (headingText = "" || headingText = "`r`n" || headingText = "`n" || headingText = " ") {
        return ""
    }
    
    if (analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("RAW TEXT (Minimal): " . TruncateString(headingText, 100), "Debug", 800)
    }
    
    lines := StrSplit(headingText, "`n", "`r")
    processedText := ""
    
    for index, line in lines {
        line := StrReplace(line, "`r", "")
        
        if (Trim(line) = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; Count tabs
        indentLevel := 0
        charPos := 1
        Loop, Parse, line
        {
            if (A_LoopField = "`t") {
                indentLevel++
                charPos++
            } else {
                break
            }
        }
        
        ; Extract content
        cleanLine := SubStr(line, charPos)
        cleanLine := Trim(cleanLine)
        
        if (cleanLine = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; Apply speed multiplier
        if (speedMultiplier > 1.0) {
            cleanLine := PreprocessTextForSpeed(cleanLine, speedMultiplier)
        }
        
        ; Apply number suppression
        if (suppressNumbersEnabled) {
            cleanLine := StripNumbersFromText(cleanLine)
        }
        
        ; MODE 7: Minimal format - just "N: heading"
        if (headingReadIndentLevels) {
            levelNumber := indentLevel + 1
            prefix := levelNumber . ": "
            processedText .= prefix . cleanLine . ". "
        } else {
            processedText .= cleanLine . ". "
        }
        
        if (headingReadIndentLevels) {
            processedText .= "... "
        }
    }
    
    return Trim(processedText)
}



; NEW: Hierarchical "then under" processing for Mode 4 with grammar variations
; ===========================================================
; MODE 4: HIERARCHICAL "then under" MODE
; ===========================================================
; ===========================================================
; MODE 4: HIERARCHICAL with Speed per line (content only)
; ===========================================================
ProcessHeadingStructureHierarchical(headingText, speedMultiplier := 1.0) {
    global headingIncludeEmptyNodes, headingMaxDepth, suppressNumbersEnabled
    global analyticalMode, dualDetectionEnabled
    
    if (headingText = "" || headingText = "`r`n" || headingText = "`n" || headingText = " ") {
        return ""
    }
    
    if (analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("RAW TEXT (Hierarchical): " . TruncateString(headingText, 100), "Debug", 800)
    }
    
    lines := StrSplit(headingText, "`n", "`r")
    processedText := ""
    previousIndentLevel := -1
    previousParent := ""
    sameParentCount := 0
    atSameLevel := false
    pathStack := []
    lastIndentLevel := -1
    firstLine := true
    
    for index, line in lines {
        originalLine := line
        line := StrReplace(line, "`r", "")
        
        if (Trim(line) = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; === CRITICAL: Count tabs WITHOUT modifying line ===
        indentLevel := 0
        charPos := 1
        Loop, Parse, line
        {
            if (A_LoopField = "`t") {
                indentLevel++
                charPos++
            } else {
                break
            }
        }
        
        RegExMatch(line, "^(`t*)", tabMatch)
        altIndentLevel := StrLen(tabMatch1)
        if (altIndentLevel > indentLevel) {
            indentLevel := altIndentLevel
        }
        
        ; Extract content only
        cleanLine := SubStr(line, charPos)
        cleanLine := Trim(cleanLine)
        
        if (cleanLine = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; === APPLY SPEED MULTIPLIER TO CONTENT ONLY ===
        if (speedMultiplier > 1.0) {
            originalHeadingName := cleanLine
            cleanLine := PreprocessTextForSpeed(cleanLine, speedMultiplier)
            if (analyticalMode && cleanLine != originalHeadingName) {
                ShowSmartTooltip("⚡ HIERARCHICAL SPEED: '" . originalHeadingName . "' → '" . cleanLine . "'", "Debug", 800)
            }
        }
        
        ; === APPLY NUMBER SUPPRESSION TO CONTENT ONLY ===
        if (suppressNumbersEnabled) {
            cleanLine := StripNumbersFromText(cleanLine)
        }
        
        ; HIERARCHICAL PROCESSING (uses indentLevel from tabs, but doesn't add prefix)
        if (firstLine) {
            processedText := cleanLine . ", "
            pathStack := []
            pathStack.Push(cleanLine)
            lastIndentLevel := indentLevel
            previousParent := cleanLine
            firstLine := false
            
            if (analyticalMode && dualDetectionEnabled) {
                ShowSmartTooltip("ROOT: " . cleanLine, "Debug", 800)
            }
        } else {
            if (indentLevel > lastIndentLevel) {
                pathStack.Push(cleanLine)
            } else if (indentLevel < lastIndentLevel) {
                while (pathStack.Length() > indentLevel + 1) {
                    pathStack.Pop()
                }
                pathStack[indentLevel + 1] := cleanLine
            } else {
                pathStack[indentLevel + 1] := cleanLine
            }
            
            currentParent := (indentLevel > 0) ? pathStack[indentLevel] : ""
            atSameLevel := (indentLevel == previousIndentLevel)
            sameParent := (currentParent == previousParent)
            grammarPattern := ChooseGrammarPattern(indentLevel, previousIndentLevel, sameParent, sameParentCount, index)
            phrase := BuildHierarchicalPhrase(grammarPattern, pathStack, indentLevel, cleanLine, currentParent)
            processedText .= phrase
            
            previousIndentLevel := indentLevel
            previousParent := currentParent
            if (sameParent && atSameLevel) {
                sameParentCount++
            } else {
                sameParentCount := 0
            }
            lastIndentLevel := indentLevel
            
            if (analyticalMode && dualDetectionEnabled) {
                debugMsg := "Lvl: " . indentLevel . " Parent: '" . currentParent . "' Pattern: " . grammarPattern . " Text: '" . cleanLine . "'"
                ShowSmartTooltip(debugMsg, "Debug", 800)
            }
        }
    }
    
    processedText := RTrim(processedText, ", ")
    processedText .= "."
    
    return processedText
}


; Grammar Pattern Selection
ChooseGrammarPattern(currentLevel, previousLevel, sameParent, sameParentCount, lineIndex) {
    ; Random seed for variation
    Random, randNum, 1, 100
    
    ; First item after root
    if (previousLevel = -1) {
        return 1  ; Simple "then under"
    }
    
    ; Moving to a different parent
    if (!sameParent) {
        ; When changing to a completely different branch
        if (currentLevel <= previousLevel) {
            ; Back to higher level
            if (randNum <= 33) {
                return 5  ; "now under"
            } else if (randNum <= 66) {
                return 6  ; "and under"
            } else {
                return 7  ; "also under"
            }
        } else {
            ; Deeper into hierarchy
            return 2  ; "then under [parent] there is [child]"
        }
    }
    
    ; Same parent, different children
    if (sameParentCount = 0) {
        ; First child of this parent
        if (randNum <= 25) {
            return 1  ; "then under"
        } else if (randNum <= 50) {
            return 3  ; "under [parent] there is [child]"
        } else if (randNum <= 75) {
            return 4  ; "under [parent] we have [child]"
        } else {
            return 8  ; "under [parent] you'll find [child]"
        }
    } else if (sameParentCount = 1) {
        ; Second child
        if (randNum <= 33) {
            return 9   ; "and also under"
        } else if (randNum <= 66) {
            return 10  ; "and under the same [parent] there is"
        } else {
            return 11  ; "then under [parent] there is also"
        }
    } else {
        ; Third or more child
        if (randNum <= 25) {
            return 12  ; "and then under"
        } else if (randNum <= 50) {
            return 13  ; "additionally under"
        } else if (randNum <= 75) {
            return 14  ; "further under"
        } else {
            return 15  ; "next under"
        }
    }
}

; Build Hierarchical Phrase
BuildHierarchicalPhrase(pattern, pathStack, indentLevel, currentHeading, currentParent) {
    ; Get immediate parent if exists
    parentName := (indentLevel > 0) ? pathStack[indentLevel] : ""
    
    ; Strip numbers from parent name if suppression is enabled
    global suppressNumbersEnabled
    if (suppressNumbersEnabled && parentName != "") {
        parentName := StripNumbersFromText(parentName)
    }
    
    ; Build the phrase based on pattern
    if (pattern = 1) {
        ; "then under [parent] there is [child]"
        if (parentName != "") {
            return "then under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "then there is " . currentHeading . ", "
        }
    } else if (pattern = 2) {
        ; "then under [parent] there is [child]" (emphasized)
        if (parentName != "") {
            return "then under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "then there is " . currentHeading . ", "
        }
    } else if (pattern = 3) {
        ; "under [parent] there is [child]"
        if (parentName != "") {
            return "under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "there is " . currentHeading . ", "
        }
    } else if (pattern = 4) {
        ; "under [parent] we have [child]"
        if (parentName != "") {
            return "under " . parentName . " we have " . currentHeading . ", "
        } else {
            return "we have " . currentHeading . ", "
        }
    } else if (pattern = 5) {
        ; "now under [parent] there is [child]"
        if (parentName != "") {
            return "now under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "now there is " . currentHeading . ", "
        }
    } else if (pattern = 6) {
        ; "and under [parent] there is [child]"
        if (parentName != "") {
            return "and under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "and there is " . currentHeading . ", "
        }
    } else if (pattern = 7) {
        ; "also under [parent] there is [child]"
        if (parentName != "") {
            return "also under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "also there is " . currentHeading . ", "
        }
    } else if (pattern = 8) {
        ; "under [parent] you'll find [child]"
        if (parentName != "") {
            return "under " . parentName . " you'll find " . currentHeading . ", "
        } else {
            return "you'll find " . currentHeading . ", "
        }
    } else if (pattern = 9) {
        ; "and also under [parent] there is [child]"
        if (parentName != "") {
            return "and also under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "and also there is " . currentHeading . ", "
        }
    } else if (pattern = 10) {
        ; "and under the same [parent] there is [child]"
        if (parentName != "") {
            return "and under the same " . parentName . " there is " . currentHeading . ", "
        } else {
            return "and there is also " . currentHeading . ", "
        }
    } else if (pattern = 11) {
        ; "then under [parent] there is also [child]"
        if (parentName != "") {
            return "then under " . parentName . " there is also " . currentHeading . ", "
        } else {
            return "then there is also " . currentHeading . ", "
        }
    } else if (pattern = 12) {
        ; "and then under [parent] there is [child]"
        if (parentName != "") {
            return "and then under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "and then there is " . currentHeading . ", "
        }
    } else if (pattern = 13) {
        ; "additionally under [parent] there is [child]"
        if (parentName != "") {
            return "additionally under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "additionally there is " . currentHeading . ", "
        }
    } else if (pattern = 14) {
        ; "further under [parent] there is [child]"
        if (parentName != "") {
            return "further under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "further there is " . currentHeading . ", "
        }
    } else if (pattern = 15) {
        ; "next under [parent] there is [child]"
        if (parentName != "") {
            return "next under " . parentName . " there is " . currentHeading . ", "
        } else {
            return "next there is " . currentHeading . ", "
        }
    }
    
    ; Default fallback
    if (parentName != "") {
        return "under " . parentName . " there is " . currentHeading . ", "
    } else {
        return "there is " . currentHeading . ", "
    }
}

; NEW: Helper function to get smart transition phrase based on context
GetSmartTransition(fromLevel, toLevel, parentName, isSameParent) {
    ; Determine movement direction
    if (toLevel > fromLevel) {
        ; GOING DEEPER
        Random, idx, 1, 20
        if (idx <= 5) {
            return "Digging deeper, under " . parentName
        } else if (idx <= 10) {
            return "Within " . parentName
        } else if (idx <= 15) {
            return "Exploring deeper into " . parentName
        } else if (idx <= 18) {
            return "Nested under " . parentName
        } else {
            return "Diving into " . parentName
        }
    } else if (toLevel < fromLevel) {
        ; GOING SHALLOWER
        Random, idx, 1, 20
        if (idx <= 5) {
            return "Backing up a bit, under " . parentName
        } else if (idx <= 10) {
            return "Now at a higher level, under " . parentName
        } else if (idx <= 15) {
            return "Returning to " . parentName
        } else if (idx <= 18) {
            return "Moving back up, under " . parentName
        } else {
            return "Shifting upward to " . parentName
        }
    } else {
        ; SAME LEVEL - new sibling
        if (isSameParent) {
            Random, idx, 1, 15
            if (idx <= 5) {
                return "Also under " . parentName
            } else if (idx <= 10) {
                return "Next under " . parentName
            } else {
                return "Additionally, under " . parentName
            }
        } else {
            return "Now under " . parentName
        }
    }
}

; NEW: Smart conversational mode that dynamically explains hierarchy movements
; ===========================================================
; MODE 5: CONVERSATIONAL MODE with smart transitions
; ===========================================================
; ===========================================================
; MODE 5: CONVERSATIONAL with Speed applied to CONTENT ONLY
; ===========================================================
ProcessHeadingStructureConversational(headingText, speedMultiplier := 1.0) {
    global headingIncludeEmptyNodes, headingMaxDepth, suppressNumbersEnabled
    global analyticalMode, dualDetectionEnabled
    
    if (headingText = "" || headingText = "`r`n" || headingText = "`n" || headingText = " ") {
        return ""
    }
    
    if (analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("RAW TEXT (Smart Conversational): " . TruncateString(headingText, 100), "Debug", 800)
    }
    
    lines := StrSplit(headingText, "`n", "`r")
    processedText := ""
    previousIndentLevel := -1
    currentParent := ""
    parentStack := []
    sentenceCount := 0
    maxDepth := 0
    
    ; Pre-scan for complexity
    for index, line in lines {
        trimmed := Trim(line)
        if (trimmed = "" && !headingIncludeEmptyNodes) {
            continue
        }
        RegExMatch(line, "^(`t*)", tabMatch)
        indentLevel := StrLen(tabMatch1)
        if (indentLevel > maxDepth) {
            maxDepth := indentLevel
        }
    }
    
    isComplex := (maxDepth > 1)
    if (analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("Detected " . lines.Length() . " lines, max depth: " . maxDepth . " (Complex: " . isComplex . ")", "Debug", 800)
    }
    
    for index, line in lines {
        originalLine := line
        line := StrReplace(line, "`r", "")
        
        if (Trim(line) = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; === CRITICAL: Count tabs WITHOUT modifying line ===
        indentLevel := 0
        charPos := 1
        Loop, Parse, line
        {
            if (A_LoopField = "`t") {
                indentLevel++
                charPos++
            } else {
                break
            }
        }
        
        RegExMatch(line, "^(`t*)", tabMatch)
        altIndentLevel := StrLen(tabMatch1)
        if (altIndentLevel > indentLevel) {
            indentLevel := altIndentLevel
        }
        
        ; Extract content only
        cleanLine := SubStr(line, charPos)
        cleanLine := Trim(cleanLine)
        
        if (cleanLine = "") {
            continue
        }
        
        ; === APPLY SPEED MULTIPLIER TO CONTENT ONLY ===
        if (speedMultiplier > 1.0) {
            originalHeadingName := cleanLine
            cleanLine := PreprocessTextForSpeed(cleanLine, speedMultiplier)
            if (analyticalMode && cleanLine != originalHeadingName) {
                ShowSmartTooltip("⚡ CONVERSATIONAL SPEED: '" . originalHeadingName . "' → '" . cleanLine . "'", "Debug", 800)
            }
        }
        
        ; === APPLY NUMBER SUPPRESSION TO CONTENT ONLY ===
        if (suppressNumbersEnabled) {
            cleanLine := StripNumbersFromText(cleanLine)
        }
        
        ; Update hierarchy
        if (indentLevel = 0) {
            parentStack := [cleanLine]
            currentParent := ""
        } else {
            if (indentLevel > previousIndentLevel) {
                parentStack.Push(cleanLine)
            } else if (indentLevel < previousIndentLevel) {
                while (parentStack.Length() > indentLevel + 1) {
                    parentStack.Pop()
                }
                parentStack[indentLevel + 1] := cleanLine
            } else {
                parentStack[indentLevel + 1] := cleanLine
            }
            currentParent := parentStack[indentLevel]
        }
        
        ; Determine line type
        lineType := ""
        if (index = 1) {
            lineType := "root"
        } else if (indentLevel > previousIndentLevel) {
            lineType := "deeper"
        } else if (indentLevel < previousIndentLevel) {
            lineType := "shallower"
        } else if (currentParent = parentStack[previousIndentLevel + 1]) {
            lineType := "same-parent"
        } else {
            lineType := "new-parent"
        }
        
        ; Generate smart phrase
        phrase := ""
        if (lineType = "root") {
            Random, randIntro, 1, 6
            if (randIntro = 1) {
                phrase := "Alright, let's start with " . cleanLine . ". "
            } else if (randIntro = 2) {
                phrase := "First, we have " . cleanLine . ". "
            } else if (randIntro = 3) {
                phrase := "The main topic is " . cleanLine . ". "
            } else if (randIntro = 4) {
                phrase := "Beginning with " . cleanLine . ". "
            } else if (randIntro = 5) {
                phrase := "We're looking at " . cleanLine . ". "
            } else {
                phrase := cleanLine . " is where we start. "
            }
        } else if (lineType = "same-parent") {
            Random, idx, 1, 10
            if (idx <= 3) {
                phrase := "Also under " . currentParent . " there's " . cleanLine . ". "
            } else if (idx <= 6) {
                phrase := "Next under " . currentParent . " is " . cleanLine . ". "
            } else if (idx <= 8) {
                phrase := "Additionally, under " . currentParent . " we have " . cleanLine . ". "
            } else {
                phrase := "Then under " . currentParent . " there's " . cleanLine . ". "
            }
        } else if (lineType = "new-parent") {
            Random, idx, 1, 8
            if (idx <= 2) {
                phrase := "Now, under " . currentParent . " there's " . cleanLine . ". "
            } else if (idx <= 4) {
                phrase := "Moving to " . currentParent . ", we have " . cleanLine . ". "
            } else if (idx <= 6) {
                phrase := "Under " . currentParent . " you'll find " . cleanLine . ". "
            } else {
                phrase := "Then there's " . currentParent . " which includes " . cleanLine . ". "
            }
        } else if (lineType = "deeper") {
            transition := GetSmartTransition(previousIndentLevel, indentLevel, currentParent, false)
            phrase := transition . " there's " . cleanLine . ". "
        } else if (lineType = "shallower") {
            transition := GetSmartTransition(previousIndentLevel, indentLevel, currentParent, false)
            phrase := transition . " which includes " . cleanLine . ". "
        }
        
        processedText .= phrase
        previousIndentLevel := indentLevel
        sentenceCount++
        
        if (sentenceCount >= 3) {
            processedText .= "... "
            sentenceCount := 0
        }
        
        if (analyticalMode && dualDetectionEnabled) {
            ShowSmartTooltip("Type: " . lineType . " | Parent: " . currentParent . " | Text: " . cleanLine, "Debug", 800)
        }
    }
    
    processedText := Trim(processedText)
    if (SubStr(processedText, -1) = "...") {
        processedText := SubStr(processedText, 1, -3) . "."
    }
    if (SubStr(processedText, -1) != ".") {
        processedText .= "."
    }
    
    return processedText
}

; Process heading structure with level announcement
; ===========================================================
; ENHANCED LEVEL NUMBERING SYSTEM - MODE 1, 2, 3 (Numbers, Dotted, Alphabet)
; ===========================================================
; ===========================================================
; MODE 1,2,3: Standard Level Announcement with Speed per line
; ===========================================================
ProcessHeadingStructure(headingText, speedMultiplier := 1.0) {
    global headingReadIndentLevels, headingIncludeEmptyNodes, headingMaxDepth
    global levelAnnounceEnabled, levelAnnounceMode, levelPrefix
    global analyticalMode, dualDetectionEnabled, suppressNumbersEnabled
    
    if (headingText = "" || headingText = "`r`n" || headingText = "`n" || headingText = " ") {
        return ""
    }
    
    if (analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("RAW TEXT: " . TruncateString(headingText, 100), "Debug", 800)
    }
    
    lines := StrSplit(headingText, "`n", "`r")
    processedText := ""
    
    if (levelAnnounceMode = 2) {
        levelCounters := []
        lastIndentLevel := -1
    }
    
    for index, line in lines {
        line := StrReplace(line, "`r", "")
        
        if (Trim(line) = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; Count raw tab indentation (this is CRITICAL - don't modify tabs)
        indentLevel := 0
        charPos := 1
        Loop, Parse, line
        {
            if (A_LoopField = "`t") {
                indentLevel++
                charPos++
            } else {
                break
            }
        }
        
        ; Extract clean content (everything after tabs)
        cleanLine := SubStr(line, charPos)
        cleanLine := Trim(cleanLine)
        
        if (cleanLine = "" && !headingIncludeEmptyNodes) {
            continue
        }
        
        ; === APPLY SPEED MULTIPLIER TO CONTENT ONLY (PRECISE) ===
        if (speedMultiplier > 1.0) {
            originalHeadingName := cleanLine
            cleanLine := PreprocessTextForSpeed(cleanLine, speedMultiplier)
            if (analyticalMode && cleanLine != originalHeadingName) {
                ShowSmartTooltip("⚡ SPEED: '" . originalHeadingName . "' → '" . cleanLine . "'", "Debug", 800)
            }
        }
        
        ; === APPLY NUMBER SUPPRESSION TO CONTENT ONLY ===
        if (suppressNumbersEnabled) {
            cleanLine := StripNumbersFromText(cleanLine)
        }
        
        ; ENHANCED LEVEL ANNOUNCEMENT (adds prefix AFTER processing)
        if (headingReadIndentLevels && levelAnnounceEnabled) {
            levelNumber := indentLevel + 1
            
            if (levelAnnounceMode = 1) {
                prefix := levelPrefix . " " . levelNumber . ": "
            } else if (levelAnnounceMode = 2) {
                ; Dotted numbering logic
                if (levelCounters.Length() = 0) {
                    levelCounters.Push(0)
                }
                if (indentLevel > lastIndentLevel) {
                    while (levelCounters.Length() < indentLevel + 1) {
                        levelCounters.Push(0)
                    }
                } else if (indentLevel < lastIndentLevel) {
                    levelCounters.SetLength(indentLevel + 1)
                }
                levelCounters[indentLevel + 1] += 1
                if (indentLevel <= lastIndentLevel) {
                    for i in levelCounters {
                        if (i > indentLevel + 1) {
                            levelCounters[i] := 0
                        }
                    }
                }
                dottedNumber := ""
                for i, counter in levelCounters {
                    if (i > 1) {
                        dottedNumber .= "."
                    }
                    dottedNumber .= counter
                }
                prefix := levelPrefix . " " . dottedNumber . ": "
                lastIndentLevel := indentLevel
            } else if (levelAnnounceMode = 3) {
                letter := NumberToLetter(levelNumber)
                prefix := levelPrefix . " " . letter . ": "
            }
            
            processedText .= prefix . cleanLine . ". "
        } else {
            processedText .= cleanLine . ". "
        }
        
        if (headingReadIndentLevels) {
            processedText .= "... "
        }
        
        if (analyticalMode && dualDetectionEnabled) {
            if (levelAnnounceMode = 2) {
                currentDotted := ""
                for i, counter in levelCounters {
                    if (i > 1) currentDotted .= "."
                    currentDotted .= counter
                }
                debugMsg := "Line " . index . ": Tabs=" . indentLevel . " Dotted=" . currentDotted . " Text='" . cleanLine . "'"
            } else {
                debugMsg := "Line " . index . ": Tabs=" . indentLevel . " Level=" . (indentLevel + 1) . " Text='" . cleanLine . "'"
            }
            ShowSmartTooltip(debugMsg, "Debug", 800)
        }
    }
    
    return Trim(processedText)
}


; Alternative method using file backup for tab preservation
; ===========================================================
; MODE 7: MINIMAL NUMBERING (N: heading) - FILE VERSION
; For advanced users - concise numbering format
; ===========================================================
ProcessHeadingStructureFromFile(speedMultiplier := 1.0) {
    global levelAnnounceEnabled, levelAnnounceMode, levelPrefix, analyticalMode, dualDetectionEnabled
    global suppressNumbersEnabled
    
    ; Create a temporary file and paste clipboard content
    tempFile := A_Temp . "\xmind_structure_" . A_TickCount . ".txt"
    FileDelete, %tempFile%
    
    ; Save clipboard to file
    clipboardContent := Clipboard
    FileAppend, %clipboardContent%, %tempFile%
    
    if (!FileExist(tempFile)) {
        return ""  ; File creation failed
    }
    
    processedText := ""
    FileRead, fileContent, %tempFile%
    
    if (fileContent = "") {
        FileDelete, %tempFile%
        return ""
    }
    
    lines := StrSplit(fileContent, "`n", "`r")
    
    for index, line in lines {
        line := StrReplace(line, "`r", "")
        
        ; Skip empty lines
        if (Trim(line) = "") {
            continue
        }
        
        ; Count leading tabs
        indentLevel := 0
        charPos := 1
        Loop, Parse, line
        {
            if (A_LoopField = "`t") {
                indentLevel++
                charPos++
            } else {
                break
            }
        }
        
        cleanLine := SubStr(line, charPos)
        cleanLine := Trim(cleanLine)
        
        if (cleanLine = "") {
            continue
        }
        
        ; Apply speed multiplier
        if (speedMultiplier > 1.0) {
            cleanLine := PreprocessTextForSpeed(cleanLine, speedMultiplier)
        }
        
        ; Strip numbers from heading text if suppression is enabled
        if (suppressNumbersEnabled) {
            cleanLine := StripNumbersFromText(cleanLine)
        }
        
        ; MODE 7: Minimal format - just "N: heading"
        if (levelAnnounceEnabled && levelAnnounceMode = 7) {
            levelNumber := indentLevel + 1
            prefix := levelNumber . ": "
            processedText .= prefix . cleanLine . ". "
        } else {
            ; Standard processing for other modes
            if (levelAnnounceEnabled) {
                levelNumber := indentLevel + 1
                
                if (levelAnnounceMode = 1) {
                    prefix := levelPrefix . " " . levelNumber . ": "
                } else if (levelAnnounceMode = 2) {
                    ; Dotted numbering logic
                    if (levelCounters.Length() = 0) {
                        levelCounters.Push(0)
                    }
                    if (indentLevel > lastIndentLevel) {
                        while (levelCounters.Length() < indentLevel + 1) {
                            levelCounters.Push(0)
                        }
                    } else if (indentLevel < lastIndentLevel) {
                        levelCounters.SetLength(indentLevel + 1)
                    }
                    levelCounters[indentLevel + 1] += 1
                    
                    dottedNumber := ""
                    for i, counter in levelCounters {
                        if (i > 1) {
                            dottedNumber .= "."
                        }
                        dottedNumber .= counter
                    }
                    prefix := levelPrefix . " " . dottedNumber . ": "
                    lastIndentLevel := indentLevel
                } else if (levelAnnounceMode = 3) {
                    letter := NumberToLetter(levelNumber)
                    prefix := levelPrefix . " " . letter . ": "
                }
                
                processedText .= prefix . cleanLine . ". "
            } else {
                processedText .= cleanLine . ". "
            }
        }
        
        processedText .= "... "
    }
    
    FileDelete, %tempFile%
    return Trim(processedText)
}

; FIXED: Function to speak heading structure - PROPER SINGLE HEADING HANDLING
; FIXED: Function to speak heading structure with auto number suppression handling
; FIXED: Heading TTS with direct file writing for large content
; FIXED: Heading TTS with fast path for single headings
; FIXED: Single character to 100K word support
; FIXED: Single character to 100K word support
; FIXED: Single character to 100K word support
; FIXED: Single character to 100K word support with infinite loop
; FIXED: Single character to 100K word support with file spam protection
; FIXED: Consistent tooltips after EVERY gap
; FIXED: Ultra-fast heading TTS with proper device switching
; FIXED: Ultra-fast heading TTS with device switching on stop
; FIXED: Single character to 100K word support for heading TTS
; FIXED: Single character to 100K word support with max levels filter
; FIXED: Loop restart by storing original structure separately
; FIXED: Removed early speed multiplier that destroyed tabs
; FIXED: NO speed multiplier here - it destroys tabs for F1
; ===========================================================
; HEADING TTS SYSTEM - MIND MAP STRUCTURE READING
; ===========================================================
; PURPOSE: Read entire branch structure with indentation levels
; FEATURES: 7 numbering modes, proper hierarchy tracking

SpeakHeadingStructure() {
    global headingTTSRunning, Message_NoHeadingSelected, Message_HeadingTTSStart
    global balconRunning, loopMode, analyticalMode, currentHeadingContent
    global levelAnnounceEnabled, levelAnnounceMode, speedMultiplier, suppressNumbersEnabled
    global cachedMode4Content, currentHeadingRawStructure, currentHeadingOriginalStructure
    global maxHeadingLevels
    
    if (balconRunning) {
        StopBalcon(true)
        Sleep, 100
    }
    
    if (loopMode) {
        CleanupLoopFiles("heading")
    }
    
    ; Get original structure FIRST
    originalStructure := GetHeadingBranchStructureAdaptive()
    
    if (Trim(originalStructure) = "" || StrLen(originalStructure) < 1) {
        ShowSmartTooltip("❌ " . Message_NoHeadingSelected, "NoHeadingSelected", 2000)
        return false
    }
    
    ; Store unfiltered for loop restart
    currentHeadingOriginalStructure := originalStructure
    
    ; Apply filter to create working copy
    headingStructure := originalStructure
    if (maxHeadingLevels > 0) {
        headingStructure := FilterHeadingByMaxLevels(headingStructure)
        if (Trim(headingStructure) = "") {
            ShowSmartTooltip("❌ No headings within max level", "NoHeadingSelected", 1200)
            return false
        }
    }
    
    ; Apply number suppression to raw content
    if (suppressNumbersEnabled) {
        headingStructure := StripNumbersFromText(headingStructure)
    }
    
    ; Store filtered structure for processing
    currentHeadingRawStructure := headingStructure
    
    ; Process with F1 announcements (speed multiplier passed as parameter)
    if (levelAnnounceEnabled) {
        if (levelAnnounceMode = 4 || levelAnnounceMode = 6) {
            processedText := ProcessHeadingStructureHierarchical(headingStructure, speedMultiplier)
            cachedMode4Content := processedText
        } else if (levelAnnounceMode = 5) {
            processedText := ProcessHeadingStructureConversational(headingStructure, speedMultiplier)
        } else if (levelAnnounceMode = 7) {
            processedText := ProcessHeadingStructureMinimal(headingStructure, speedMultiplier)
        } else {
            processedText := ProcessHeadingStructure(headingStructure, speedMultiplier)
        }
    } else {
        ; F1 is OFF but still apply speed multiplier to content
        processedText := headingStructure
        if (speedMultiplier > 1.0) {
            processedText := PreprocessTextForSpeed(processedText, speedMultiplier)
        }
    }
    
    if (processedText = "" || StrLen(processedText) < 1) {
        ShowSmartTooltip("❌ Processing failed", "Debug", 1200)
        return false
    }
    
    currentHeadingContent := processedText
    
    if (SpeakWithBalconSmart(processedText, "heading")) {
        headingTTSRunning := true
        ShowSmartTooltip(Message_HeadingTTSStart, "HeadingTTSStart", 800)
        return true
    }
    
    return false
}

; Stop heading TTS and cleanup
; Stop heading TTS and restore number suppression state
; Stop heading TTS and restore number suppression state
; Stop heading TTS - ERROR-PROOF VERSION
; Stop heading TTS and restore number suppression state - ERROR-PROOF VERSION
; Stop heading TTS - GUARANTEED DEVICE RESTORE
; Stop heading TTS - ONLY RESTORE DEVICE IF NOT IN LOOP MODE
; Stop heading TTS - ALWAYS restores device (manual stop)
; Stop heading TTS - ALWAYS restores device
; Stop heading TTS - SETS MANUAL KILL FLAG
; Stop heading TTS - CLEANS BOTH TYPES
; Stop heading TTS with debounce
; Stop heading TTS - ALWAYS restores device (for final stop)
; Stop heading TTS and restore number suppression state - ERROR-PROOF VERSION
; FIXED: Audio lock support - skips device restore when locked
StopHeadingTTS(silent := false) {
    global headingTTSRunning, headingBalconPID, analyticalMode
    global CABLE_DEVICE, REAL_DEVICE, NIRCMD_PATH, currentHeadingTTSFile
    global suppressNumbersEnabled, originalSuppressNumbersState, loopMode
    global Message_HeadingTTSStop, ttsLocked, noteToggleEnabled, manualLoopKill
    global loopHeadingFile, cachedMode4Content, currentHeadingRawStructure
    global audioLockActive, isTransition  ; <-- ADDED for audio lock feature
    
    if (!headingTTSRunning) {
        return
    }
    
    HideSmartTooltip()
    
    manualLoopKill := true
    
    if (headingBalconPID != 0) {
        Process, Close, %headingBalconPID%
        Sleep, 20
    }
    ; RunWait (not Run) — must finish killing stray balcon.exe processes BEFORE
    ; we return, otherwise a transition that immediately launches a NEW balcon.exe
    ; (for note TTS) can race with this taskkill and get killed by it right after starting.
    RunWait, taskkill /IM balcon.exe /F, , Hide
    
    headingTTSRunning := false
    isInGapPhase := false
    
    ; CRITICAL: Restore device ONLY if audio lock is NOT active AND not transitioning
    if (!audioLockActive && !isTransition) {
        Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
        Sleep, 30
    } else {
        ; Stay on CABLE despite stop
        if (analyticalMode) {
            ShowSmartTooltip("🔒 Audio lock - stay on CABLE (heading TTS stopped)", "Debug", 400)
        }
    }
    
    if (loopHeadingFile != "" && FileExist(loopHeadingFile)) {
        FileDelete, %loopHeadingFile%
        loopHeadingFile := ""
    }
    if (currentHeadingTTSFile != "" && FileExist(currentHeadingTTSFile)) {
        FileDelete, %currentHeadingTTSFile%
        currentHeadingTTSFile := ""
    }
    
    if (originalSuppressNumbersState) {
        suppressNumbersEnabled := true
        originalSuppressNumbersState := false
    }
    
    headingBalconPID := 0
    cachedMode4Content := ""
    currentHeadingRawStructure := ""
    
    if (!silent && !isTransition) {
        ShowSmartTooltip("⏹️ " . Message_HeadingTTSStop, "HeadingTTSStop", 1000)
    }
    
    if (!noteToggleEnabled || !ttsLocked) {
        CleanupClipboard()
    }
}

; Timer to detect when heading TTS finishes naturally
; FIXED: Persistent loop for heading TTS
; FIXED: Infinite loop for Heading TTS - NO STOP CONDITIONS
; FIXED: Heading TTS with loop counting
; Timer to detect when heading TTS finishes naturally
; Timer for heading TTS - ALWAYS RESTORES REAL DEVICE
; Timer to detect when heading TTS finishes naturally - SEAMLESS LOOPING
; Timer to detect when heading TTS finishes naturally - WORKING GAP CONTROL
; Timer to detect when heading TTS finishes naturally - NO DEVICE SWITCHING IN LOOP
; Timer to detect when heading TTS finishes naturally - NO DEVICE SWITCHING IN LOOP
; Timer for Heading TTS - PROTECTED from note TTS interference
; Timer for Heading TTS - FIXED: Removed blocking logic that prevented loop restart
; Timer for Heading TTS - FIXED: No device switching during loop gaps
; Timer for Heading TTS - FIXED: Shows finished message & restores device on dual-detection stop
; Timer for Heading TTS - FIXED: Re-processes with current filter on each loop
; Timer for Heading TTS - FIXED: Passes CURRENT speed multiplier
; Timer for Heading TTS - FIXED: Audio lock support
_CheckHeadingTTSFinished:
    global headingTTSRunning, headingBalconPID, headingBalconProcessHandle, Message_HeadingTTSFinished
    global currentHeadingTTSFile, currentHeadingContent, currentHeadingRawStructure, currentHeadingOriginalStructure
    global loopMode, levelAnnounceMode, loopHeadingFile, loopGapMs
    global CABLE_DEVICE, NIRCMD_PATH, analyticalMode, manualLoopKill, isInGapPhase
    global activeTTSType, REAL_DEVICE, cachedMode4Content, speedMultiplier, maxHeadingLevels
    global headingFilterInputValues, audioLockActive, suppressNumbersEnabled, isTransition
    
    if (!headingTTSRunning || headingBalconPID = 0) {
        return
    }
    
    ; FIX: Handle-based check instead of "Process, Exist, %headingBalconPID%".
    ; A PID-only check can be fooled once Windows reuses a closed balcon.exe's
    ; PID for an unrelated process - that used to make the loop silently freeze
    ; after a few restarts. Checking the handle opened at launch time is immune to that.
    if (!HasBalconProcessExited(headingBalconProcessHandle)) {
        return  ; Still genuinely running
    }
    CloseBalconHandle(headingBalconProcessHandle)
    
    if (true) {  ; Process ended
        
        if (manualLoopKill) {
            manualLoopKill := false
            isInGapPhase := false
            activeTTSType := ""
            headingTTSRunning := false
            currentHeadingContent := ""
            
            ; Switch back to REAL on manual stop (only if NOT audio locked AND NOT transitioning)
            if (!audioLockActive && !isTransition) {
                Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
                Sleep, 50
            } else {
                if (analyticalMode) {
                    ShowSmartTooltip("🔒 Staying on CABLE (transition/lock)", "Debug", 400)
                }
            }
            
            if (analyticalMode) {
                ShowSmartTooltip("🛑 Manual stop detected", "Debug", 1200)
            }
            return
        }
        
        
        ; FIX: Do NOT gate on FileExist(loopHeadingFile) here. The temp file is only a
        ; transport for balcon and can be legitimately absent for a brief instant
        ; (another timer's cleanup pass, filesystem/AV latency, etc.) without that
        ; meaning the user wants the loop to stop. The only real "stop" signals are
        ; manualLoopKill (explicit stop), loopMode being off, or having no content
        ; left to speak. If the file happens to be missing, the rewrite block below
        ; already deletes/recreates it unconditionally, so it self-heals instead of
        ; ending the loop.
        if (loopMode && (currentHeadingOriginalStructure != "")) {
            if (analyticalMode) {
                ShowSmartTooltip("⏱️ Gap: " . loopGapMs . "ms", "Debug", 800)
            }
            
            isInGapPhase := true
            activeTTSType := "heading"
            Sleep, % loopGapMs
            isInGapPhase := false
            
            if (manualLoopKill || !loopMode || (currentHeadingOriginalStructure = "")) {
                manualLoopKill := false
                activeTTSType := ""
                headingTTSRunning := false
                return
            }
            
            ShowSmartTooltip("🔄 Looping heading TTS...", "LoopNotification", 1000)
            
            newFiltered := currentHeadingOriginalStructure
            
            if (maxHeadingLevels > 0) {
                newFiltered := FilterHeadingByMaxLevels(currentHeadingOriginalStructure)
            }
            
            if (suppressNumbersEnabled) {
                newFiltered := StripNumbersFromText(newFiltered)
            }
            
            currentHeadingRawStructure := newFiltered
            
            if (levelAnnounceEnabled) {
                if (levelAnnounceMode = 4 || levelAnnounceMode = 6) {
                    processedText := ProcessHeadingStructureHierarchical(currentHeadingRawStructure, speedMultiplier)
                    cachedMode4Content := processedText
                } else if (levelAnnounceMode = 5) {
                    processedText := ProcessHeadingStructureConversational(currentHeadingRawStructure, speedMultiplier)
                } else if (levelAnnounceMode = 7) {
                    processedText := ProcessHeadingStructureMinimal(currentHeadingRawStructure, speedMultiplier)
                } else {
                    processedText := ProcessHeadingStructure(currentHeadingRawStructure, speedMultiplier)
                }
            } else {
                ; F1 is OFF but still apply speed multiplier to content
                processedText := currentHeadingRawStructure
                if (speedMultiplier > 1.0) {
                    processedText := PreprocessTextForSpeed(processedText, speedMultiplier)
                }
            }
            
            currentHeadingContent := processedText
            
            ; ========== FIX: Robust file rewrite with verification ==========
            if (loopHeadingFile = "" || !InStr(loopHeadingFile, "persistent")) {
                loopHeadingFile := A_Temp . "\xmind_loop_heading_persistent.txt"
            }
            
            FileDelete, %loopHeadingFile%
            Loop, 30 {
                if (!FileExist(loopHeadingFile))
                    break
                Sleep, 5
            }
            
            FileAppend, %processedText%, %loopHeadingFile%
            
            fileReady := false
            Loop, 30 {
                if (FileExist(loopHeadingFile)) {
                    FileGetSize, fileSize, %loopHeadingFile%
                    if (fileSize > 0) {
                        fileReady := true
                        break
                    }
                }
                Sleep, 5
            }
            
            if (!fileReady) {
                if (analyticalMode) {
                    ShowSmartTooltip("⚠️ File write failed, retrying...", "Debug", 800)
                }
                FileDelete, %loopHeadingFile%
                Sleep, 50
                FileAppend, %processedText%, %loopHeadingFile%
                Sleep, 50
                if (FileExist(loopHeadingFile)) {
                    FileGetSize, fileSize, %loopHeadingFile%
                    if (fileSize > 0) {
                        fileReady := true
                    }
                }
            }
            
            if (!fileReady) {
                if (analyticalMode) {
                    ShowSmartTooltip("❌ File persistently unavailable, skipping iteration", "Debug", 1200)
                }
                return
            }
            
            ; ========== FIX: NO device switch on loop restart ==========
            ; Device is ALREADY on CABLE from initial TTS start.
            ; Stay on CABLE during all loop iterations.
            ; Only switch back to REAL on manual stop (above) or loop termination (below).
            if (analyticalMode) {
                ShowSmartTooltip("🔁 Loop restart (no device switch)", "Debug", 400)
            }
            
            Run, % """" . balconPath . """" . " -n " . Chr(34) . balconVoice . Chr(34) . " -s " . balconSpeed . " -p " . balconPitch . " -v " . balconVolume . " -f " . Chr(34) . loopHeadingFile . Chr(34), , Hide, headingBalconPID
            headingBalconProcessHandle := OpenBalconHandle(headingBalconPID)
            headingTTSRunning := true
            return
        }
        
        ; Loop is OFF or conditions failed - TTS finished naturally
        ; Switch back to REAL (only if NOT audio locked)
        if (!audioLockActive) {
            Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
            Sleep, 50
        } else {
            if (analyticalMode) {
                ShowSmartTooltip("🔒 Audio lock - stay on CABLE (finished)", "Debug", 400)
            }
        }
        
        isInGapPhase := false
        activeTTSType := ""
        headingTTSRunning := false
        currentHeadingContent := ""
        currentHeadingRawStructure := ""
        currentHeadingOriginalStructure := ""
        cachedMode4Content := ""
        
        if (!loopMode) {
            if (loopHeadingFile != "" && FileExist(loopHeadingFile)) {
                FileDelete, %loopHeadingFile%
                loopHeadingFile := ""
            }
            if (currentHeadingTTSFile != "" && FileExist(currentHeadingTTSFile)) {
                FileDelete, %currentHeadingTTSFile%
                currentHeadingTTSFile := ""
            }
        }
        
        headingBalconPID := 0
        ShowSmartTooltip("✅ " . Message_HeadingTTSFinished, "HeadingTTSFinished", 1200)
    }
return

; ===========================================================
; ENHANCED LEVEL SELECTION SYSTEM
; ===========================================================
; PURPOSE: Provide 3-second window to select level announcement mode
; FEATURES: Countdown timer, six numbering modes, double-press detection for keys 4 and 5

; Timer for level mode selection countdown
_LevelSelectionCountdown:
    global levelSelectionTimer, levelSelectionActive, levelAnnounceMode
    global Message_Countdown3, Message_Countdown2, Message_Countdown1, Message_DefaultSelected
    
    if (!levelSelectionActive) {
        return
    }
    
    levelSelectionTimer -= 1
    
    if (levelSelectionTimer = 3) {
        ShowSmartTooltip(Message_Countdown3, "Countdown3", 1000)
    } else if (levelSelectionTimer = 2) {
        ShowSmartTooltip(Message_Countdown2, "Countdown2", 1000)
    } else if (levelSelectionTimer = 1) {
        ShowSmartTooltip(Message_Countdown1, "Countdown1", 1000)
    } else if (levelSelectionTimer <= 0) {
        ; Time's up - set default mode (Numbers)
        levelSelectionActive := false
        levelAnnounceMode := 1
        ShowSmartTooltip(Message_DefaultSelected, "DefaultSelected", 1500)
        SetTimer, _LevelSelectionCountdown, Off
    }
return

; Start level mode selection with 3-second countdown
StartLevelModeSelection() {
    global levelSelectionActive, levelSelectionTimer, levelAnnounceMode
    global Message_LevelOn, analyticalMode
    
    levelSelectionActive := true
    levelSelectionTimer := 3  ; 3-second countdown
    
    ShowSmartTooltip(Message_LevelOn, "LevelOn", 1500)
    
    ; Start countdown timer
    SetTimer, _LevelSelectionCountdown, 1000
    
    if (analyticalMode) {
        ShowSmartTooltip("⏱️ LEVEL MODE SELECTION ACTIVE - Press 1/2/3/4/5 (or 4/5 twice for Conversational/Hybrid)", "Debug", 800)
    }
}

; Select level mode during the 3-second window
; ===========================================================
; SELECT LEVEL MODE WITH CONFIRMATION TOOLTIP
; ===========================================================
SelectLevelMode(mode) {
    global levelSelectionActive, levelSelectionTimer, levelAnnounceMode, analyticalMode
    global Message_ModeNumbers, Message_ModeDotted, Message_ModeAlphabet, Message_ModeHierarchy
    global Message_ModeConversational, Message_ModeHybridLoop, Message_ModeMinimal
    
    if (!levelSelectionActive) {
        return
    }
    
    ; Stop all timers and reset counters
    levelSelectionActive := false
    SetTimer, _LevelSelectionCountdown, Off
    SetTimer, ResetKey1Press, Off
    SetTimer, ResetKey4Press, Off
    SetTimer, ResetKey5Press, Off
    
    key1PressCount := 0
    key4PressCount := 0
    key4LastPressTime := 0
    key5PressCount := 0
    key5LastPressTime := 0
    
    levelAnnounceMode := mode
    
    ; Show confirmation with proper tooltip styling
    if (mode = 1) {
        ShowSmartTooltip(Message_ModeNumbers, "ModeNumbers", 1500)
    } else if (mode = 2) {
        ShowSmartTooltip(Message_ModeDotted, "ModeDotted", 1500)
    } else if (mode = 3) {
        ShowSmartTooltip(Message_ModeAlphabet, "ModeAlphabet", 1500)
    } else if (mode = 4) {  ; 4 key single press
        ShowSmartTooltip(Message_ModeHierarchy, "ModeHierarchy", 1500)
    } else if (mode = 5) {  ; 4 key double press
        ShowSmartTooltip(Message_ModeConversational, "ModeConversational", 1500)
    } else if (mode = 6) {  ; 5 key double press
        ShowSmartTooltip(Message_ModeHybridLoop, "ModeHybridLoop", 1500)
    } else if (mode = 7) {  ; 1 key double press
        ShowSmartTooltip(Message_ModeMinimal, "ModeMinimal", 1500)
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("✅ LEVEL MODE SET: " . mode, "Debug", 800)
    }
}

ResetKey1Press:
    global key1PressCount
    if (key1PressCount = 1) {
        key1PressCount := 0
        SelectLevelMode(1)  ; Single press = Mode 1 (Numbers)
    }
return

; Timer to reset key 4 press count (single press confirmation)
ResetKey4Press:
    ; Single press confirmed - select mode 4
    global key4PressCount
    if (key4PressCount = 1) {
        key4PressCount := 0
        SelectLevelMode(4)
    }
return

; Timer to reset key 5 press count (single press confirmation)
ResetKey5Press:
    global key5PressCount, levelSelectionActive, levelAnnounceMode, analyticalMode, Message_ModeHierarchy
    
    if (key5PressCount = 1) {
        key5PressCount := 0
        
        ; STOP THE COUNTDOWN
        levelSelectionActive := false
        SetTimer, _LevelSelectionCountdown, Off
        
        ; Set mode to 4 (hierarchical)
        levelAnnounceMode := 4
        
        ; Show PURPLE tooltip for 5-key
        ShowSmartTooltip(Message_ModeHierarchy, "ModeHierarchyAlt", 1500)
        
        if (analyticalMode) {
            ShowSmartTooltip("✅ LEVEL MODE SET: 4 (from 5 key)", "Debug", 800)
        }
    }
return

; Select level mode from 5 key (alternative hierarchical)
SelectLevelModeAlt(mode) {
    global levelSelectionActive, levelAnnounceMode, analyticalMode
    
    if (!levelSelectionActive) {
        return
    }
    
    levelSelectionActive := false
    SetTimer, _LevelSelectionCountdown, Off
    SetTimer, ResetKey4Press, Off
    SetTimer, ResetKey5Press, Off
    key4PressCount := 0
    key5PressCount := 0
    
    levelAnnounceMode := mode
    
    ; Show Mode 4 content but with 5-key colors
    ShowSmartTooltip(Message_ModeHierarchy, "ModeHierarchyAlt", 1500)
    
    if (analyticalMode) {
        ShowSmartTooltip("✅ LEVEL MODE SET: " . mode . " (from 5 key)", "Debug", 800)
    }
}

; Hotkeys for mode selection (only active during selection window)
; ===========================================================
; LEVEL MODE SELECTION HOTKEYS
; ===========================================================
#If levelSelectionActive

1::
    global key1PressCount, key1LastPressTime, key1DoublePressThreshold
    
    now := A_TickCount
    if (key1PressCount = 1 && now - key1LastPressTime < key1DoublePressThreshold)
    {
        ; ** DOUBLE PRESS → MODE 7 (Minimal: "N:") **
        key1PressCount := 0
        SetTimer, ResetKey1Press, Off
        SelectLevelMode(7)  ; ** NEW: Minimal numbering **
        return
    }
    
    ; ** First press – wait for potential double press **
    key1PressCount := 1
    key1LastPressTime := now
    SetTimer, ResetKey1Press, %key1DoublePressThreshold%
return

2::SelectLevelMode(2)  ; Dotted mode

3::SelectLevelMode(3)  ; Alphabet mode

4::
    global key4PressCount, key4LastPressTime, key4DoublePressThreshold
    
    now := A_TickCount
    if (key4PressCount = 1 && now - key4LastPressTime < key4DoublePressThreshold)
    {
        ; DOUBLE PRESS → Mode 5 (Conversational)
        key4PressCount := 0
        SetTimer, ResetKey4Press, Off
        SelectLevelMode(5)  ; Conversational
        return
    }
    
    ; Single press – start detection window
    key4PressCount := 1
    key4LastPressTime := now
    SetTimer, ResetKey4Press, %key4DoublePressThreshold%
return

5::
    global key5PressCount, key5LastPressTime, key5DoublePressThreshold
    
    now := A_TickCount
    if (key5PressCount = 1 && now - key5LastPressTime < key5DoublePressThreshold)
    {
        ; DOUBLE PRESS → Mode 6 (Hybrid Loop)
        key5PressCount := 0
        SetTimer, ResetKey5Press, Off
        SelectLevelMode(6)  ; Hybrid Loop
        return
    }
    
    ; Single press – start detection window
    key5PressCount := 1
    key5LastPressTime := now
    SetTimer, ResetKey5Press, %key5DoublePressThreshold%
return

#If

; ===========================================================
; FILE SAFETY SYSTEM - PREVENTS 10K+ FILE SPAMMING
; ===========================================================
CheckTempFileLimit() {
    global maxTempFilesAllowed, analyticalMode
    
    ; Count xmind temp files
    filePattern := A_Temp . "\xmind_*.txt"
    fileCount := 0
    
    Loop, Files, %filePattern%
        fileCount++
    
    ; Log count if analytical mode
    if (analyticalMode) {
        ShowSmartTooltip("📁 Active files: " . fileCount, "Debug", 500)
    }
    
    ; CRITICAL: Stop if exceeding limit
    if (fileCount > maxTempFilesAllowed) {
        return fileCount
    }
    
    return fileCount
}

; ===========================================================
; IMMEDIATE FILE CLEANUP - Runs when TTS stops
; ===========================================================
ImmediateCleanup(ttsType := "") {
    global currentNoteTTSFile, currentHeadingTTSFile, analyticalMode
    
    ; Clean files for the specified TTS type
    if (ttsType = "note" || ttsType = "") {
        if (currentNoteTTSFile != "" && FileExist(currentNoteTTSFile)) {
            FileDelete, %currentNoteTTSFile%
            currentNoteTTSFile := ""
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Note file deleted", "Debug", 500)
            }
        }
    }
    
    if (ttsType = "heading" || ttsType = "") {
        if (currentHeadingTTSFile != "" && FileExist(currentHeadingTTSFile)) {
            FileDelete, %currentHeadingTTSFile%
            currentHeadingTTSFile := ""
            if (analyticalMode) {
                ShowSmartTooltip("🧹 Heading file deleted", "Debug", 500)
            }
        }
    }
}

; ===========================================================
; AUTOMATIC TTS CONTROL SYSTEM
; ===========================================================
; PURPOSE: Handle transitions between heading TTS and note TTS
; FEATURES: Automatic starting of note TTS after heading TTS stops

; Timer to check for pending note TTS starts after stopping heading TTS
_CheckPendingNoteTTS:
    global pendingNoteTTSAfterHeadingStop, headingTTSRunning, noteOpen, analyticalMode
    
    if (pendingNoteTTSAfterHeadingStop && !headingTTSRunning && noteOpen) {
        ; Clear the flag immediately
        pendingNoteTTSAfterHeadingStop := false
        
        if (analyticalMode) {
            ShowSmartTooltip("🚀 STARTING NOTE TTS AFTER HEADING STOP", "Debug", 800)
        }
        
        ; Start note TTS
        StartNoteTTSAfterHeadingStop()
    }
return

; Start note TTS after stopping heading TTS
StartNoteTTSAfterHeadingStop() {
    global Message_TTSStart, selectionSleep, copySleep, analyticalMode
    global Message_NoteEmpty  ; Need this for error message
    
    ; Use DIRECT clipboard retrieval (faster, no hanging retry loops)
    SwitchToXMindClipboard()
    Clipboard := ""
    Send, ^a
    Sleep, %selectionSleep%
    Send, ^c
    Sleep, %copySleep%
    ClipWait, 0.3, 1
    noteContent := Clipboard
    Send, ^{Home}
    SwitchToSystemClipboard()
    
    ; CRITICAL: Check if content is actually present
    if (noteContent = "" || Trim(noteContent) = "") {
        HideSmartTooltip()
        ShowSmartTooltip("❌ " . Message_NoteEmpty, "NoteEmpty", 1200)
        return
    }
    
    ; Store content for loop mode
    currentNoteContent := noteContent
    
    ; Run TTS with the captured note content
    if (SpeakWithBalconSmart(noteContent, "note")) {
        balconRunning := true
        ShowSmartTooltip("📋 " . Message_TTSStart, "TTSStart", 800)
        
        if (analyticalMode) {
            ShowSmartTooltip("✅ NOTE TTS STARTED AFTER HEADING STOP", "Debug", 800)
        }
    }
}

; ===========================================================
; DUAL DETECTION SYSTEM
; ===========================================================
; PURPOSE: Detect when user navigates to different topics during TTS
; STRATEGY: Real-time detection during gestures + background polling
; BENEFITS: Automatic TTS stopping when a note of a different heading is opened, if the currently running note TTS is of different heading as well

; Start dual detection system when TTS begins
StartHeadingDetection() {
    global headingDetectionActive, backgroundDetectionActive, originalHeading, balconRunning
    global headingHashTable, dualDetectionEnabled, analyticalMode
    
    if (balconRunning && dualDetectionEnabled) {
        headingDetectionActive := true
        backgroundDetectionActive = true
        
        ; Clear previous hash table
        headingHashTable := {}
        
        if (analyticalMode) {
            ShowSmartTooltip("🚀 DUAL DETECTION ACTIVATED", "Debug", 800)
            ShowSmartTooltip("Real-time + Background scanning started", "Debug", 800)
        }
    }
}

StopHeadingDetection() {
    global headingDetectionActive, backgroundDetectionActive, differentHeadingDetected
    global headingHashTable, analyticalMode
    
    headingDetectionActive := false
    backgroundDetectionActive := false
    differentHeadingDetected := false
    
    ; Clear hash table
    headingHashTable := {}
    
    if (analyticalMode) {
        ShowSmartTooltip("🛑 DUAL DETECTION STOPPED", "Debug", 800)
    }
}

; Background detection system (runs every 50ms)
_BackgroundHeadingCheck:
    global backgroundDetectionActive, balconRunning, originalHeading, differentHeadingDetected
    global headingHashTable, analyticalMode, dualDetectionEnabled
    
    if (backgroundDetectionActive && balconRunning && originalHeading != "" && dualDetectionEnabled) {
        ; Ultra-fast background heading check
        currentHeading := GetCurrentHeadingFast()
        
        if (currentHeading != "" && currentHeading != originalHeading) {
            ; Use hash table for instant detection
            if (!headingHashTable.HasKey(currentHeading)) {
                headingHashTable[currentHeading] = true
                differentHeadingDetected = true
                
                if (analyticalMode) {
                    truncatedHeading := TruncateString(currentHeading, 50)
                    ShowSmartTooltip("🎯 BG DETECT: " . truncatedHeading, "Debug", 800)
                }
            }
        } else if (currentHeading = originalHeading) {
            differentHeadingDetected := false
        }
    }
return

; Ultra-fast heading detection for background system
GetCurrentHeadingFast() {
    ; Minimal version for background checks - no clipboard backup/restore
    Clipboard := ""
    Send, ^c
    Sleep, 8  ; Ultra-short wait
    if (Clipboard != "") {
        ; Mark this heading content for cleanup
        MarkClipboardContent(Clipboard)
        return Trim(Clipboard)
    }
    return ""
}

; ===========================================================
; DEBUG AND DIAGNOSTICS SYSTEM
; ===========================================================
; PURPOSE: Provide debugging information for developers
; USAGE: Enabled via F11 key, shows detailed state information

; Create debug window for analytical information
CreateDebugWindow() {
    global originalHeading, analyticalMode, dualDetectionEnabled
    if (!analyticalMode || !dualDetectionEnabled)
        return
    
    ; Truncate the original heading for display
    displayHeading := TruncateString(originalHeading, 50)
    if (displayHeading = "") {
        displayHeading := "[Empty or not captured]"
    }
        
    ; Create a simple GUI window for debug info
    Gui, Debug:New, +AlwaysOnTop +ToolWindow, TTS Debug Info
    Gui, Debug:Add, Text,, TTS Stopped - Analysis Info:
    Gui, Debug:Add, Text,, Original Heading: %displayHeading%
    Gui, Debug:Add, Button, gCloseDebugWindow, Close
    Gui, Debug:Show, AutoSize
}

; Close debug window
CloseDebugWindow:
    Gui, Debug:Destroy
return

; ===========================================================
; FOCUS MONITORING AND APPLICATION MANAGEMENT
; ===========================================================
; PURPOSE: Handle application focus changes and cleanup
; FEATURES: Auto-stop TTS on focus loss, restore detection on focus regain

; Monitor application focus and manage TTS accordingly
_CheckAppFocusTimer:
    global balconRunning, ttsLocked, noteToggleEnabled, headingTTSRunning
    global middleZoomActive, headingDetectionActive, backgroundDetectionActive
    global analyticalMode, dualDetectionEnabled, f4f5OverrideActive, headingFilterGUIVisible
    
    ; Stop TTS on focus loss if not locked
    if (balconRunning && !WinActive("ahk_exe XMind.exe") && !ttsLocked) {
        CleanupClipboard()
        StopBalcon()
    }
    
    if (headingTTSRunning && !WinActive("ahk_exe XMind.exe") && !ttsLocked) {
        StopHeadingTTS()
    }
    
    ; Turn off zoom mode when XMind loses focus
    if (middleZoomActive && !WinActive("ahk_exe XMind.exe")) {
        middleZoomActive := false
        ShowSmartTooltip(Message_ZoomOff, "ZoomOff", 500)
    }
    
    ; Restore dual detection on focus regain
    if (balconRunning && WinActive("ahk_exe XMind.exe") && noteToggleEnabled) {
        if (!headingDetectionActive || !backgroundDetectionActive) {
            StartHeadingDetection()
            if (analyticalMode && dualDetectionEnabled) {
                ShowSmartTooltip("🔄 DUAL DETECTION RESTORED on focus regain", "Debug", 800)
            }
        }
    }
    
    ; ** PAUSE/RESUME LIVE RELOAD TIMER **
    if (!WinActive("ahk_exe XMind.exe") && f4f5OverrideActive) {
        SetTimer, _LiveReloadF4F5Control, Off
    } else if (WinActive("ahk_exe XMind.exe") && f4f5OverrideActive && headingFilterGUIVisible) {
        SetTimer, _LiveReloadF4F5Control, 100
    }
return

; Comprehensive cleanup before script exit
; Comprehensive cleanup before script exit
; FIXED: Audio lock override - ALWAYS restores real device on exit
CleanupBeforeExit(ExitReason, ExitCode) {
    global CABLE_DEVICE, REAL_DEVICE, NIRCMD_PATH
    global audioLockActive  ; <-- ADDED for audio lock feature (but we override it)
    
    ; ALWAYS restore real audio device on script exit (OVERRIDE audio lock)
    Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
    Sleep, 100

    ; Close the Python AI Note Assistant together with this script (it
    ; otherwise just hides its window and keeps running in the background --
    ; see F11 above). Ask it to shut down itself first (so its own browser
    ; cleanup runs), then fall back to force-killing it by PID if it doesn't
    ; exit in time.
    global XMindAI_BridgeDir, XMindAI_BridgeExit, XMindAI_PID
    if (XMindAI_PID != 0) {
        FileCreateDir, %XMindAI_BridgeDir%
        FileDelete, %XMindAI_BridgeExit%
        FileAppend, exit, %XMindAI_BridgeExit%

        Loop, 20 {
            Process, Exist, %XMindAI_PID%
            if (!ErrorLevel) {
                break
            }
            Sleep, 100
        }
        Process, Exist, %XMindAI_PID%
        if (ErrorLevel) {
            ; Still running after ~2 sec -- it may be busy (mid AI request)
            ; or the poll missed the flag. Don't leave it behind.
            Process, Close, %XMindAI_PID%
        }
        XMindAI_PID := 0
    }

    ; Import all global variables
    global noteOpen, noteControl, noteWindowID, middleZoomActive, balconRunning, originalHeading, differentHeadingDetected, balconPID
    global headingDetectionActive, backgroundDetectionActive, headingTTSRunning, headingBalconPID
    global pendingNoteTTSAfterHeadingStop, levelSelectionActive
    global key4PressCount, key4LastPressTime, key5PressCount, key5LastPressTime
    global suppressNumbersEnabled, loopMode, currentNoteContent, currentHeadingContent
    global currentHeadingRawStructure, loopPatternToggle, loopNoteFile, loopHeadingFile
    global currentNoteTTSFile, currentHeadingTTSFile
    
    ; Cleanup clipboard system
    CleanupClipboard()
    
    ; Delete all temporary files
    FileDelete, %A_Temp%\xmind_tts_*.txt
    FileDelete, %A_Temp%\xmind_structure_*.txt
    
    ; Delete loop files if they exist
    if (loopNoteFile != "" && FileExist(loopNoteFile)) {
        FileDelete, %loopNoteFile%
    }
    if (loopHeadingFile != "" && FileExist(loopHeadingFile)) {
        FileDelete, %loopHeadingFile%
    }
    
    ; Delete active TTS files
    if (currentNoteTTSFile != "" && FileExist(currentNoteTTSFile)) {
        FileDelete, %currentNoteTTSFile%
    }
    if (currentHeadingTTSFile != "" && FileExist(currentHeadingTTSFile)) {
        FileDelete, %currentHeadingTTSFile%
    }
    
    ; Stop running TTS processes
    if (balconRunning) {
        Process, Close, %balconPID%
        Sleep, 20
        Run, taskkill /IM balcon.exe /F, , Hide
    }
    if (headingTTSRunning) {
        Process, Close, %headingBalconPID%
        Sleep, 20
        Run, taskkill /IM balcon.exe /F, , Hide
    }
    
    ; Reset all state variables
    noteOpen := false
    noteControl := ""
    noteWindowID := ""
    middleZoomActive := false
    shiftZoomActive := false
    originalHeading := ""
    differentHeadingDetected := false
    headingDetectionActive := false
    backgroundDetectionActive := false
    headingHashTable := {}
    balconPID := 0
    headingBalconPID := 0
    pendingNoteTTSAfterHeadingStop := false
    levelSelectionActive := false
    key4PressCount := 0
    key4LastPressTime := 0
    key5PressCount := 0
    key5LastPressTime := 0
    suppressNumbersEnabled := false
    loopMode := false
    currentNoteContent := ""
    currentHeadingContent := ""
    currentHeadingRawStructure := ""
    loopPatternToggle := false
    loopNoteFile := ""
    loopHeadingFile := ""
    currentNoteTTSFile := ""
    currentHeadingTTSFile := ""
    
    ; Reset audio lock on exit
    audioLockActive := false
    
    ; Hide any active tooltips
    HideSmartTooltip()
    
    ; Close debug window if open
    Gui, Debug:Destroy
    
    CleanupChunkFiles()
}

; ===========================================================
; CORE XMIND INTERACTION FUNCTIONS
; ===========================================================
; PURPOSE: Handle XMind-specific window management and interactions
; FEATURES: Note detection, zoom control, focus management

; Check if current window is a valid XMind window
IsValidXMindWindow() {
    IfWinNotActive, ahk_exe XMind.exe
        return false
    WinGetTitle, t, A
    return (t != "")
}

; Update note focus state based on current control and window
UpdateNoteFocusCheck() {
    global noteOpen, noteControl, noteWindowID
    ControlGetFocus, curControl, A
    WinGet, curWinID, ID, A
    
    ; FIXED BUG: Check if note was closed by canvas click
    if (noteOpen && curWinID = noteWindowID && curControl != noteControl && noteControl != "") {
        ; Note was closed (control focus changed from note to canvas)
        noteOpen := false
        noteControl := ""
        noteWindowID := ""
        return
    }
    
    if (noteOpen && curWinID != noteWindowID) {
        noteOpen := false
        noteControl := ""
        noteWindowID := ""
        return
    }
    if (noteOpen && curControl != "") {
        noteControl := curControl
    }
}

; Recover from error state by resetting all variables
RecoverFromError() {
    global noteOpen, noteControl, noteWindowID, middleZoomActive, balconRunning, originalHeading, differentHeadingDetected, balconPID
    global headingDetectionActive, backgroundDetectionActive, headingTTSRunning, headingBalconPID
    global pendingNoteTTSAfterHeadingStop, levelSelectionActive
    global key4PressCount, key4LastPressTime, key5PressCount, key5LastPressTime
    global suppressNumbersEnabled, loopMode, currentNoteContent, currentHeadingContent
    global currentHeadingRawStructure, loopPatternToggle
    
    noteOpen := false
    noteControl := ""
    noteWindowID := ""
    middleZoomActive := false
    pendingNoteTTSAfterHeadingStop := false
    levelSelectionActive := false
    key4PressCount := 0
    key4LastPressTime := 0
    key5PressCount := 0
    key5LastPressTime := 0
    ; REMOVED: suppressNumbersEnabled := false
    ; REMOVED: loopMode := false  ; Loop mode now PERSISTENT - only F3 controls it
    currentNoteContent := ""
    currentHeadingContent := ""
    currentHeadingRawStructure := ""
    loopPatternToggle := false
    if (balconRunning) {
        StopBalcon()
    }
    if (headingTTSRunning) {
        StopHeadingTTS()
    }
    headingDetectionActive := false
    backgroundDetectionActive := false
}

; Show zoom tooltip message with "ZOOM(IN + OUT)" on the first line and "random % per tick".
ShowZoomStatus() {
    global middleZoomActive
    
    if (middleZoomActive) {
        ShowSmartTooltip("ZOOM(IN + OUT): ON`n? % per tick", "ZoomOn", 1600)
    }
}

; ===========================================================
; HOTKEY IMPLEMENTATIONS
; ===========================================================
; PURPOSE: Define all keyboard and mouse hotkey behaviors
; ORGANIZATION: Grouped by functionality and input device

; Only activate these hotkeys when XMind is the active window
#IfWinActive ahk_exe XMind.exe

; Timer to check note focus state
_CheckNoteFocusTimer:
    IfWinActive, ahk_exe XMind.exe
        UpdateNoteFocusCheck()
return

; ---------------- MOUSE WHEEL BEHAVIOR (CTRL OR SHIFT ZOOM) ----------------
; PURPOSE: Zoom ONLY when XButton1 OFF + zoom mode ON. Otherwise normal scroll.

WheelUp::
    if (!IsValidXMindWindow()) {
        Send, {WheelUp}
        return
    }
    global noteToggleEnabled, shiftZoomActive, noteOpen

    ; XButton1 ON
    if (noteToggleEnabled) {
        UpdateNoteFocusCheck()
        if (noteOpen) {
            ; Note is open: Up arrow to navigate text
            Send, {Up}
        } else {
            ; Note is closed: Zoom in (Ctrl+Wheel)
            Send, {Ctrl down}
            Sleep, 30
            Send, {WheelUp}
            Sleep, 30
            Send, {Ctrl up}
        }
        return
    }

    ; XButton1 OFF + Shift Scroll ON: Horizontal scroll (Shift+Wheel)
    if (shiftZoomActive) {
        Send, {Shift down}
        Sleep, 30
        Send, {WheelUp}
        Sleep, 30
        Send, {Shift up}
        return
    }

    ; XButton1 OFF + Shift Scroll OFF: Normal scroll (pass through to XMind)
    Send, {WheelUp}
return

WheelDown::
    if (!IsValidXMindWindow()) {
        Send, {WheelDown}
        return
    }
    global noteToggleEnabled, shiftZoomActive, noteOpen

    ; XButton1 ON
    if (noteToggleEnabled) {
        UpdateNoteFocusCheck()
        if (noteOpen) {
            ; Note is open: Down arrow to navigate text
            Send, {Down}
        } else {
            ; Note is closed: Zoom out (Ctrl+Wheel)
            Send, {Ctrl down}
            Sleep, 30
            Send, {WheelDown}
            Sleep, 30
            Send, {Ctrl up}
        }
        return
    }

    ; XButton1 OFF + Shift Scroll ON: Horizontal scroll (Shift+Wheel)
    if (shiftZoomActive) {
        Send, {Shift down}
        Sleep, 30
        Send, {WheelDown}
        Sleep, 30
        Send, {Shift up}
        return
    }

    ; XButton1 OFF + Shift Scroll OFF: Normal scroll (pass through to XMind)
    Send, {WheelDown}
return

; ---------------- XButton1 (Mouse4) - MASTER TOGGLE ----------------
; PURPOSE: Toggle all features ON/OFF. 
; - When turning OFF with F12 OFF: Stops TTS silently, then shows "Features: OFF"
; - When turning OFF with F12 ON: Does NOT stop TTS (lock active), shows "Features: OFF"
; - When turning ON: Shows "Features: ON"



; ============================================
; XButton1 Toggle
; ============================================
XButton1::
    if (!IsValidXMindWindow()) {
        Send, {XButton1}
        return
    }
    global noteToggleEnabled, gestureToggleEnabled, middleZoomActive, noteOpen, noteControl, noteWindowID, balconRunning, ttsLocked
    global Message_FeaturesOn, Message_FeaturesOff
    global headingDetectionActive, analyticalMode, dualDetectionEnabled, headingTTSRunning, pendingNoteTTSAfterHeadingStop
    global key4PressCount, key4LastPressTime, key5PressCount, key5LastPressTime
    global suppressNumbersEnabled, loopMode
    global SoundPath_On, SoundPath_Off
    global XMindAI_BridgeDir, XMindAI_BridgeRequest, XMindAI_BridgeFlag, XMindAI_BridgePasteReady, XMindAI_BridgeCancel
    
    noteToggleEnabled := !noteToggleEnabled
    gestureToggleEnabled := noteToggleEnabled
    
    if (!noteToggleEnabled) {
        ; Turning features OFF
        
        if (!ttsLocked) {
            if (balconRunning) {
                StopBalcon(true)
            }
            if (headingTTSRunning) {
                StopHeadingTTS(true)
            }
        }
        
        noteOpen := false
        noteControl := ""
        noteWindowID := ""
        pendingNoteTTSAfterHeadingStop := false
        levelSelectionActive := false
        SetTimer, _LevelSelectionCountdown, Off
        key4PressCount := 0
        key4LastPressTime := 0
        key5PressCount := 0
        key5LastPressTime := 0
        
        if (!ttsLocked) {
            CleanupClipboard()
        }
        
        headingDetectionActive := false
        backgroundDetectionActive := false
        
        ; NOTE: turning features OFF no longer kills an in-flight F11 AI
        ; session. It now takes an explicit XButton2 press while features are
        ; OFF (see the XButton2 handler / TerminateF11Session below).
        
        ; >>> OFF SOUND <<<
        if (FileExist(SoundPath_Off)) {
            SoundPlay, %SoundPath_Off%
        }
        
        ShowSmartTooltip(Message_FeaturesOff, "FeaturesOff", 800)
    } else {
        ; Turning features ON
        middleZoomActive := false
        shiftZoomActive := false
        
        if (balconRunning && (!headingDetectionActive || !backgroundDetectionActive)) {
            StartHeadingDetection()
            if (analyticalMode) {
                ShowSmartTooltip("🔄 DUAL DETECTION RESTORED on XButton1 ON", "Debug", 800)
            }
        }
        
        ; >>> ON SOUND <<<
        if (FileExist(SoundPath_On)) {
            SoundPlay, %SoundPath_On%
        }
        
        ShowSmartTooltip(Message_FeaturesOn, "FeaturesOn", 800)
    }
return

; ---------------- F11 AI SESSION TERMINATION ----------------
; PURPOSE: An "F11 session" is an AI Node/Note request that is queued,
; being processed by Python, or has a reply waiting to be pasted. It is now
; terminated by XButton2 (Shift Scroll) while XButton1 features are OFF --
; NOT by XButton1 turning OFF anymore.

IsF11SessionOngoing() {
    global XMindAI_BridgeBusy, XMindAI_BridgeFlag, XMindAI_BridgeRequest, XMindAI_BridgePasteReady
    if (FileExist(XMindAI_BridgeBusy) != "")
        return true
    if (FileExist(XMindAI_BridgeFlag) != "")
        return true
    if (FileExist(XMindAI_BridgeRequest) != "")
        return true
    if (FileExist(XMindAI_BridgePasteReady) != "")
        return true
    return false
}

; Returns true if a session was ongoing (and has now been terminated).
TerminateF11Session() {
    global XMindAI_BridgeDir, XMindAI_BridgeRequest, XMindAI_BridgeFlag, XMindAI_BridgePasteReady, XMindAI_BridgeCancel
    wasOngoing := IsF11SessionOngoing()
    ; Delete whatever is pending on our side (a request Python hasn't picked
    ; up yet, or a reply waiting to be pasted), then drop cancel.request so
    ; Python abandons its side too (see _poll_cancel/_handle_cancel_request
    ; in the .py).
    FileDelete, %XMindAI_BridgeFlag%
    FileDelete, %XMindAI_BridgeRequest%
    FileDelete, %XMindAI_BridgePasteReady%
    FileCreateDir, %XMindAI_BridgeDir%
    FileDelete, %XMindAI_BridgeCancel%
    FileAppend, cancel, %XMindAI_BridgeCancel%
    return wasOngoing
}

; ---------------- F1 - ENHANCED LEVEL ANNOUNCEMENT TOGGLE ----------------
; PURPOSE: Toggle level numbering for heading TTS with mode selection

F1::
    global levelAnnounceEnabled, Message_LevelOff, levelSelectionActive
    global analyticalMode
    
    if (levelAnnounceEnabled) {
        ; If it's already on, turn it off
        levelAnnounceEnabled := false
        levelSelectionActive := false  ; Cancel any active selection
        SetTimer, _LevelSelectionCountdown, Off
        ShowSmartTooltip(Message_LevelOff, "LevelOff", 1500)
    } else {
        ; Turn it on directly without safety check
        levelAnnounceEnabled := true
        StartLevelModeSelection()
    }
return

; ---------------- F2 - NUMBER SUPPRESSION TOGGLE ----------------
; PURPOSE: Prevent TTS from reading numbers in content while preserving F1 level announcements

F2::
    global suppressNumbersEnabled, Message_SuppressNumbersOn, Message_SuppressNumbersOff, analyticalMode
    
    suppressNumbersEnabled := !suppressNumbersEnabled
    
    if (suppressNumbersEnabled) {
        ShowSmartTooltip("🔇 " . Message_SuppressNumbersOn, "SuppressNumbersOn", 1500)
    } else {
        ShowSmartTooltip("🔊 " . Message_SuppressNumbersOff, "SuppressNumbersOff", 1500)
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("🔢 NUMBER SUPPRESSION: " . (suppressNumbersEnabled ? "ON" : "OFF"), "Debug", 800)
    }
return

; ---------------- F3 - LOOP MODE TOGGLE (PERSISTENT GLOBAL) ----------------
; PURPOSE: Enable/disable looping for all TTS operations
; FIXED: Audio lock support - skips device switch when locked

F3::  ; Loop Mode Toggle
    global loopMode, Message_LoopOn, Message_LoopOff, analyticalMode
    global loopNoteFile, loopHeadingFile, currentNoteTTSFile, currentHeadingTTSFile
    global cachedMode4Content, loopNoteJustRestarted, loopHeadingJustRestarted
    global balconRunning, headingTTSRunning, CABLE_DEVICE, REAL_DEVICE, NIRCMD_PATH
    global audioLockActive  ; <-- ADDED for audio lock feature
    
    loopMode := !loopMode
    
    if (!loopMode) {
        ; Turn OFF - cleanup
        if (loopNoteFile != "" && FileExist(loopNoteFile)) {
            FileDelete, %loopNoteFile%
            loopNoteFile := ""
        }
        if (loopHeadingFile != "" && FileExist(loopHeadingFile)) {
            FileDelete, %loopHeadingFile%
            loopHeadingFile := ""
        }
        cachedMode4Content := ""
        loopNoteJustRestarted := false
        loopHeadingJustRestarted := false
        
        ShowSmartTooltip("⏹️ " . Message_LoopOff, "LoopOff", 1500)
        if (analyticalMode) {
            ShowSmartTooltip("LOOP DISABLED", "Debug", 1000)
        }
        
        ; RESTORE REAL DEVICE WHEN LOOP TURNS OFF (only if NOT audio locked)
        if (!audioLockActive && (balconRunning || headingTTSRunning)) {
            Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
            Sleep, 100
        } else if (audioLockActive && (balconRunning || headingTTSRunning)) {
            if (analyticalMode) {
                ShowSmartTooltip("🔒 Audio lock - stay on CABLE (loop OFF)", "Debug", 400)
            }
        }
    } else {
        ; Turn ON - convert current files to loop files
        if (balconRunning && currentNoteTTSFile != "" && FileExist(currentNoteTTSFile)) {
            loopNoteFile := A_Temp . "\xmind_loop_note_" . A_TickCount . ".txt"
            FileCopy, %currentNoteTTSFile%, %loopNoteFile%, 1
            FileDelete, %currentNoteTTSFile%
            currentNoteTTSFile := ""
            
            ; IMMEDIATELY SWITCH TO CABLE FOR LOOPING (only if NOT locked)
            if (!audioLockActive) {
                Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . CABLE_DEVICE . Chr(34), , Hide
                Sleep, 50
            } else {
                if (analyticalMode) {
                    ShowSmartTooltip("🔒 Audio lock - already on CABLE (loop ON)", "Debug", 400)
                }
            }
            
            if (analyticalMode) {
                ShowSmartTooltip("📁 Note → Loop File", "Debug", 800)
            }
        }
        if (headingTTSRunning && currentHeadingTTSFile != "" && FileExist(currentHeadingTTSFile)) {
            loopHeadingFile := A_Temp . "\xmind_loop_heading_" . A_TickCount . ".txt"
            FileCopy, %currentHeadingTTSFile%, %loopHeadingFile%, 1
            FileDelete, %currentHeadingTTSFile%
            currentHeadingTTSFile := ""
            
            ; IMMEDIATELY SWITCH TO CABLE FOR LOOPING (only if NOT locked)
            if (!audioLockActive) {
                Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . CABLE_DEVICE . Chr(34), , Hide
                Sleep, 50
            } else {
                if (analyticalMode) {
                    ShowSmartTooltip("🔒 Audio lock - already on CABLE (loop ON)", "Debug", 400)
                }
            }
            
            if (analyticalMode) {
                ShowSmartTooltip("📁 Heading → Loop File", "Debug", 800)
            }
        }
        loopNoteJustRestarted := false
        loopHeadingJustRestarted := false
        
        ShowSmartTooltip("🔁 " . Message_LoopOn, "LoopOn", 1500)
        if (analyticalMode) {
            ShowSmartTooltip("LOOP ENABLED", "Debug", 1000)
        }
    }
return

; ---------------- F4 & F5 - CORRECTED STAR LOGIC ----------------
; Star rating: 0-4 stars based on speed multiplier level
; 1.0-1.9x: 0 stars (normal speed)
; 2.0-3.9x: ★ (1 star)
; 4.0-5.9x: ★★ (2 stars)
; 6.0-7.9x: ★★★ (3 stars)
; 8.0-9.0x: ★★★★ (4 stars)

stars := ""
starCount := Floor(speedMultiplier / 2)
Loop, %starCount%
    stars .= "★"

; ---------------- F4 - DECREMENT (Active Mode) ----------------
; If SpeedMultiplier mode: Decrease speed
; If mmHeadings level Filter mode: Decrease max levels
; ---------------- F4 - DECREMENT (Active Mode) ----------------
; ---------------- F4 - DECREMENT (Active Mode or Level Override) ----------------
; ---------------- F4 - DECREMENT (Active Mode or Level Override) ----------------
; ---------------- F4 - DECREMENT (Active Mode or Level Override) ----------------
; ---------------- F4 - DECREMENT LEVEL LIMIT ----------------
; ==================== F4: DECREMENT ====================
; - Level mode: Decreases max level OR specific level limit
; - Speed mode: Decreases speed multiplier  
; - Words mode: Decrements noteWordsPerLine toward -10
; - Override mode: When F4/F5 checked + F6=level, controls specific level limit

F4::
    global f6Mode, f4f5OverrideActive, f4f5OverrideLevel, speedMultiplier, noteWordsPerLine
    global headingFilterInputValues, Message_F4F5Tooltip, Message_MaxLevel, Message_WordsPerLine
    
    ; MODE: F4/F5 Override (always takes priority)
    if (f4f5OverrideActive && f6Mode = "level" && f4f5OverrideLevel >= 2) {
        controlLevel := f4f5OverrideLevel
        currentValue := headingFilterInputValues[controlLevel]
        
        if (currentValue = 0) {
            newValue := 0
        } else {
            newValue := currentValue - 1
        }
        
        headingFilterInputValues[controlLevel] := newValue
        
        ; Sync SpinBox + UpDown
        spinControl := "headingFilterSpin" . controlLevel
        upDownControl := "headingFilterSpin" . controlLevel . "UD"
        GuiControl,, %spinControl%, %newValue%
        GuiControl,, %upDownControl%, %newValue%
        
        ; Uncheck radio cascade
        radioVar := "headingFilterRadioBox" . controlLevel
        GuiControl,, %radioVar%, 0
        Loop, % controlLevel - 1 {
            parentRadio := "headingFilterRadioBox" . A_Index
            GuiControl,, %parentRadio%, 0
        }
        
        ShowSmartTooltip(Message_F4F5Tooltip . controlLevel . "/" . newValue, "MaxLevelsOn", 1500)
        return
    }
    
    ; MODE: Level Adjustment (default F6 mode)
    if (f6Mode = "level") {
        if (maxHeadingLevels > 0) {
            maxHeadingLevels -= 1
        }
        levelMsg := (maxHeadingLevels = 0) ? "ALL" : maxHeadingLevels
        ShowSmartTooltip(Message_MaxLevel . levelMsg, "MaxLevelsOn", 1500)
        return
    }
    
    ; MODE: Speed Multiplier Adjustment
    if (f6Mode = "speed") {
        if (speedMultiplier > 1.0) {
            speedMultiplier -= 0.5
        }
        speedMultiplier := Round(speedMultiplier, 1)
        
        stars := ""
        starCount := Floor(speedMultiplier / 2)
        Loop, %starCount%
            stars .= "★"
        
        ShowSmartTooltip("Speed Multiplier: " . Format("{:.1f}", speedMultiplier) . "x " . stars, "F6ModeSpeed", 1500)
        return
    }
    
    ; MODE: Words Per Line Adjustment
    if (f6Mode = "words") {
        if (noteWordsPerLine > -10) {
            noteWordsPerLine -= 1
        }
        ShowSmartTooltip(Message_WordsPerLine . noteWordsPerLine, "WordsPerLine", 1500)
        return
    }
return


; ---------------- F5 - INCREMENT (Active Mode) ----------------
; If SpeedMultiplier mode: Increase speed
; If mmHeadings level Filter mode: Increase max levels
; ---------------- F5 - INCREMENT (Active Mode) ----------------
; ---------------- F5 - INCREMENT (Active Mode or Level Override) ----------------
; ---------------- F5 - INCREMENT (Active Mode or Level Override) ----------------
; ---------------- F5 - INCREMENT (Active Mode or Level Override) ----------------
; ---------------- F5 - INCREMENT LEVEL LIMIT ----------------
; ==================== F5: INCREMENT ====================
; - Level mode: Increases max level OR specific level limit  
; - Speed mode: Increases speed multiplier
; - Words mode: Increments noteWordsPerLine toward 0
; - Override mode: When F4/F5 checked + F6=level, controls specific level limit

; ==================== F5: INCREMENT ====================
; ==================== F5: INCREMENT ====================
F5::
    global f6Mode, f4f5OverrideActive, f4f5OverrideLevel, speedMultiplier, noteWordsPerLine
    global headingFilterInputValues, Message_F4F5Tooltip, Message_MaxLevel, Message_WordsPerLine
    
    ; MODE: F4/F5 Override (always takes priority)
    if (f4f5OverrideActive && f6Mode = "level" && f4f5OverrideLevel >= 2) {
        controlLevel := f4f5OverrideLevel
        currentValue := headingFilterInputValues[controlLevel]
        
        if (currentValue = 999) {
            newValue := 0
        } else if (currentValue = 0) {
            newValue := 1
        } else {
            newValue := currentValue + 1
        }
        
        headingFilterInputValues[controlLevel] := newValue
        
        ; Sync SpinBox + UpDown
        spinControl := "headingFilterSpin" . controlLevel
        upDownControl := "headingFilterSpin" . controlLevel . "UD"
        GuiControl,, %spinControl%, %newValue%
        GuiControl,, %upDownControl%, %newValue%
        
        ; Uncheck radio cascade
        radioVar := "headingFilterRadioBox" . controlLevel
        GuiControl,, %radioVar%, 0
        Loop, % controlLevel - 1 {
            parentRadio := "headingFilterRadioBox" . A_Index
            GuiControl,, %parentRadio%, 0
        }
        
        ShowSmartTooltip(Message_F4F5Tooltip . controlLevel . "/" . newValue, "MaxLevelsOn", 1500)
        return
    }
    
    ; MODE: Level Adjustment (default F6 mode)
    if (f6Mode = "level") {
        maxHeadingLevels += 1
        ShowSmartTooltip(Message_MaxLevel . maxHeadingLevels, "MaxLevelsOn", 1500)
        return
    }
    
    ; MODE: Speed Multiplier Adjustment
    if (f6Mode = "speed") {
        if (speedMultiplier < 9.0) {
            speedMultiplier += 0.5
        }
        speedMultiplier := Round(speedMultiplier, 1)
        
        stars := ""
        starCount := Floor(speedMultiplier / 2)
        Loop, %starCount%
            stars .= "★"
        
        ShowSmartTooltip("Speed Multiplier: " . Format("{:.1f}", speedMultiplier) . "x " . stars, "F6ModeSpeed", 1500)
        return
    }
    
    ; MODE: Words Per Line Adjustment
    if (f6Mode = "words") {
        if (noteWordsPerLine < 0) {
            noteWordsPerLine += 1
        }
        ShowSmartTooltip(Message_WordsPerLine . noteWordsPerLine, "WordsPerLine", 1500)
        return
    }
return

; ---------------- F6 - TOGGLE MODE (SpeedMultiplier ↔ mmHeadings level Filter) ----------------
; ---------------- F6 - TOGGLE MODE (SpeedMultiplier ↔ mmHeadings level Filter ↔ Note words/line) ----------------
; ---------------- F6 - TOGGLE MODE (SpeedMultiplier ↔ mmHeadings level Filter ↔ Note words/line) ----------------
; ---------------- F6 - TOGGLE MODE (SpeedMultiplier ↔ mmHeadings level Filter ↔ Note words/line) ----------------
F6::
    global f6Mode, Message_F6ModeSpeed, Message_F6ModeLevel, Message_F6ModeWords
    global speedMultiplier, maxHeadingLevels, noteWordsPerLine, analyticalMode
    
    ; Cycle through all three modes
    if (f6Mode = "level") {
        f6Mode := "speed"
        stars := ""
        starCount := Floor(speedMultiplier / 2)
        Loop, %starCount%
            stars .= "★"
        ShowSmartTooltip(Message_F6ModeSpeed . ": " . Format("{:.1f}", speedMultiplier) . "x " . stars, "F6ModeSpeed", 1500)
    } else if (f6Mode = "speed") {
        f6Mode := "words"
        ShowSmartTooltip(Message_F6ModeWords . noteWordsPerLine, "F6ModeWords", 1500)
    } else {
        f6Mode := "level"
        levelMsg := (maxHeadingLevels = 0) ? "ALL" : maxHeadingLevels
        ShowSmartTooltip(Message_F6ModeLevel . ": " . levelMsg, "F6ModeLevel", 1500)
    }
    
    if (analyticalMode) {
        ShowSmartTooltip("🎚️ Active Mode: " . f6Mode, "Debug", 800)
    }
return

; ---------------- F7 - SHOW CURRENT MODE VALUE ----------------
; ---------------- F7 - SHOW CURRENT MODE STATUS (Tap) / HEADING FILTER GUI (Hold) ----------------
; ---------------- F7 - SHOW CURRENT MODE VALUE (Tap) / HEADING FILTER GUI (Hold) ----------------
; ---------------- F7 - SHOW CURRENT MODE VALUE (Tap) / HEADING FILTER GUI (Hold) ----------------
; ---------------- F7 - SHOW STATUS (Tap) / HEADING FILTER GUI (Hold) ----------------
; ---------------- F7 - SHOW CURRENT MODE VALUE (Tap) / HEADING FILTER GUI (Hold) ----------------
; ---------------- F7: TAP = SHOW STATUS, HOLD = OPEN GUI ----------------
; TAP behavior:
;   - Level mode: Show current max level status
;   - Speed mode: Show current speed multiplier  
;   - Words mode: Show current words/line
; HOLD behavior (2+ seconds):
;   - Only works in level mode: Opens Heading Filter GUI

F7::
    global f6Mode, f7HoldStart, f7LongPressActive, headingFilterGUIVisible
    global speedMultiplier, maxHeadingLevels, noteWordsPerLine
    
    ; ===== TAP: Show current status for the active F6 mode =====
    if (f6Mode = "level") {
        ; Level mode: Show max levels
        levelMsg := (maxHeadingLevels = 0) ? "ALL" : maxHeadingLevels
        ShowSmartTooltip("mmHeadings level Filter: " . levelMsg, "F6ModeLevel", 1500)
    } else if (f6Mode = "speed") {
        ; Speed mode: Show speed multiplier
        stars := ""
        starCount := Floor(speedMultiplier / 2)
        Loop, %starCount%
            stars .= "★"
        ShowSmartTooltip("Speed Multiplier: " . Format("{:.1f}", speedMultiplier) . "x " . stars, "F6ModeSpeed", 1500)
    } else if (f6Mode = "words") {
        ; Words mode: Show words per line
        ShowSmartTooltip("Note words/line: " . noteWordsPerLine, "F6ModeWords", 1500)
    }
    
    ; ===== HOLD: Only proceed if in level mode =====
    if (f6Mode != "level") {
        return  ; Exit early for non-level modes
    }
    
    ; Hold detection
    f7HoldStart := A_TickCount
    f7LongPressActive := false
    
    while (GetKeyState("F7", "P")) {
        if (A_TickCount - f7HoldStart >= 300 && !f7LongPressActive) {
            f7LongPressActive := true
            f4f5CurrentHeadingNum := 0  ; Reset counter when opening GUI
            CreateHeadingFilterGUI()
            return
        }
        Sleep, 50
    }
return


; ---------------- F9 - AUDIO LOCK TOGGLE ----------------
; PURPOSE: Manually lock audio to CABLE_DEVICE regardless of TTS state
; When ON: Device stays on CABLE_INPUT permanently
; When OFF: Normal automatic device switching resumes

F9::
    global audioLockEnabled, audioLockActive, CABLE_DEVICE, REAL_DEVICE, NIRCMD_PATH
    global Message_AudioLockOn, Message_AudioLockOff, analyticalMode
    
    audioLockEnabled := !audioLockEnabled
    
    if (audioLockEnabled) {
        ; LOCK ON - Switch to CABLE and stay there
        audioLockActive := true
        Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . CABLE_DEVICE . Chr(34), , Hide
        
        ; Show tooltip with custom styling (add to SECTION 2/5)
        ShowSmartTooltip("🔒 Audio Lock: ON (CABLE)", "AudioLockOn", 1500)
        
        if (analyticalMode) {
            ShowSmartTooltip("🔊 Device locked to CABLE_INPUT", "Debug", 800)
        }
    } else {
        ; LOCK OFF - Restore normal behavior
        audioLockActive := false
        
        ; Check if we should switch back to REAL device
        ; (Only if no TTS currently running - otherwise let normal logic handle it)
        global balconRunning, headingTTSRunning
        if (!balconRunning && !headingTTSRunning) {
            Run, % NIRCMD_PATH . " setdefaultsounddevice " . Chr(34) . REAL_DEVICE . Chr(34), , Hide
        }
        
        ShowSmartTooltip("🔓 Audio Lock: OFF (Auto)", "AudioLockOff", 1500)
        
        if (analyticalMode) {
            ShowSmartTooltip("🔊 Automatic device switching restored", "Debug", 800)
        }
    }
return


; ---------------- F10 - DUAL DETECTION TOGGLE ----------------
; PURPOSE: Enable/disable smart heading detection during TTS

F10::
    global dualDetectionEnabled, Message_DualDetectionOn, Message_DualDetectionOff
    global balconRunning, headingDetectionActive, backgroundDetectionEnabled
    
    dualDetectionEnabled := !dualDetectionEnabled
    
    if (dualDetectionEnabled) {
        ShowSmartTooltip("🔍 " . Message_DualDetectionOn, "DualDetectionOn", 1500)
        ; If TTS is running, start dual detection
        if (balconRunning && (!headingDetectionActive || !backgroundDetectionActive)) {
            StartHeadingDetection()
        }
    } else {
        ShowSmartTooltip("🚫 " . Message_DualDetectionOff, "DualDetectionOff", 1500)
        ; Stop dual detection if it's running
        if (headingDetectionActive || backgroundDetectionActive) {
            StopHeadingDetection()
        }
    }
return

; ---------------- F11 - AI NOTE ASSISTANT SETTINGS GUI ----------------
; PURPOSE: Launch (first press) or show/hide (later presses) the Python
; "XMind AI Note Assistant" floating toolbar, where you pick Node vs Note
; mode and the node size tier. Closing that window (its own X button) just
; hides it -- it keeps running in the background so its browser session and
; your Node/Note tab selection are preserved for RButton & XButton2 search.
; NOTE: F11 used to toggle Analytical Mode. That toggle has been removed
; from F11, but analyticalMode itself and every "if (analyticalMode)" debug
; check elsewhere in this script are left completely untouched.

F11::
    global XMindAI_PythonPath, XMindAI_ScriptPath, XMindAI_WinTitle, XMindAI_PID

    DetectHiddenWindows, On
    if (!WinExist(XMindAI_WinTitle)) {
        Run, %XMindAI_PythonPath% "%XMindAI_ScriptPath%",, UseErrorLevel, XMindAI_PID
        if (ErrorLevel = "ERROR") {
            ShowSmartTooltip("❌ Couldn't launch " . XMindAI_PythonPath . " — check XMindAI_PythonPath/XMindAI_ScriptPath", "AINotRunning", 3000)
            DetectHiddenWindows, Off
            return
        }
        ShowSmartTooltip("🤖 Launching AI Note Assistant...", "AILaunch", 1200)
        WinWait, %XMindAI_WinTitle%,, 8
        if (ErrorLevel) {
            ; Run succeeded (a process started) but no window ever appeared --
            ; pythonw.exe has no console, so a crash on launch (missing
            ; tkinter, a typo'd path, etc.) is otherwise completely silent.
            ShowSmartTooltip("❌ AI Assistant window never appeared — script likely crashed on launch. Try running it with python.exe (not pythonw.exe) to see the error.", "AINotRunning", 4000)
        } else {
            WinActivate, %XMindAI_WinTitle%
        }
        DetectHiddenWindows, Off
        return
    }

    if (WinActive(XMindAI_WinTitle)) {
        WinHide, %XMindAI_WinTitle%
        ShowSmartTooltip("🤖 AI Assistant hidden — F11 to reopen", "AIHide", 900)
    } else {
        WinShow, %XMindAI_WinTitle%
        WinActivate, %XMindAI_WinTitle%
        ShowSmartTooltip("🤖 AI Assistant settings", "AIShow", 800)
    }
    DetectHiddenWindows, Off
return

; ---------------- F12 - TTS LOCK TOGGLE (BOTH SYSTEMS) ----------------
; PURPOSE: Prevent automatic TTS stopping for both note and heading TTS

F12::
    global ttsLocked, Message_TTSLockOn, Message_TTSLockOff, balconRunning, noteToggleEnabled, headingTTSRunning
    
    ; If turning F12 OFF and features are disabled AND TTS is running, stop both TTS systems
    if (ttsLocked && !noteToggleEnabled) {
        if (balconRunning) {
            StopBalcon()
        }
        if (headingTTSRunning) {
            StopHeadingTTS()
        }
    }
    
    ttsLocked := !ttsLocked
    if (ttsLocked) {
        ShowSmartTooltip("🔒 " . Message_TTSLockOn, "TTSLockOn", 1500)
    } else {
        ShowSmartTooltip("🔓 " . Message_TTSLockOff, "TTSLockOff", 1500)
        
        ; When turning F12 OFF and features are disabled, cleanup clipboard
        if (!noteToggleEnabled) {
            CleanupClipboard()
        }
        
        ; When turning F12 OFF and TTS is running but features are enabled, cleanup clipboard
        ; This handles the case where F12 was ON, TTS is running, and we turn F12 OFF
        if ((balconRunning || headingTTSRunning) && noteToggleEnabled) {
            CleanupClipboard()
        }
    }
return

; ---------------- PGUP/PGDN - BALCON SPEED CONTROL ----------------
; Page Up: Increase speed (max 10, shows Max)
; Page Down: Decrease speed (min 1, shows Min)

PgUp::
    if (!IsValidXMindWindow())
        return
    global balconSpeed, Message_Speed, VoiceSpeed_WIDTH
    
    if (balconSpeed < 10) {
        balconSpeed += 1
    }
    
    ; Dynamic width: Expand to 178 for Max/Min text
    if (balconSpeed = 10) {
        oldWidth := VoiceSpeed_WIDTH
        VoiceSpeed_WIDTH := 178
        ShowSmartTooltip(Message_Speed . balconSpeed . " (Max)", "VoiceSpeed", 1200)
        VoiceSpeed_WIDTH := oldWidth
    } else {
        ShowSmartTooltip(Message_Speed . balconSpeed, "VoiceSpeed", 1200)
    }
return

PgDn::
    if (!IsValidXMindWindow())
        return
    global balconSpeed, Message_Speed, VoiceSpeed_WIDTH
    
    if (balconSpeed > -10) {
        balconSpeed -= 1
    }
    
    ; Dynamic width: Expand to 178 for Max/Min text
    if (balconSpeed = -10) {
        oldWidth := VoiceSpeed_WIDTH
        VoiceSpeed_WIDTH := 178
        ShowSmartTooltip(Message_Speed . balconSpeed . " (Min)", "VoiceSpeed", 1200)
        VoiceSpeed_WIDTH := oldWidth
    } else {
        ShowSmartTooltip(Message_Speed . balconSpeed, "VoiceSpeed", 1200)
    }
return


; ---------------- F8 - MANUAL NOTE SYNC ----------------
; PURPOSE: Force detection of note opening for edge cases

~F8::
    if (!IsValidXMindWindow()) {
        Send, {F8}
        return
    }
    Sleep, 40
    ControlGetFocus, noteControl, A
    WinGet, noteWindowID, ID, A
    noteOpen := true
    Sleep, 40
    Send, ^{Home}
return

; ---------------- ESC - NOTE CLOSURE AND CLEANUP ----------------
; PURPOSE: Handle escape key for note closing and state cleanup

~Esc::
    if (IsValidXMindWindow()) {
        noteOpen := false
        noteControl := ""
        noteWindowID := ""
        middleZoomActive := false
    }
    Send, {Esc}
return

; ---------------- RIGHT-CLICK GESTURES - TOPIC NAVIGATION ----------------
; PURPOSE: Navigate between topics using mouse gestures

$RButton::
    if (!IsValidXMindWindow()) {
        Send, {RButton down}
        KeyWait, RButton
        Send, {RButton up}
        return
    }
    global gestureToggleEnabled, balconRunning, originalHeading, differentHeadingDetected, gestureThreshold, gesturePollMs
    global headingDetectionActive, analyticalMode, dualDetectionEnabled
    
    if (!gestureToggleEnabled) {
        Send, {RButton down}
        KeyWait, RButton
        Send, {RButton up}
        return
    }
    
    UpdateNoteFocusCheck()
    MouseGetPos, lastX, lastY
    
    ; Show detection status when starting gesture (only if dual detection is enabled)
    if (headingDetectionActive && analyticalMode && dualDetectionEnabled) {
        ShowSmartTooltip("🔍 GESTURE ACTIVE - Real-time detection running", "Debug", 800)
    }
    
    ; Store current heading at gesture start for comparison (only if dual detection is enabled)
    if (headingDetectionActive && originalHeading = "" && dualDetectionEnabled) {
        originalHeading := GetCurrentHeading()
        if (analyticalMode && originalHeading != "") {
            truncatedHeading := TruncateString(originalHeading, 50)
            ShowSmartTooltip("📝 ORIGINAL: " . truncatedHeading, "Debug", 800)
        }
    }
    
    Loop {
        Sleep, %gesturePollMs%
        GetKeyState, rnow, RButton, P
        if (rnow != "D")
            break

        ; RButton held + XButton2 pressed -> AI Node/Note search (NOT a gesture).
        ; Checked here, inside the same held-RButton loop, rather than as a
        ; separate "RButton & XButton2::" hotkey, so it can't conflict with the
        ; plain-RButton gesture logic below or with XButton2's own hotkey.
        GetKeyState, xb2now, XButton2, P
        if (xb2now = "D") {
            PerformAISearch()
            KeyWait, XButton2
            KeyWait, RButton
            return
        }

        MouseGetPos, curX, curY
        dx := curX - lastX
        dy := curY - lastY
        
        ; REAL-TIME DETECTION: Check heading during gesture (only if dual detection is enabled)
        if (headingDetectionActive && (dx != 0 || dy != 0) && dualDetectionEnabled) {
            currentHeading := GetCurrentHeading()
            
            if (currentHeading != "" && currentHeading != originalHeading) {
                differentHeadingDetected := true
                if (analyticalMode) {
                    truncatedHeading := TruncateString(currentHeading, 50)
                    ShowSmartTooltip("🎯 DIFFERENT: " . truncatedHeading, "Debug", 800)
                }
            } else if (currentHeading = originalHeading) {
                differentHeadingDetected := false
                if (analyticalMode) {
                    ShowSmartTooltip("✅ SAME HEADING", "Debug", 800)
                }
            }
        }
        
        if (Abs(dx) >= gestureThreshold or Abs(dy) >= gestureThreshold) {
            if (Abs(dx) >= Abs(dy))
                Send, % (dx > 0 ? "{Right}" : "{Left}")
            else
                Send, % (dy > 0 ? "{Down}" : "{Up}")
            lastX := curX
            lastY := curY
        }
    }
return

; ===========================================================
; AI NODE/NOTE SEARCH - RButton (held) + XButton2
; ===========================================================
; PURPOSE: Capture the selected node's own name, or the open note's
; content, and hand it to the Python "XMind AI Note Assistant" (F11 GUI).
; Which action happens depends on noteOpen -- the SAME state flag the
; Note/Heading TTS system already tracks:
;   - No note open, a node/heading is selected  -> NODE search
;   - A note IS open                            -> NOTE search
; Node vs Note MODE on the assistant's side (i.e. what it does with the
; text, and where the AI's reply goes) is controlled purely by whichever
; tab is selected in the F11 GUI -- this function only ever hands over
; the captured text, it never decides that for the assistant.
PerformAISearch() {
    global noteOpen, analyticalMode, XMindAI_WinTitle, XMindAI_BridgeKeepChildren

    ; If the assistant isn't actually running, writing the bridge file
    ; would just vanish into nothing -- nobody would ever read it, and
    ; there'd be no paste, no error, no clue why. Fail loudly instead.
    DetectHiddenWindows, On
    assistantRunning := WinExist(XMindAI_WinTitle)
    DetectHiddenWindows, Off
    if (!assistantRunning) {
        ShowSmartTooltip("❌ AI Assistant isn't running — press F11 first", "AINotRunning", 2000)
        return
    }

    if (!noteOpen) {
        ; ---- NODE SEARCH ----
        ; GetHeadingBranchStructureAdaptive() copies the selected node via
        ; Ctrl+C, which (when the node has subnodes) returns the WHOLE
        ; branch as tab-indented lines: the node itself on line 1, every
        ; subnode below it. Normally node search wants ONLY the selected
        ; node's own name, so subnodes get filtered out by keeping just
        ; the first line -- UNLESS XMindAI_BridgeKeepChildren exists, which
        ; means the MCQ's tab's "Keep children nodes" checkbox is checked
        ; (and that tab is the active one) on the Python side. In that
        ; case the whole tab-indented branch is kept and sent as-is, so
        ; the AI gets the full subtree instead of just the bare node name.
        clipBackup := ClipboardAll
        Clipboard := ""
        headingText := GetHeadingBranchStructureAdaptive()
        Clipboard := clipBackup
        clipBackup := ""

        if (Trim(headingText) = "") {
            ShowSmartTooltip("❌ No node selected for search", "NoNodeSearch", 1500)
            return
        }

        keepChildren := FileExist(XMindAI_BridgeKeepChildren)
        if (keepChildren) {
            nodeOnly := Trim(headingText, "`r`n")
        } else {
            StringSplit, headingLines, headingText, `n, `r
            nodeOnly := Trim(headingLines1)
        }

        if (Trim(nodeOnly) = "") {
            ShowSmartTooltip("❌ No node selected for search", "NoNodeSearch", 1500)
            return
        }

        if (analyticalMode) {
            ShowSmartTooltip("🔎 Node search: " . TruncateString(nodeOnly, 50), "Debug", 900)
        }
        SendAISearchRequest("NODE", nodeOnly)
        ShowSmartTooltip("🤖🔎 Node sent to AI Assistant", "NodeSearchSent", 1000)
        return
    }

    ; ---- NOTE SEARCH ----
    ; The note must ALREADY be open (that's the noteOpen check above) so
    ; that after the AI replies, XMind still has the note field focused --
    ; that's what keeps the pasted reply landing back in the note instead
    ; of on the canvas.
    clipBackup := ClipboardAll
    Clipboard := ""
    Send, ^a
    Sleep, 40
    Send, ^c
    Sleep, 2
    noteContent := ""
    attempts := 0
    Loop {
        noteContent := Clipboard
        if (noteContent != "")
            break
        attempts++
        if (attempts >= 10)
            break
        Sleep, 100
    }
    Send, ^{Home}
    Clipboard := clipBackup
    clipBackup := ""

    if (Trim(noteContent) = "") {
        ShowSmartTooltip("❌ Note is empty, nothing to search", "NoNoteSearch", 1500)
        return
    }

    if (analyticalMode) {
        ShowSmartTooltip("🔎 Note search: " . StrLen(noteContent) . " chars", "Debug", 900)
    }
    SendAISearchRequest("NOTE", noteContent)
    ShowSmartTooltip("🤖🔎 Note sent to AI Assistant", "NoteSearchSent", 1000)
    return
}

; Writes the captured node/note text to the bridge file the Python
; assistant polls for. Two files so the assistant never reads a
; half-written request: the text file is written FIRST, the tiny flag
; file LAST, and the assistant only reacts once the flag file exists.
;
; capturedKind is "NODE" or "NOTE" -- which of the two branches in
; PerformAISearch() actually did the capturing (i.e. whether a note was
; open or not), NOT which tab happens to be selected in the Python GUI.
; It's written as a header line so Python knows for certain what kind of
; text this is instead of having to guess from its own tab state, which
; can easily disagree with what AHK actually captured (e.g. the Note tab
; is selected in the toolbar, but you RM+XButton2'd a plain node with no
; note open -- that's still a NODE capture, not a NOTE capture).
SendAISearchRequest(capturedKind, capturedText) {
    global XMindAI_BridgeDir, XMindAI_BridgeRequest, XMindAI_BridgeFlag
    FileCreateDir, %XMindAI_BridgeDir%
    FileDelete, %XMindAI_BridgeFlag%
    FileDelete, %XMindAI_BridgeRequest%
    ; "UTF-8-RAW" (not "UTF-8"): plain "UTF-8" makes AHK write a
    ; byte-order-mark at the start of the file every time it's (re)created,
    ; which was leaking an invisible BOM character onto the front of every
    ; captured node/note text the Python side read back.
    FileAppend, %capturedKind%`n%capturedText%, %XMindAI_BridgeRequest%, UTF-8-RAW
    FileAppend, ready, %XMindAI_BridgeFlag%
}

; ---------------- AI REPLY -> PASTE (Python signals, AHK executes) ----------
; PURPOSE: Python puts the AI's reply on the clipboard (as plain text for
; Node search, or as a CF_HTML/plain fallback pair for Note search) and then
; just drops this flag file -- it deliberately does NOT try to bring XMind
; to the foreground or send Ctrl+V itself anymore, since that consistently
; copied the text but never actually pasted it. AHK does that part instead,
; the same way it already reliably talks to this exact XMind window
; everywhere else in this script.
;
; PASTE ONLY IF XMIND IS ALREADY THE ACTIVE WINDOW: the reply can take a
; while to come back (see the AI wait limit spinbox on the Python side), and
; the person may well have switched to something else -- a browser, another
; app -- while it was thinking. Force-activating XMind and pasting into it
; at that point would yank focus away from whatever they're actually doing.
; So: if XMind isn't the window currently in focus when the reply lands,
; leave it on the clipboard only (already done, above this label) and stop
; here -- no WinActivate, no Send. If XMind IS already active, paste as
; before.
_PollAIPasteReady:
    global XMindAI_BridgePasteReady, noteToggleEnabled
    if (!FileExist(XMindAI_BridgePasteReady))
        return
    FileDelete, %XMindAI_BridgePasteReady%

    ; (Turning features OFF used to cancel a queued paste right here. It no
    ; longer does -- an F11 session now only ends when XButton2 is pressed
    ; while features are OFF, and TerminateF11Session() deletes paste.ready
    ; itself, so anything that reaches this point is a live session.)

    if (!WinExist("ahk_exe XMind.exe")) {
        ShowSmartTooltip("❌ XMind window not found -- can't paste AI reply", "AIPasteFail", 1500)
        return
    }

    if (!WinActive("ahk_exe XMind.exe")) {
        ShowSmartTooltip("📋 AI reply copied to clipboard -- XMind isn't focused, paste manually (Ctrl+V)", "AICopiedNotPasted", 2000)
        return
    }

    ; Already the active window -- no need to WinActivate/WinWaitActive,
    ; just give XMind's own UI a beat to make sure the right control (canvas
    ; or note field) has keyboard focus before the keystroke fires.
    Sleep, 150
    Send, ^v
return

; One-shot timer target: the second tooltip shown after the Shift Scroll one.
_ShowF11TerminatedTooltip:
    global Message_F11SessionTerminated
    ShowSmartTooltip(Message_F11SessionTerminated, "F11Terminated")
return

; ---------------- LEFT-CLICK - NOTE MANAGEMENT ----------------
; PURPOSE: Handle note opening/closing with smart TTS management

$LButton::
    global noteToggleEnabled
    if (!IsValidXMindWindow() || !noteToggleEnabled) {
        Send, {LButton down}
        KeyWait, LButton
        Send, {LButton up}
        return
    }
    MouseGetPos, _lbtn_down_x, _lbtn_down_y
    _lbtn_was_down := true
return

$LButton Up::
    global noteToggleEnabled
    if (!IsValidXMindWindow() || !noteToggleEnabled) {
        Send, {LButton up}
        return
    }
    if (!_lbtn_was_down) {
        Send, {LButton}
        return
    }
    _lbtn_was_down := false
    UpdateNoteFocusCheck()
    global noteOpen, clickMoveThreshold, balconRunning, originalHeading, differentHeadingDetected
    global headingDetectionActive, analyticalMode, dualDetectionEnabled
    global headingTTSRunning, pendingNoteTTSAfterHeadingStop
    
    MouseGetPos, ux, uy
    dx := Abs(ux - _lbtn_down_x)
    dy := Abs(uy - _lbtn_down_y)
    if (dx > clickMoveThreshold or dy > clickMoveThreshold) {
        UpdateNoteFocusCheck()
        return
    }
    if (noteOpen) {
        ; Closing note
        Send, {Esc}
        Sleep, 0  ; Very fast response
        noteOpen := false
        noteControl := ""
        noteWindowID := ""
        
        ; Clear pending note TTS flag when closing note
        if (pendingNoteTTSAfterHeadingStop) {
            pendingNoteTTSAfterHeadingStop := false
            if (analyticalMode) {
                ShowSmartTooltip("❌ PENDING NOTE TTS CANCELLED - NOTE CLOSED", "Debug", 800)
            }
        }
        
        ; If detection is active but we don't have originalHeading yet, get it now (only if dual detection is enabled)
        if (headingDetectionActive && originalHeading = "" && dualDetectionEnabled) {
            originalHeading := GetCurrentHeading()
            if (analyticalMode) {
                ShowSmartTooltip("📝 FALLBACK ORIGINAL: " . originalHeading, "Debug", 800)
            }
        }
        return
    }
    ; Opening a note - only stop TTS if dual detection is enabled AND different heading detected
    if (balconRunning && differentHeadingDetected && dualDetectionEnabled) {
        ; Opening different heading note - stop TTS
        if (analyticalMode) {
            ShowSmartTooltip("🛑 STOPPING TTS - Different heading detected via dual system!", "Debug", 1200)
        }
        StopBalcon()
    }
    ; Open note
    Send, {F8}
    noteControl := ""
    noteWindowID := ""
    noteOpen := false
    Loop, %noteOpenRetryAttempts% {
        Sleep, %noteOpenRetryDelay%
        ControlGetFocus, tmpControl, A
        WinGet, tmpWinID, ID, A
        if (tmpWinID && tmpControl) {
            noteControl := tmpControl
            noteWindowID := tmpWinID
            noteOpen := true
            break
        }
    }
    if (!noteOpen) {
        WinGet, curWinID, ID, A
        if (curWinID) {
            noteWindowID := curWinID
            noteControl := ""
            noteOpen := true
        }
    }
    if (noteOpen) {
        Sleep, 80  ; Very fast
        Send, ^{Home}
        Sleep, 50  ; Very fast
        Send, ^{Home}
    }
return

; ---------------- MIDDLE MOUSE BUTTON - TRANSITIONING TOGGLE ----------------
; PURPOSE: Toggle transitioning ON/OFF when XButton1 (features) is ON
; When features OFF: Pass through to XMind for native free scroll/panning

MButton::
    if (!IsValidXMindWindow()) {
        Send, {MButton}
        return
    }
    global noteToggleEnabled, transitioningEnabled
    global Message_TransitioningOn, Message_TransitioningOff

    ; MODE: Features OFF - Free Panning (native XMind canvas panning)
    if (!noteToggleEnabled) {
        Send, {MButton Down}
        KeyWait, MButton
        Send, {MButton Up}
        return
    }

    ; MODE: Features ON - Toggle transitioning
    transitioningEnabled := !transitioningEnabled
    if (transitioningEnabled) {
        ShowSmartTooltip(Message_TransitioningOn, "TransitioningOn", 1500)
    } else {
        ShowSmartTooltip(Message_TransitioningOff, "TransitioningOff", 1500)
    }
return

; ---------------- XButton2 (Mouse5) - NOTE TTS / HEADING TTS / SHIFT SCROLL ----------------
; PURPOSE:
; - When features OFF: Shift Scroll toggle
; - When features ON + transitioning OFF: Stop any running TTS, no auto-switch
; - When features ON + transitioning ON: Seamless transition between Note/Heading TTS
; - Transition occurs when conditions are met (note open for NoteTTS, node selected for HeadingTTS)

XButton2::
    if (!IsValidXMindWindow()) {
        Send, {XButton2}
        return
    }
    ; RButton held -> that combo is an AI Node/Note search (handled inside
    ; the $RButton:: gesture loop), not the normal Note/Heading TTS toggle.
    GetKeyState, rBtnHeldNow, RButton, P
    if (rBtnHeldNow = "D") {
        return
    }
    global noteToggleEnabled, shiftZoomActive, ttsLocked, noteOpen, balconRunning, headingTTSRunning
    global transitioningEnabled, loopMode, manualLoopKill, activeTTSType, isTransition, isInGapPhase
    global analyticalMode, Message_TTSStart, Message_NoNoteOpen, Message_NoteEmpty
    global Message_ShiftScrollOn, Message_ShiftScrollOff, Message_NoHeadingSelected, Message_HeadingTTSStart
    global CABLE_DEVICE, NIRCMD_PATH, currentNoteContent, currentNoteOriginalContent, loopNoteFile
    global currentHeadingContent, currentHeadingRawStructure, currentHeadingOriginalStructure, loopHeadingFile
    global speedMultiplier, suppressNumbersEnabled, noteWordsPerLine, cachedMode4Content
    global pendingNoteTTSAfterHeadingStop, levelSelectionActive

    ; Clear flags
    pendingNoteTTSAfterHeadingStop := false
    levelSelectionActive := false
    SetTimer, _LevelSelectionCountdown, Off

    ; MODE: Features OFF - Shift scroll control only
    if (!noteToggleEnabled) {
        ; A pending "session terminated" tooltip from a previous press must
        ; not fire in the middle of this press's own tooltips.
        SetTimer, _ShowF11TerminatedTooltip, Off
        shiftZoomActive := !shiftZoomActive
        if (shiftZoomActive) {
            shiftTipMs := 1000
            ShowSmartTooltip(Message_ShiftScrollOn, "ShiftScrollOn", shiftTipMs)
        } else {
            shiftTipMs := 800
            ShowSmartTooltip(Message_ShiftScrollOff, "ShiftScrollOff", shiftTipMs)
        }
        ; XButton2 while features are OFF is now ALSO the F11 session
        ; terminator. If an F11 AI session was actually ongoing, kill it and
        ; queue a second tooltip to appear once the Shift Scroll one is done
        ; (ShowSmartTooltip replaces whatever is showing, so it can't be
        ; shown at the same time -- it has to wait its turn).
        if (TerminateF11Session()) {
            SetTimer, _ShowF11TerminatedTooltip, % -(shiftTipMs + 50)
        }
        return
    }

    ; MODE: Features ON

    ; === TRANSITIONING OFF: Simple stop-only behavior ===
    if (!transitioningEnabled) {
        ; If any TTS is running, just stop it and return
        if (balconRunning) {
            manualLoopKill := true
            StopBalcon()
            return
        }
        if (headingTTSRunning) {
            manualLoopKill := true
            StopHeadingTTS()
            return
        }
        ; BLOCK if in gap phase
        if (isInGapPhase) {
            if (analyticalMode) {
                ShowSmartTooltip("⏳ Gap...", "Debug", 800)
            }
            return
        }
        ; Nothing running - start TTS based on note state
        if (noteOpen) {
            ; === NOTE IS OPEN → NOTE TTS ===
            HideSmartTooltip()
            isInGapPhase := false
            manualLoopKill := false
            activeTTSType := "note"
            isTransition := false
            CleanupLoopFiles("heading")
            CleanupLoopFiles("note")
            if (loopMode) {
                loopNoteFile := A_Temp . "\xmind_loop_note_tts_" . A_TickCount . ".txt"
                FileDelete, %loopNoteFile%
            }
            ; Capture RAW content
            currentNoteContent := ""
            currentNoteOriginalContent := ""
            CleanupClipboard()
            Clipboard := ""
            Send, ^{Home}
            Sleep, 0
            Send, ^a
            Sleep, 40
            Send, ^c
            Sleep, 2
            noteContent := ""
            attempts := 0
            maxAttempts := 10
            Loop {
                noteContent := Clipboard
                if (noteContent != "") {
                    break
                }
                attempts++
                if (attempts >= maxAttempts) {
                    break
                }
                Sleep, 200
            }
            Send, ^{Home}
            Send, {Home}
            if (Trim(noteContent) = "" || StrLen(noteContent) < 1) {
                HideSmartTooltip()
                ShowSmartTooltip("❌ " . Message_NoteEmpty, "NoteEmpty", 1200)
                return
            }
            currentNoteOriginalContent := noteContent
            processedNoteContent := noteContent
            if (speedMultiplier > 1.0) {
                processedNoteContent := PreprocessTextForSpeed(processedNoteContent, speedMultiplier)
            }
            if (suppressNumbersEnabled) {
                processedNoteContent := StripNumbersFromText(processedNoteContent)
            }
            if (noteWordsPerLine < 0) {
                processedNoteContent := FormatWordsPerLine(processedNoteContent, noteWordsPerLine)
            }
            currentNoteContent := processedNoteContent
            if (loopMode && loopNoteFile != "") {
                FileDelete, %loopNoteFile%
                FileAppend, %processedNoteContent%, %loopNoteFile%
            }
            if (SpeakWithBalconSmart(processedNoteContent, "note")) {
                balconRunning := true
                ShowSmartTooltip("▶ Reading Note TTS", "TTSStart", 800)
            }
            return
        } else {
            ; === NOTE IS CLOSED → HEADING TTS ===
            isInGapPhase := false
            manualLoopKill := false
            activeTTSType := "heading"
            isTransition := false
            CleanupLoopFiles("note")
            CleanupLoopFiles("heading")
            if (loopMode) {
                loopHeadingFile := A_Temp . "\xmind_loop_heading_" . A_TickCount . ".txt"
                FileDelete, %loopHeadingFile%
                cachedMode4Content := ""
            }
            if (Trim(GetHeadingBranchStructureAdaptive()) = "") {
                ShowSmartTooltip("❌ " . Message_NoHeadingSelected, "NoHeadingSelected", 2000)
                return
            }
            if (SpeakHeadingStructure()) {
                headingTTSRunning := true
                ShowSmartTooltip("🌳 Reading heading structure", "HeadingTTSStart", 800)
            }
            return
        }
    }

    ; === TRANSITIONING ON: Domain-Based Toggle Behavior ===
    ; Domain determines which TTS to toggle:
    ;   Note TTS domain: note is open
    ;   Heading TTS domain: note is closed
    ;
    ; Transition logic:
    ;   1. Check if target TTS can start BEFORE stopping old TTS
    ;   2. If target can't start → stop old TTS normally (show stop msg, switch device)
    ;   3. If target can start → stop old TTS silently (no device switch), start target

    ; BLOCK if in gap phase
    if (isInGapPhase) {
        if (analyticalMode) {
            ShowSmartTooltip("⏳ Gap...", "Debug", 800)
        }
        return
    }

    ; === NOTE TTS DOMAIN (note is open) ===
    if (noteOpen) {
        ; If Note TTS already running → just stop it
        if (balconRunning) {
            manualLoopKill := true
            activeTTSType := ""
            StopBalcon()
            Sleep, 50
            return
        }

        ; Note TTS not running — try to read content FIRST (before stopping heading TTS)
        HideSmartTooltip()
        CleanupClipboard()
        Clipboard := ""
        Send, ^{Home}
        Sleep, 0
        Send, ^a
        Sleep, 40
        Send, ^c
        Sleep, 2
        noteContent := ""
        attempts := 0
        maxAttempts := 10
        Loop {
            noteContent := Clipboard
            if (noteContent != "") {
                break
            }
            attempts++
            if (attempts >= maxAttempts) {
                break
            }
            Sleep, 200
        }
        Send, ^{Home}
        Send, {Home}

        ; If note is empty → can't start Note TTS
        if (Trim(noteContent) = "" || StrLen(noteContent) < 1) {
            ; Stop heading TTS normally if running (transition failed)
            if (headingTTSRunning) {
                StopHeadingTTS()
                Sleep, 50
            }
            HideSmartTooltip()
            ShowSmartTooltip("❌ " . Message_NoteEmpty, "NoteEmpty", 1200)
            return
        }

        ; Note has content — transition from heading TTS if running
        ; NOTE: isTransition stays true until AFTER the new TTS actually starts below —
        ; SpeakWithBalconSmart/SpeakHeadingStructure can internally call StopBalcon/StopHeadingTTS
        ; again if the cleanup timer hasn't caught up yet, and that call must also see isTransition=true
        ; or it will restore the real device and cause an audible switch mid-transition.
        wasHeadingRunning := headingTTSRunning
        if (headingTTSRunning) {
            isTransition := true
            manualLoopKill := true
            StopHeadingTTS(true)
            Sleep, 50
        }

        ; Start Note TTS
        isInGapPhase := false
        manualLoopKill := false
        activeTTSType := "note"
        CleanupLoopFiles("heading")
        CleanupLoopFiles("note")
        if (loopMode) {
            loopNoteFile := A_Temp . "\xmind_loop_note_tts_" . A_TickCount . ".txt"
            FileDelete, %loopNoteFile%
        }
        currentNoteContent := ""
        currentNoteOriginalContent := ""
        currentNoteOriginalContent := noteContent
        processedNoteContent := noteContent
        if (speedMultiplier > 1.0) {
            processedNoteContent := PreprocessTextForSpeed(processedNoteContent, speedMultiplier)
        }
        if (suppressNumbersEnabled) {
            processedNoteContent := StripNumbersFromText(processedNoteContent)
        }
        if (noteWordsPerLine < 0) {
            processedNoteContent := FormatWordsPerLine(processedNoteContent, noteWordsPerLine)
        }
        currentNoteContent := processedNoteContent
        if (loopMode && loopNoteFile != "") {
            FileDelete, %loopNoteFile%
            FileAppend, %processedNoteContent%, %loopNoteFile%
        }
        if (SpeakWithBalconSmart(processedNoteContent, "note")) {
            balconRunning := true
            if (wasHeadingRunning) {
                ShowSmartTooltip("▶▶ Reading Note TTS", "TTSStart", 800)
            } else {
                ShowSmartTooltip("▶ Reading Note TTS", "TTSStart", 800)
            }
        }
        isTransition := false
        return
    }

    ; === HEADING TTS DOMAIN (note is closed) ===
    ; Check if heading TTS can start BEFORE stopping Note TTS
    clipBackup := ClipboardAll
    Clipboard := ""
    headingCheck := GetHeadingBranchStructureAdaptive()
    isNodeSelected := (headingCheck != "")
    Clipboard := clipBackup
    clipBackup := ""

    if (analyticalMode) {
        domainMsg := isNodeSelected ? "Heading TTS domain (node selected)" : "Heading TTS domain (no node)"
        ShowSmartTooltip("🌐 " . domainMsg, "Debug", 800)
    }

    ; If heading TTS already running → just stop it
    if (headingTTSRunning) {
        manualLoopKill := true
        activeTTSType := ""
        StopHeadingTTS()
        Sleep, 50
        return
    }

    ; If no node selected → can't start heading TTS
    if (Trim(headingCheck) = "") {
        ; Stop Note TTS normally if running (transition failed — show stop msg)
        if (balconRunning) {
            manualLoopKill := true
            StopBalcon()
            Sleep, 50
        }
        ShowSmartTooltip("❌ " . Message_NoHeadingSelected, "NoHeadingSelected", 2000)
        return
    }

    ; Node is selected — transition from Note TTS if running
    ; NOTE: isTransition stays true until AFTER SpeakHeadingStructure() actually starts —
    ; it can internally call StopBalcon() again if the cleanup timer hasn't caught up yet,
    ; and that call must also see isTransition=true or it will restore the real device
    ; and cause an audible switch mid-transition.
    wasNoteRunning := balconRunning
    if (balconRunning) {
        isTransition := true
        manualLoopKill := true
        StopBalcon(true)
        Sleep, 50
    }

    ; Start Heading TTS
    isInGapPhase := false
    manualLoopKill := false
    activeTTSType := "heading"
    CleanupLoopFiles("note")
    CleanupLoopFiles("heading")
    if (loopMode) {
        loopHeadingFile := A_Temp . "\xmind_loop_heading_" . A_TickCount . ".txt"
        FileDelete, %loopHeadingFile%
        cachedMode4Content := ""
    }

    if (SpeakHeadingStructure()) {
        headingTTSRunning := true
        if (wasNoteRunning) {
            ShowSmartTooltip("🌳🌳 Reading heading structure", "HeadingTTSStart", 800)
        } else {
            ShowSmartTooltip("🌳 Reading heading structure", "HeadingTTSStart", 800)
        }
    }
    isTransition := false
    return

; ---------------- SCROLL LOCK - SCRIPT PAUSE/RESUME ----------------
; PURPOSE: Temporarily disable all script functionality

ScrollLock::
    Suspend, Toggle
    global Message_ScriptPaused, Message_ScriptResumed
    global middleZoomActive  ; ALSO turn off zoom mode when pausing
    
    if (A_IsSuspended) {
        ShowSmartTooltip(Message_ScriptPaused, "ScriptPaused", 800)
        StopBalcon()
        StopHeadingTTS()
        middleZoomActive := false  ; Turn off zoom mode when script is paused
    } else {
        ShowSmartTooltip(Message_ScriptResumed, "ScriptResumed", 800)
    }
return

; End of XMind-specific hotkeys
#IfWinActive