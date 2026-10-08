# Privacy and local storage

WhatsGram is an unofficial client using the Telegram API. Ordinary Telegram cloud messages and the private workspace settings supergroup are not end-to-end encrypted Secret Chats.

| Data | Location |
|---|---|
| Messages and media | Their actual Telegram conversations |
| Membership/topics | Telegram |
| Shared selections | Small records in a dedicated private Telegram supergroup |
| Message/chat cache | The device's TDLib database |
| Database encryption key | Android Keystore-backed / Windows protected Flutter secure storage |
| Pending events, workspace cache and device preferences | Platform protected local storage, scoped by Telegram user ID |
| Media cache | App-private files, separate from the encrypted database |
| Exported attachments | User-chosen local folder/document URI |

No hosted application backend, GitHub chat database, analytics, our own advertisements or telemetry is implemented. GitHub stores source only. The authenticated Telegram account on the device determines the sender; mobile/desktop targets are not fixed people. API ID/hash identify the application, not the signed-in account.

Every login slot has an independently generated 32-byte cryptographic database key and app-private directory. Logging out invalidates that session through Telegram and clears its active application state; it does not terminate another account/device. OTPs and two-step passwords remain ephemeral form values and are never persisted. Android backups and device transfers exclude application state. TDLib verbosity is disabled; raw native messages and request bodies are not written to application diagnostics.

Exported media and app-private media cache are not automatically encrypted by TDLib's database key. Automatic export starts off and checks selected scope, allowed category, size, network preference, protected/disappearing content and server-provided save permission. Manual exports are intentional. Never move session directories between people or upload them to GitHub.

Notifications are local to this app. Per-device mute does not change official Telegram's account-wide notification settings. Preview content is off by default. Quitting Windows or force-stopping Android prevents live reception. The app does not conceal online activity or fabricate read/delivery guarantees.
