# Configuration validation — 0.1.0-dev.1

The configuration pass is deployed for live review. This is a development
prerelease, not a published release or an in-game certification.

## Local checks

All 39 Lua regression scripts passed. Every manifest entry exists, and all
19 listed Lua files passed `luac -p`. The original configuration deployment
and the later Vignette Radar deployment were copied from the authoritative
source and verified against the installed files by SHA-256. Unrelated installed
files were preserved.

EllesmereUI 9.2.2 provides a fixed 1005 × 686 content viewport with 45-unit
side margins. The native settings rows are 915 units wide. Scaling changes
their displayed size; longer pages scroll.

| Surface | Covered locally |
| --- | --- |
| Item Queue | Native margins at 1005 and defensive 640 widths; header, Auto Sort and list gutters; every drag source/destination pair; cancel, reopen and automatic priority reset. |
| Adventure | Populated Soiree, Delve Companion and Group Buff Check sections; all settings retained; no empty activity headings or blank Situations button. |
| Bags | Native row sizing and scroll height for closed, empty and populated Frozen Slots manager. |
| Ignored vendor NPCs | Closed, empty, one and multiple entries; name/ID/action gutters; draft add/remove/save/cancel; safe target-name caching; combat guards; validation-tooltip cleanup. |
| Buff Frame | Only the supported repair action is exposed. Retired rules stay saved and cannot drive native aura updates. Repair remains guarded in combat. |
| Soiree chooser | Native EUI font and tooltip path; distinct choice descriptions; one-time show-every-visit reset; live unique-Favor recommendation and tie handling; info pin/dismiss; row and footer bounds; small-screen scaling; combat and window lifecycle. |
| Vignette Radar | Live-minimap-only filtering; secret/unavailable data rejection; world-yard conversion; heading-relative projection; stable red blip controls; 220 × 252 panel bounds and header/field gutters; native Adventure controls and preview isolation. |

## Live review still required

Capture the real UI after `/reload`: Adventure, Item Queue, the expanded
Vendor manager, `/whsoiree` with an invitation open, and Vignette Radar first
in preview and then near a live minimap vignette. Inspect dropdowns, hover and
pinned details, scroll to the final controls, and check for clipping at the
user's smallest supported panel scale. Exercise normal manual invitation
confirmation separately; the helper never sends the invitation.

The Soiree styling reset is temporary. Remove it before release publication,
after the visual pass is accepted. Keep the base version unchanged until a
release is explicitly accepted.
