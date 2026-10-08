# Pair two independent Telegram accounts

1. Each person signs into their own account. Either account can use Android or Windows.
2. Person A opens Settings → Create workspace, enters B's public username or Telegram user ID, checks B's name and numeric ID, then explicitly confirms group creation/invitation.
3. The app creates a private settings supergroup and enables visible earlier history. Privacy restrictions can prevent directly adding B; in that case it shows a single-member invite link. Send the invite privately yourself. The app does not send unsolicited messages to people.
4. A sees a QR code and copyable pairing JSON. This includes the control supergroup ID, workspace UUID, genesis message ID and expected owner ID. It contains no API hash, session, password or verification code.
5. B joins the settings group with official Telegram, opens WhatsGram Settings → Join workspace, and pastes the pairing payload. B checks the owner name and ID. The app compares the genesis sender with Telegram's message metadata and only accepts B if B is a genesis participant.
6. Either person opens the + chat picker, selects their direct conversation or shared supergroups, and optionally chooses forum topics. A whole-group selection includes every topic.

The QR is a portable representation of the pairing payload; this build accepts pasted payloads rather than requiring camera scanning. If B cannot find A by numeric ID, opening A's profile or direct conversation in official Telegram first can make the user available to TDLib.

The settings group is hidden from WhatsGram's normal selected chat list and notifications. Its records remain visible in official Telegram. Joining the workspace does not grant access to other conversations. Inaccessible groups show Access required without a preview. Arbitrary third-party private chats, Saved Messages, Secret Chats and channels are not offered in the picker.

Changes are shown immediately and marked pending until Telegram confirms their settings message. Offline changes are saved locally. Reconnect/resume replays available history and merges deterministically, preserving deselections. Recovery requires the original trusted genesis. Disconnect clears local pending operations and stops synchronization; it does not delete Telegram history or leave selected groups.
