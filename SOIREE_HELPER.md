# Saltheril's Soiree helper

Waffle House adds guidance to the four-faction invitation window. It does not send invitations or spend Favor tokens.

On the first invitation, or when accepting **High Esteem** / **Favor of the Court**, a focus chooser offers:

- **Extra Favor:** highlight the available invitation with the uniquely largest listed Saltheril's Favor reward. If the data is missing or tied, leave all invitations unmarked.
- **A court faction:** highlight that faction's guest, which determines the faction offering the weekly Fortify the Runestones quest. This is a faction-route preference, not a claim that the invitation has the highest immediate reputation total.

The recommendation uses the EllesmereUI accent around its entry and invitation button. Portrait badges provide styled EUI explanations on hover; clicking a badge opens the focus chooser. The tooltip displays the invitation's reported gains and losses, the extra Favor when present, and the reason for the recommendation.

The focus chooser uses native EllesmereUI typography and buttons, a short description for each faction, and an info button with live reward details. Hover **i** for details or click it to keep them open. **Extra Favor** is highlighted as recommended only when the currently available invitation rewards have one unique Favor winner; a saved faction focus is labeled separately.

For this development styling pass, revision 1 resets **Show Soiree Helper** and **Ask for Focus Each Visit** to on once after reload. The saved faction focus is retained. Subsequent user changes to those toggles are respected. Remove this temporary styling reset before release publication.

Use **`/whsoiree`** or **Adventure → Saltheril's Soiree** to change focus. The preference is shared across characters in `WaffleHouseDB.soireeHelper`. **Ask for Focus Each Visit** reopens the chooser on later visits. **Show Soiree Helper** disables the guidance and popup together.

## Scope and validation

- Recognizes the complete set of four court factions from current localized option subheaders, with English fallback. It never assumes a fixed guest name or column order.
- Reads the live PlayerChoice rewards each time. No weekly reward rotation is hardcoded.
- Supports structured reputation rewards and explicit signed faction amounts in the invitation description. Unavailable data stays unknown.
- Hides guidance in combat, on window close, and when pooled option frames are reused for other content.
- Uses owned overlays and post-hooks; native invitation click handlers and confirmation dialogs remain in charge.
- The focus chooser scales to fit small screens. Info badges stay inside the portrait with an eight-pixel gutter; no extra toolbar competes with the native title or reputation rows.

Local checks:

```text
lua tests/soiree_rules_test.lua
lua tests/soiree_ui_test.lua
luac -p WaffleHouse_SoireeRules.lua
luac -p WaffleHouse_Soiree.lua
```

These are mocked Lua checks, not an in-game test. Before release, verify a live invitation at your smallest UI size: first-use and returning focus, all four faction choices, Extra Favor, info hover, close/reopen, and normal manual invitation confirmation.

## References

- [Blizzard PlayerChoice API data, mirrored from the client](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerChoiceDocumentation.lua)
- [Blizzard normal option implementation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_PlayerChoice/Blizzard_PlayerChoiceNormalOptionTemplate.lua)
- [Saltheril's Soiree event overview](https://warcraft.wiki.gg/wiki/Saltheril%27s_Soiree)
- [Court factions and in-game introductions](https://warcraft.wiki.gg/wiki/Honored_Guests)
- [Saltheril's Favor](https://www.wowhead.com/item=238987/saltherils-favor)
