# Native buff-frame controls

Automatic collapse/expand is unavailable on the supported Retail client.
Calling Blizzard's native state setter from addon code also runs its aura
update. That update can install Blizzard's repeating `OnUpdate` under addon
taint, causing secret-value errors later, including `hideUnlessExpanded`.
Checking for combat or restricted aura access and wrapping the call in `pcall`
does not make it safe.

Waffle House leaves Blizzard's live buff state, scripts, buttons, aura containers,
and frame methods untouched. Its saved rules and former display preferences remain
stored, but do not run. General > Buff Frame exposes only the working anchor
repair, with no unavailable automation switches or rule editors. Use Blizzard's native collapse/expand
button manually and Blizzard Edit Mode to position the frame.

After installing this correction, use `/reload` to discard any tainted native
handler left by the previous code. The addon deliberately does not attempt to
repair an already-tainted handler in the running session.

## Missing PlayerBuffsMover anchor

`PlayerBuffsMover` is a legacy MoveAnything virtual frame. An Edit Mode layout
that saved it as Buff Frame's relative anchor can emit a missing-region warning
when that mover no longer exists. Selecting the invisible frame in Edit Mode
is not required for the targeted repair.

After `/reload`, Waffle House checks the saved layouts once. It backs up the
original data in `WaffleHouseDB.buffFrameAnchorRepairBackup` and changes only
Buff Frame primary anchors whose target is exactly `PlayerBuffsMover`. It uses
Blizzard's default upper-right position (`TOPRIGHT`, `UIParent`, `TOPRIGHT`,
`-255`, `-10`). Other systems, settings, layout selection, and valid anchors are
preserved. Frames with a second anchor are skipped rather than guessed at.

The repair uses `C_EditMode.GetLayouts` and `C_EditMode.SaveLayouts`, with the
same preset-layout augmentation used by Blizzard. It does not call live frame
methods or modify the Edit Mode manager's layout tables. Startup repair is
skipped during combat, while Edit Mode is open, or when unsaved changes exist.
Close Edit Mode and leave combat before requesting a manual repair. There is
no polling or retry loop.

On confirmed success, chat reports **Repaired ... saved buff anchor(s)**.
Run `/reload` once more to apply the saved position. Saving alone does not
prove the live frame moved. The unchanged original snapshot is kept for recovery.

If the startup check could not run, use `/whbuffrepair` or **General > Buff
Frame > Repair Missing Anchor**. The command reports failures or that
no matching broken anchor was found, without resetting the entire layout.

## Verification

Local regression tests check that saved enabled rules cannot call the native
state setter, install a tainted update handler, access native aura state, or
start an event/polling loop. They also check that manual handlers and saved
preferences remain unchanged and that the options expose only the supported repair.
The regression fails against the prior runtime.

Repair tests cover exact-target changes, unchanged neighboring frames/settings,
the full pre-repair backup, preset augmentation, duplicate suppression,
combat/Edit Mode guards, skipped dual anchors, rejected/unconfirmed saves,
and preservation of the active layout.

These are mocked tests, not an in-game client test. In-game verification still
requires a reload, manual collapse/expand, combat with buffs active, and saving
the repaired Edit Mode position if the missing-mover warning occurred.

## Native source references

- [State setter and aura update](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua)
- [Edit Mode per-frame position reset](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua)
- [12.0.5 layout loading and saving](https://github.com/Gethe/wow-ui-source/blob/12.0.5/Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua)
- [12.0.5 Buff Frame preset](https://github.com/Gethe/wow-ui-source/blob/12.0.5/Interface/AddOns/Blizzard_EditMode/Mainline/EditModePresetLayouts.lua)

Line numbers vary between client builds.
