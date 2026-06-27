# Introduction

***

This Setup will allow you: 
 - To learn through patterns.
 - Utilize both your eyes and ears in learning.
 - Use your ears ONLY.

It is recommend to test the script yourself by opening an .xmind file like in examples/Test.xmind

### The Main script for Learning through English language is XXMM5.exe
### The other script for learning through Japanese language is XMM5_Japanese_Only_Haruka.exe

#### <span style="color:red">MAJOR FLAW</span>: This setup requires you to create mindmaps in order for you to use this setup, in other words, this setup is a tool.

- After figuring out this setup and all the features of the script + xmind app, create your own mind maps that will be compatible with this ahk setup.


***
#### This script CODE is made with AI(Artificial Intelligence). 
#### The innvotive ideas, testing, debugging ideas, designing ideas, improvements, All conditions/state ideas, prompting and more came from ME (licensor), a sole person.

- Reason: 
  - NO: learn to code ---> create an ahk script---> start learning using this setup.

  - YES: create an ahk script ----> start learning using this setup.

***

* This script will only work when Xmind app is in focus. And is only meant for xmind app.

  * See F12 for a condition

* This script uses SAPI voices of Microsoft Windows(7, 8, 10, 11).
* This script has alot of Conditions and clever features and only requires a mouse and F1 to F12(not F8) keys, Page/up and Page/down and Scrol Lock Key of Keyboard.

* I will be using the word "tts" instead of SAPI voices throughout this README, both means the same thing. 




`Links to sections` 

