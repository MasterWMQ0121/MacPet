# MacPet 🐾

A native macOS desktop pet using the pixel-art cat from `pet.svg`
(extracted from the original screenshot SVG, background removed for transparency).
It is also a gentle wellness companion: it reminds you to drink water,
take walk breaks, and eat lunch/dinner on time.

## Where it lives

- **Installed app: `/Applications/MacPet.app`** (Finder → Applications → MacPet)
- Source + build output: this folder (`MacPet.app` here is the build artifact)

It registers itself as a **Login Item** on first launch, so it starts
automatically when you log in (System Settings → General → Login Items shows it;
the checkbox in the in-app settings window controls it too).

## Run

Double-click `/Applications/MacPet.app`, or:

```sh
open /Applications/MacPet.app
```

## Pet behavior

- **Two-frame walk animation**: alternates between the standing pose
  (`pet0.png`) and the leap pose (`pet1.png`) in step with its bounce.
  Standing pose when idle/paused, leap pose when jumping, falling, or dragged.
- Drops in from the top of the screen and lands above the Dock.
- Walks back and forth, faces its direction of travel,
  and turns around at screen edges.
- Randomly pauses to idle or does a little hop. Half of the idles are a
  quick standing rest; the other half play a **settle-down sequence**:
  stand → sit (`pet_sit.png`) → lie belly-up (`pet_lie.png`) → sit → stand,
  lasting 9–16 s.
- **Belly rubs** 🥰: after lying belly-up for 3 s, it purrs and asks
  "摸摸我吧～" or "陪我玩一会儿吧～". Stroke your mouse back and forth over
  it — each stroke direction shows a different belly-up frame
  (`pet_lie.png` ↔ `pet_lie2.png`), and it won't get up while being petted.
  Stop petting and it carries on: sits up, stands, walks off.
- **Click the cat** to freeze it in place — a ✕ button appears above it.
  - Click the **✕** to quit the app.
  - Click the cat again to resume (it falls back to the ground first).
  - While frozen you can drag it anywhere and it stays put — like a sticker.
- **Right-click the cat** to open the Reminder Settings window.
- **Drag** it with the mouse — when you let go, it falls back down.
- **It's also a trash bin** 🗑️: drag any file (or several) from Finder onto
  the pet — it opens its mouth (`pet_eat.png`) while the file hovers, and on
  drop the file is moved to the Trash (recoverable, not deleted) with a
  "Pop" chomp sound and a confirmation bubble. The first time you feed it a
  file from Desktop/Documents/Downloads, macOS may ask to grant folder access.
- **Sleep mode** 😴: drag the pet (partly) past any screen edge and let go —
  it curls up and sleeps (`pet_sleep.png`). It automatically tucks itself
  back so a good chunk always stays visible and clickable. While asleep it
  stays put (no falling, no walking) and can be dragged anywhere.
  **Double-click** it to wake it up — it falls to the ground and walks on.
  ("Drop From Top" in the 🐾 menu also wakes it, as an emergency recall.)
- A 🐾 menu bar icon (no Dock icon) has Reminder Settings (⌘,),
  "Drop From Top" (⌘R) and "Quit MacPet" (⌘Q).

## Reminders 💧🚶‍♀️🍱

The cat shows a speech bubble (with a chime and an attention hop):

| Reminder | Default |
|----------|---------|
| 💧 Drink water | every 60 min (only while actively using the Mac) |
| 🚶‍♀️ Walk break | after 45 min of continuous work — stepping away from the keyboard/mouse for 5+ min resets the timer |
| 🍱 Lunch | 12:00 |
| 🍝 Dinner | 18:30 |

- **Custom reminders**: in the settings window you can add your own —
  type any message, choose "Every N minutes" or "Daily at HH:MM", and Add.
  Each one can be toggled on/off or deleted (✕). Saved permanently.
- **Custom messages for the built-in four**: each built-in reminder has a
  text field below it — type your own message to replace the default
  bilingual one, or leave it blank to keep the default.
- **Right-click the cat** (or 🐾 menu → Reminder Settings…) opens the
  settings window, organized in three tabs:
  - **提醒 Reminders** — enable/disable the built-in four, change intervals,
    meal times, and custom message texts.
  - **自定义 Custom** — add/toggle/delete your own reminders.
  - **通用 General** — start at login, Drop From Top, Quit, and a full
    scrollable bilingual (中文/English) **user manual** covering every
    feature: pet controls, sleep mode, the trash bin, all reminder types,
    and the menu bar.
  Changes apply immediately and are saved permanently (UserDefaults).
- The speech bubble is the pixel-art `bubble.png`, 9-sliced so it stretches
  to fit any text. Click it to dismiss (it also auto-hides after 18 s).
- "Test Reminder" in the 🐾 menu previews a bubble immediately.

The message texts (bilingual 中文/English) live in the `Config` enum at the
top of `main.swift` — edit and rebuild.

## Rebuild after editing

```sh
./build.sh
```

Builds `MacPet.app` here and, if `/Applications/MacPet.app` exists, updates it
too (quit the pet first, then relaunch). Requires Xcode Command Line Tools.

Debug tricks (run the binary directly with an env var):
- `MACPET_TEST_REMINDER=1` — fires a test bubble 3 s after launch
- `MACPET_TEST_SETTINGS=1` — opens the settings window 2 s after launch
- `MACPET_TEST_EAT=1` — shows the open-mouth drag-over pose for 6 s
- `MACPET_TEST_SLEEP=1` — puts the pet to sleep 2 s after launch
- `MACPET_TEST_IDLE=1` — forces the settle-down idle sequence 2 s after launch

## Swap the artwork

Replace `pet0.png` (standing) and `pet1.png` (leap/stride) — transparent
PNGs, artwork facing left — and run `./build.sh` again. More frames can be
added by extending the `["pet0", "pet1"]` list and frame logic in `main.swift`.
(`pet.svg` remains as a single-frame fallback.)
