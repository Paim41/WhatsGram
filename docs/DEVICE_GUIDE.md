# Using WhatsGram on your phone and Windows PC

## Install this update

- **Windows:** quit WhatsGram, extract the entire new Windows ZIP into a new folder, then run `whatsgram.exe`. Keep all DLLs and the `data` folder beside it. Your session is stored in your Windows user profile, not in the extracted program folder.
- **Android:** open the new development APK on your phone and install it over the existing WhatsGram app. Do not uninstall first, because uninstalling removes local app data. Updates require the same signing key; the development packages built on this workstation use its existing debug key. The phone may cache the old launcher icon briefly.

## Sign in

Open WhatsGram and choose **Connect Telegram** on each device. Enter the phone number for the Telegram account you want that device to use, then follow Telegram's requested code/password steps. Each device has its own session. Never share login codes, passwords, API credentials or session files.

## Two different accounts sharing selections

1. Sign in as account A on one device and account B on the other. Both accounts must already be able to access any groups you want to select.
2. On A: open **Settings → Workspace → Create workspace**. Enter B's Telegram `@username` or numeric user ID and confirm the displayed person.
3. WhatsGram creates a private Telegram settings group. If it shows an invite link, share it with B yourself and have B join through official Telegram.
4. On A: choose **Show pairing QR → Copy payload**. Share that pairing text privately with B. The current app accepts pasted text; it does not scan QR codes itself.
5. On B: open **Settings → Workspace → Join workspace**, paste the payload, and verify A's name and ID.
6. Open **Chats → +** to select the conversation between A and B, shared groups, or forum topics. Selecting a whole group includes all its topics. Selection changes sync through the private settings group.

Messages are sent by whichever account is signed in on that device. Pairing shares the selection list; it does not grant access to another account's private messages. The control group is hidden from WhatsGram's normal chat list but visible in official Telegram. Keep it and its original setup message intact.

## If both devices use the same Telegram account

You can sign into the same account independently on Android and Windows. Do not create a workspace by entering your own account as the counterpart: the current workspace model requires two distinct Telegram accounts. If that account already belongs to a WhatsGram workspace with a second person, copy the existing pairing payload onto the other device and join that same workspace there. A single-person workspace is not implemented in this version.

## Per-device preferences

- **System / Light / Dark**, message previews, Enter-to-send, pinned/muted chats and export settings belong to that device.
- Enable notifications separately on each device. Keep the app running for immediate reception; quitting Windows or Android battery restrictions can interrupt it.
- Automatic media saving starts off. Select a destination folder and media types on each device. Windows currently cannot determine network cost, so turn off **Only on an unmetered connection** if you deliberately want automatic exports there.
- If shared selections seem delayed, connect both devices and choose **Settings → Workspace → Reconcile now**. Joining a workspace does not join its selected groups automatically.

These packages are for development testing. Android uses debug signing; neither platform has completed the full two-account acceptance checklist in [TESTING.md](TESTING.md).