1. [Requirements](#◉-requirements)

2. [Setup](#◉-setup)
   - [TroubleShooting and checking Setup](#troubleshooting-and-checking-setup)
3. [Default State of the Script](#default-state-of-the-script)
4. [Usage and Working Guide](#◉-usage-and-working-guide)
   - [Mouse Guide (Controller)](#◉-mouse-guide-controller)
   - [Smart tooltip Messages](#◉-smart-tooltip-messages) 
   - [Keyboard Guide ](#◉-keyboard-guide)


***
## ◉ Requirements
1. You need a computer mouse that also has Mouse button 4(xbutton1) and Mouse button 5(xbutton2).

2. You also need balcon(from balabolka), nircmd, VBCABLE(Specifically "CABLE Input & Output"), lighthost with plugins and Autohotkey 1.1.37 version(the ahk app isn't needed if you are gonna use the .exe version of it).

3. The heading tts needs tab indentations to work properly. 

(If you don't fulfill the first 2 requirements then launching the ahk file will give you an error OR it won't work properly)
***
## ◉ Setup

* **Download XMind latest version**
  - Reason: This script is only meant for xmind app and will **NOT** work in any other app or place. And within xmind app its expects tab indentations when copying a mind map, for heading tts.

* **Download VCABLE_Driver_Pack45(1.29MB)** from [here](https://vb-audio.com/Cable/) (Offical website). VB-CABLE is donationware; donations are welcome.

  - Restart your PC after installing VCABLE_Driver_Pack45.

  - Purpose: To create a virtual audio device inside your system as "CABLE Input" in output section along with your original 'Headphones' and "CABLE Ouput" within the input section along with original 'Microphone' in sound settings of your system.

  - Reason: The script will switch the output device to "CABLE Input" when a tts is started, hence allowing you to modify this virtual device however you like within the light host without changing your default device "headphones" output sound.

  - CABLE Input and Headphones are mentioned within the script so make sure you get the "CABLE Input" from the VCABLE pack and make sure Your Original out device name is "Headphones"

  - You should have what i have within sound settings:
  * ![](assets/sound_settings.png) 

  * ![](assets/sound_settings_2.png)

* **Download lighthost** or any other VST device since it is not connected with the script, it will only modify the virtual device sound whom is switched to by the script when a tts is started. I reccomend MeldaProduction plugins within light host for tts sound manipulation.
  - I don't know about other VST but for Lighthost the settings are: 
  * ![](assets/lighthost_device_settings.png)
  * Meaning the final output device should be your default one.

***

*The following two files(balcon and nircmd) are connected with the script meaning the file paths are mentioned within the script in Section: 1, hence do not change it in any way unless you are going to modify the paths within the script yourself.*
* Create a Folder named `XMIND TTS SYSTEM` within F: disk and place the following files in it:
  - **Download balcon(823KB)** from [here](https://www.cross-plus-a.com/bconsole.htm) (Offical website: balabolka). Place it within the folder as `F:\XMIND TTS SYSTEM\balcon\balcon.exe`
    - Purpose: balcon will use the windows SAPi voices to read.

    - Make sure you have `Microsoft Eva Mobile` SAPI voice becuz it will be mentioned within the Section: 1 of the script as Requirement.

    - Use the following command in "command prompt" to see if you have 'Microsoft Eva Mobile' SAPi voice within your Windows:
    
    <pre>powershell -command "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }"</pre>

    - In script, `Microsoft Eva Mobile` is set for balcon. You can change it in section: 1 with other voices. Make sure you write it within ''


                    
  - **Download nircmd x64(152KB)** from [here](https://www.nirsoft.net/utils/nircmd.html) (Offical website). The file is at the bottom of the webstie. Once Downloaded, Place it within the folder as `F:\XMIND TTS SYSTEM\nircmd\nircmd.exe`
    - Purpose: The script will use nircmd to switch the device, from original to CABLE Input,  when a tts is started.


#### For tidiness, place balcon, nircmd, light, VST plugins within the same "XMIND TTS SYSTEM" folder.

#### **Summary:**


- VCABLE pack will create two virtual devices named:"CABLE Input" & "CABLE Output", in sound settings of your windows.
- Script will switch the output device to "CABLE Input" using nircmd when a tts is started.
- Balcon will read using SAPi voices of Microsoft windows.
- In lighthost the "CABLE Output" recieves sound through "CABLE Input" in sound settings of windows
- since the output the device goes through lighthost + VST plugins, it will be modified before reaching the final Output device which should be your Default(Headphones) device then your ears.
- Once a tts is stopped by methods(explained below), reloading the script or exiting the script:
 - Then the device will switch back to original from "CABLE Input".

If you dont modify the output sound, you will get bored of the default balcon sound.
***
## TroubleShooting and checking Setup
- Not hearing any tts:
  - Just press F3 ON then start a tts then just swtich devices within lighthost/prefernces/Audio settings like:
    -  In OUTPUT, change your default(Headphones) with other option and then back to your default(Headphones) device, while a tts is running in the background.
    - In Input, Do the same and revert back to "CABLE Output"

- No txt files are generated in %temp% folder.
  - Then it is your system clipboard issue. 
  - You can check your clipboard by pressing 'window key + V' to see if it is working.

- Make sure the "CABLE Input" is exactly as written here within sound settings as mentioned above in images.

- When a tts is stopped by methods(explained below), reloading the script or exiting the script:
  - Then the device should switch back to original from "CABLE Input".
***
## Default State of the Script

**It means the state of every function key and feature when you run the script for the first time or re-run it or reload it or exit it and re-launch it.** 

So when you run the script:
 - xbutton1: OFF

 - F1: OFF

 - F2: OFF

 - F3: OFF

 - F4: increment the currently selected state of F6  (depends on F6 state)
 - F5: decrement the currently selected state of F6  (depends on F6 state)

 - F6: mmHeadings Filter Level: ALL

 - F7: shows F6 state

 - F9: OFF

 - F10: OFF 

 - F11: OFF
 - F12: ON
 - Page up/down: "Balcon speed: 5"
 - Balcon voice: Microsoft Eva Mobile
 - Balcon volume: 100
 - Scroll Lock: Resumed

  
***
## ◉ TTS Systems Info

Basic info about tts(note and heading):

- The script uses system default clipboard for both the tts operations, So make sure whatever you copy, manually, from anywhere should be pasted into its desired place before starting a tts.
  - And make sure you **enable clipboard**. 


- The note tts can read upto 120k words, last time i checked. You can see and test it yourself in examples/Test.xmind and the heading tts can also read a mind map that has like 5k headings, i also checked this.

- Both the tts uses **file-based system**, you can see a txt file being generated in %temp% folder.
  - How? when a tts is started or before starting a tts, just press F12 ON and start a tts then you will be able to see a txt file being generated in %tempt% folder.

- No Worries, the script uses a **Clean UP System** (_CleanupTempFile:) that regularly do a clean of the files generated by the script, the script will immediatly remove the txt files that are no longer needed for the tts, probably when the script has already feed the text to balcon.
 - Looping Mode has a seprate function dedicated to removing txt file that are generated when Loop Mode is ON(F3). 
***
## ◉ Usage and Working Guide.

Before starting make sure that a heading note opening key is F8 and not Ctrl+Shift+N within xmind app.

**Each Key press whether it is in mouse or in Keyboard(F keys, page up/down, scrollock) will show a `Colored tooltip message` near the mouse cursor. To create a memory of colors without looking at the text within each tooltip message.**

- Mouse is the Controller.
- Those some keys of Keyboard are just Prerequisiste setting before starting a tts.

***
***
## ◉ Mouse Guide (Controller)
***


***The mouse have two states that are ON and OFF by xbutton 1 showing a tooltip message "Features: ON"(green) and "Features: OFF"(red)*** 


- **Xbutton 1 is a MASTER TOGGLE. Each state of it changes the function of almost all the buttons within the mouse.**
***
### ★ When xbutton1 is OFF
***
#### ➤ **xbutton2:**
 - When pressed Once will activate shift scroll now when you scroll wheel up or down, you will move across the xmind canvas as left and right. Basically, the script is using the shift + scroll wheel feature which is default but now **you dont have to press Shift on keyboard**, just scroll wheel.

 - When pressed again will OFF the shift scroll feature and the scroll wheel revert back to its original feature which is up and down movement across the canvas of xmind app. 

 #### ➤ **Middle Mouse button and Scroll Wheel:**
 - Both the scroll wheel and the Middle Mouse button has the default settings and is not interfered by the script is any way.

 #### ➤ **Left and Right mouse buttons:**

 - No feature is added meaning they are in there default state and has default features of xmind app. Default features like Panning.

***
 ### ★ When xbutton1 is ON
 ***

{Make sure you select a heading before making the "Features: ON" becuz xbutton1 ON state mostly works when a heading is selected}


#### ➤ **Left Mouse Button: (Note open/close)**
- When **a heading** is selected, press Left mouse button once-it will open the note of the selected heading, placing the **text cursor** within the note at the start of the note-text, and pressing the Left mouse button  again will close the note. Also when a note is open then you can control the **"text cursor"** using scroll wheel up/down.

  - Actually when You press Left mouse button, when a heading is selected, the script sends F8 then sends two ctrl + home after some delays so that the cursor move at the start of the text witnin the note. **Meaning you dont have to use keyboard** the script does everything. Also if the note has text in it then you can u scroll wheel(while a note is open) to scroll down: it actiually sends up and down arrow key if a note is open and you use scrol wheel.

### ➤ xbutton2:  Note tts starter/stopper
- After you have open a note of a heading that has text in it then just press xbutton2 and it will start the note tts.
  - How? it selects all(ctrl + A) then copies it(ctrl + c) then ctrl + home to place the **text cursor** at the start of the text in note. The copied text of the note is then pasted into a file(txt) then use a chunking system to divide the text and then feed each chunk to balcon, there is no pause. 

- Press Xbutton2 again to stop the note tts. 



#### ➤ **Right Mouse button: (Navigation like a Joystick) 🕹️**
 {My mouse sens in setting is 7}
- When a heading is selected, press and hold Right Mouse button and moving it left will send left arrow key, moving it right will send right arrow key, moving it up will send up arrow key and moving it down will send down arrow key from the script directly to the pc **without using keyboard.** 
  - Reason: To easily move on a mind map **without having to press any arrows key in keyboard.**
 
#### ➤ **Middle Mouse Scroll Wheel:**
 -  Will automatically activate zoom in/out feature using scroll wheel only **instead of using keyboard** ctrl + scroll wheel.

 - When xbutton 1 is OFF then this zoom in/out will be disabled and then the xbutton1 OFF features will take place.

 - Xmind app losing focus will also **automatically OFF this feature.**

### ➤ **Middle Mouse Button: Heading tts starter/stopper**
<pre>Fruits
	Tropical
		Banana
		Pineapple
		Mango
	Berries
		Strawberry
		Blueberry
		Raspberry
	Citrus
		Orange
		Lemon
		Lime
	Stone fruits
		Peach
		Plum
		Cherry
	Melons
		Watermelon
		Cantaloupe
		Honeydew</pre>

- When **a heading** is selected then press middle mouse button to start the heading tts. It will read the heading tts based on hierarchy from top to bottom.
  - In above example: if u have selected Test (when xbutton1 OFF) and press Middle mouse button (when Xbutton1 ON) then the heading tts will start, reading from "Test" upto "Honeydew".
  - The script uses tab indentations to understand the hierarchy of the mind map, **SO MAKE SURE THAT A HEADING NAME DOESN"T HAVE A LINE-BREAK**(by shift+Enter) when making a mind map. 

- **The Heading tts is the most complicated feature in this entire script, in fact most of the F keys functions exit for heading tts only. The heading tts is explained in detail at the end.**


#### ➤ **Scroll wheel**: 
 - No features, it has its default state which is up/down movement across the canvas of the mind map. 

***
***
<pre>
Once Your done upto to now, you should be able to do and understand just like in the following video:
assets/xmind-XMM5-ahk.mp4</pre>

***
## ◉ Smart tooltip Messages:
As shown in the video below, each state change, event start/stop/end, and errors will show tooltip messages, near the mouse cursor. Each tooltip message has a distinct color, border color, font color, font size, widht/height. It will allow you to create a memory of colors, a mental pattern for conditions and status, rather then looking at the text in each tooltip message.

- Error messages will be shown, for [Mouse Guide (Controller)](#◉-mouse-guide-controller) ONLY, when attempting to do something without fulfilling Prerequisiste conditions.
  - example: pressing xbutton2 when xbutton1 is ON and NO note of a heading is Open, will give an error message.

<pre>WATCH THE VIDEO AT: assets/tooltips.mp4</pre>

Only few other tooltip messages aren't shown within the video.
***
***
## ◉ Keyboard Guide 
***

### Intro

-  The script uses the following keys that modfies the tts depending upon the state of the tts and kind of tts:

   - **F1**, F2, F3, F4, F5, F6, F7, **F7 special**, F9, F10, F11, F12, Page up, Page down and Scroll lock.

-  First the simple functioning Keys will be explained then the complex one (F1 and F7 special).

- You should remove any assign functions(like snapshot through F7) from the keys that are mentioned above becuz it might interefere with the features that are provided by the script.


### Scroll Lock key:

 - It pauses the scrip when pressed once and resumes it when pressed again.
 - It will only work when xmind app is in focus.

### F3 Loop Mode:

- When F3 is pressed Once, it will ON the Loop Mode and when pressed again, it will OFF the loop mode.

- It works by repeating the tts until you stop the tts manually or OFF the Loop Mode(while a tts is running) or reload the script or exit the script.

- Each iteration of Loop of a tts has exactly 150 ms gap [loopGapMs].

- You can ON Loop Mode in the middle of a tts session and it will still work but still it is best to just ON it before starting a tts.

- It will Loop forever.

- It will switch the device and keeps it switched until the tts is stopped manually or the script is reloaded or the script is exited.

### Page up / Page down:

 - It Controls the balcon speed.

 - Page up increases the balcon speed by 1 for every click on it, and Page down decreases balcon speed by 1 for every click on it.
- When Loop Mode is ON then any change in the speed of the balcon will be shown in next iteration of Loop.

- Maximum speed is 10 and Minimum speed is -10.


### F12 TTS LOCK:

- If **F12** is **OFF:**  
  - Xmind app losing focus or xbutton 1 OFF will stop the currently running tts.

- If **F12** is **ON:**
  - Xmind losing focus or xbutton 1 OFF will **NOT** stop the currently running tts.

- I reccomend making it ON everytime you launch or reload the script.

- It's OFF state purpose was to prevent you from opening another app while a tts is running. Like No distractions.

### F11 Analytical Mode:

-  It was a debugging feature at the early stages of development of the script.

- Keep it OFF unless you wanna see alot of tooltip meesages popping up especially in F10 system.

- It has no other function besides showing a specific colored tooltip message for every event and since it appears on the same place as other tooltip messages so it might block or gets blocked by other tooltip messages.

### F9 Audio Lock:
- When it is ON:
  - It will switch the device and will not switch it back unless you OFF this feature or exit the script or reload the script.

- When it is OFF:
  - The device will switch when a tts is started and will switch back to original device after the tts is ended or stopped or the script is exited or the script is reloaded.   

### F10 Duel detection:

- I recommend keeping it OFF.

- It's Purpose is to prevent you from listening to a note tts of a heading and opening a note of a different heading.

- How it works?: It works using hash tables and real time heading names copying. Once a tts is started the script will copy heading names like every fraction of second and compare it with the heading name whose tts started. IF you cames across a heading name whose name doesn't match the original then upon opening this different heading note(using L-MButton)will stop the currently running note tts.

- It will only be able start its detection process of headnng names if you hover around headings using Right Mouse button navigation feature.

- It will make the Right mouse button feature very slow so Keep it OFF.

### F2 Number suppression:

- As the name suggest, it will remove all the numbers from note text and mind map headings before feeding it to balcon to be read.

- It will **NOT** act on the prefexes made by F1 Anouncement system of heading tts but it will act on the heading names.

- It will act on note text.

- If Loop Mode is ON then ON'ing or OFF'ing this feature will cause:
  -  additon or removal of this feature from the text(notetts) or heading names, (headingtts) that will be Feed to balcon, **in next iteration of loop**.

{Test this feature within examples\Test.xmind}


## F1 Anouncement System:
- It is for heading tts **ONLY** and will not act on note text of note tts.

- It will add a prefex to the Mind map structure before it is being fed to balcon for reading.

- Just press F1, then chose any of the 1 to 6 number keys and then start a headingtts to see the effect of F1 feature.

- pressing 1, 4, 5 twice will switch to a modified feature of the keys that are much better then a single click.

- I recommoned 4 or 5 key single click for understanding the hierachy of a structre without loking at it.

## F6 

- It has 3 features that you can switch by pressing it again and again.
- Each of the 3 features are controlled by F4 and F5.

#### mmHeading level filter:
- It will ONLY work for Heading tts.
- It is controlled by F4 and F5 as decrement and increment.
- lvl 1 means read the selected heading only.
- lvl 2 means read the selected heading along with its sub-heading.
- lvl 3 will read the selected heading, its sub-headings, and their sub-headings.

- Maximum levels that you can select is 200

#### speedMultiplier:
- It will ONLY works for note tts.
- It removes spaces and words and more the higher you go by pressing F5.
- If Word/line is NOT equal to 0 then speedMultiplier 1.5, 2.0 is negated, 1.5 and 2.0 removes extra spaces between text.

#### Word/Line:
- It will ONLY work for note tts.
- 0 means no change.
- -1 means one word line.
- -2 means two words per line and so on upto -10 which is 10 words per line.
- REASON: there is no other way to reduce the speed of balcon below 1 hence you can by placing words per line.


## F7

- It shows the current status of F6 like what is selected on F6 so i can control that feature using F4 and F5.


 ## F7 Special:
 
- when the F6 status is "mmsHeading level filter" then press and hold F7 for 0.3 seconds to open a GUI window.
 
