# Sway

A native AppKit menu bar break reminder for macOS. Build with `./build.sh`.

## Wording: how to use "sway"

"Sway" is the app's name. As a verb it only means gently moving the body, never "take a break".

- Ask questions and give instructions in plain words: "break", "focus", "step away".
  - Good: "How long do you want to focus before a break?"
  - Avoid: "How long do you want to work before you sway?", "How long will you sway?"
- Use "sway" as a verb only where its literal meaning fits, when the user is about to move: "Time to stand up, stretch and sway a little." A bolder branded line such as "Time to sway" belongs on the break itself, once the user knows the app.
- Translations don't carry the pun: translate "sway" as moving a little, not as a break.

## Localization

Every user-facing string goes through `L()` and needs an entry in all 9 `Resources/*.lproj/Localizable.strings` files, keyed by the English text.
