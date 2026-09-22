# Buff Check

A 280px floating panel for party and raid preparation, styled for EllesmereUI
and inspired by Housing Decor Guide's compact Lumber Tracker window.

- Enabled in groups by default; hides during combat.
- Open **EllesmereUI > Waffle House > Adventure > Buff Check** to configure or preview it.
- `/whbuffs` shows it, including while solo. `/whbuffs off` disables it.
- `/whbuffs preview` toggles a sample 40-player layout with casting disabled.
- Drag the header to move it; use the minus button to collapse it.

The top strip shows each available group buff once. Its count is the number
of missing recipients. Hover for names (ten at a time, with an overflow count).
Click a spell your character knows to cast it. Other classes' icons show
coverage only. A provider of the corresponding class must be in the group.

Group buffs: Fortitude, Arcane Intellect, Mark of the Wild, Battle Shout,
Blessing of the Bronze, and Skyfury. Passive proximity auras and short combat
buffs are not individual missing-buff tasks.

The assignment list offers known Earth Shield, Beacon of Light, Beacon of Faith,
Source of Magic, Blistering Scales, and Soulstone. Click a name to choose a
recipient, then click the adjacent spell icon to cast. Each spell tracks only
its chosen recipient. Assignments are saved by character and recipient GUID.
The list shows at most four rows; the recipient picker shows eight people per
page. Names are sorted by role and name. No automatic target choice is made.

Ready buffs hide by default. Unreadable, disconnected, dead, or invisible
recipients are never counted as definitely missing. A question mark indicates
unavailable coverage; hovering supplies details. WoW still enforces range,
cooldowns, valid targets, and learned spells.

The panel maintains a cached roster. Group joins, leaves, role changes, and
world/spell changes rebuild the relevant roster and spell information.
Normal aura events reuse that list and update only affected members; readable
aura changes unrelated to tracked buffs are ignored. Bursts share a 0.2-second
window, with each affected member invalidated once. Aura removal events also
handle buff expiration while the panel is hidden by Only When Needed.

There is no recurring full buff scan. While an eligible group is being
tracked, a five-second availability check catches members becoming visible
or readable without an aura event. It checks cached members' availability
only; unchanged checks do not query buffs, collect results, or redraw the
panel. The watch stops in solo play, preview, combat, and excluded situations,
or when Buff Check is disabled. There is no per-frame scanner, automatic
casting, or group messaging.

Local validation covers the model, 40-player aggregation, secrecy handling,
secure button configuration, paging, and layout bounds. In-game visuals and
actual casts still require a WoW `/reload` and play testing.
