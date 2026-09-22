<p align="center">
  <img src="docs/assets/waffle-house-readme-banner.png" alt="Waffle House — EllesmereUI Quality of Life" width="100%" />
</p>

<p align="center">
  <strong>Thoughtful quality-of-life tools for World of Warcraft Retail and EllesmereUI.</strong><br />
  Better vendor runs, calmer bag management, faster group prep, and automation that stays under your control.
</p>

<p align="center">
  <a href="https://github.com/zero-wow/WaffleHouse_EllesmereUI/issues">Report an issue or request a feature</a>
</p>

> **Development prerelease — 0.1.0-dev.1.** Waffle House is being prepared for its first public release. Expect iteration, and please include steps to reproduce when reporting a problem.

## What it brings to EllesmereUI

Waffle House extends EllesmereUI with practical tools that reduce friction without taking decisions away from you. It is built around the native game UI and EllesmereUI's existing surfaces: discoverable settings, visible state, and deliberate actions.

| Area | What Waffle House adds |
| --- | --- |
| **Vendor Bags** | Currency legend with filters, a grid or sortable list view, saved shopping pins and notes, richer tooltips, and a quantity picker for **Shift-right-click** purchases. |
| **Interact Key** | An inline list of ignored vendor NPCs with names and IDs. Add the current target or enter an ID, review the draft, and save or cancel. |
| **Item Queue** | A priority-aware button for usable unlocks and utility items in your bags. You choose when to use an item; it never uses one automatically. |
| **Bags** | Freeze a main-bag item in its physical slot before sorting, with a configurable modifier and lock marker. |
| **Group preparation** | A compact Buff Check for party and raid coverage, including click-to-cast group buffs and explicit recipient choices for supported assignment spells. |
| **Adventure tools** | A Trusty Delve Companion curio helper, optional Valeera voice mute, and group-prep controls in one place. |
| **Saltheril's Soiree** | Pick a faction focus or follow the extra Favor reward. An EllesmereUI accent highlights the suggested guest and invitation button; hover the info badge to understand gains, losses, and the recommendation. |
| **Automation** | Individually enabled quest, dialogue, campaign-skip, cinematic, merchant, and Ethereal Tool Rack actions with safeguards for ambiguity and a hold-to-pause key. |
| **UI care** | A Waffle House header logo, an optional Zygor Guide Pointer skin, Wonderbar reordering, and a targeted repair for an obsolete Buff Frame anchor. |

## Install

Waffle House requires both **EllesmereUI** and **EllesmereUIVendorBag**. Install and enable those addons first.

1. Download a published Waffle House release, or download this repository as a ZIP for development testing.
2. Extract the addon so this folder exists:

   ```text
   World of Warcraft/_retail_/Interface/AddOns/WaffleHouse_EllesmereUI/
   ```

3. Confirm that `WaffleHouse_EllesmereUI.toc` is directly inside that folder. Do not leave an extra nested repository folder around it.
4. Launch WoW, enable **Waffle House** on the character-select AddOns screen, and reload if you installed it while logged in.

The manifest currently targets Retail interface versions **12.0.0, 12.0.1, and 12.0.5**. Optional integrations are detected when present: EllesmereUIBlizzardSkin, ZygorGuidesViewer, EllesmereUIDataBars, and EllesmereUIBags.

## Getting started

Open **EllesmereUI → Waffle House**. Its pages are organized by task: **General**, **Adventure**, **Automation**, **Bags**, **Item Queue**, and **Vendor**. Settings are stored in WoW SavedVariables and are intended to persist between sessions.

Three useful first stops:

1. **Vendor** — switch between the native-style grid and the detailed list, pin future purchases, and choose how currency information is shown.
2. **Bags** — hold the configured modifier over an item in OneBag's Main Bags, then click it to freeze or unfreeze that item before sorting.
3. **Adventure → Group Buff Check** — enable or preview the preparation panel, then place it by dragging its header.

In **Vendor → Interact Key**, choose **Manage** to expand the ignored-NPC table. Add a nearby vendor or enter an NPC ID and optional name. **Save** applies the draft; **Cancel** keeps the saved list unchanged. Names are remembered when available, and unknown IDs remain clearly labeled until you name them or encounter that NPC.

### Helpful commands

| Command | Result |
| --- | --- |
| `/whsoiree` | Choose or change your Soiree focus, remembered across characters. |
| `/whbuffs` | Show and enable Buff Check. |
| `/whbuffs off` | Disable Buff Check. |
| `/whbuffs preview` | Toggle a non-casting sample 40-player preview. |
| `/whbuffrepair` | Recheck and repair the specific legacy `PlayerBuffsMover` Buff Frame anchor when it is safe to do so. |
| `/whqueue` | Open diagnostics for the currently displayed Item Queue item; it also accepts a bag/slot, item ID, or item-name search. |

## Designed to stay in your hands

Automation is **off by default**. Every automated action is enabled separately, pauses while you hold the configured pause key (**Shift** by default), and avoids ambiguous choices. For example, it does not guess between quest rewards or competing service and dialogue options.

Other guardrails are intentional:

- Item Queue only presents a button; it does not consume items on its own.
- Buff Check can show missing coverage and configure secure clicks, but it does not select targets automatically or message the group.
- The vendor quantity flow hands the final purchase back to Blizzard's native merchant system, retaining its affordability checks and confirmations.
- Bag Slot Freeze records an explicit slot choice and keeps that item in place only when you use the bag sort flow.

## Current preview status

This repository is at **0.1.0-dev.1**, ahead of its first stable public release. The codebase includes focused local Lua regression harnesses, but this is not a substitute for live-client verification. No screenshots are included yet: the public visual gallery will follow in-game capture and review.

Two important current limits are documented explicitly:

- Native Buff Frame collapse/expand is deliberately left to Blizzard because addon-driven state changes can taint the Retail frame. Use Blizzard's control and Edit Mode for normal placement.
- The Buff Frame repair only addresses the obsolete `PlayerBuffsMover` saved anchor, skips uncertain layouts, and asks for `/reload` after a confirmed repair.

## Documentation

- [Vendor stack purchase behavior](VENDOR_STACK.md)
- [Buff Check behavior and limits](BUFF_CHECK.md)
- [Soiree focus and recommendation behavior](SOIREE_HELPER.md)
- [Buff Frame safety and anchor repair](BUFF_FRAME.md)
- [Quest-advance choice database policy](QUEST_ADVANCE_CHOICES.md)
- [Issue tracker](https://github.com/zero-wow/WaffleHouse_EllesmereUI/issues)

## Contributing feedback

Early reports are especially useful when they include your WoW client build, the enabled dependencies, the page or feature involved, the exact action that triggered the result, and any Lua error text. Please file those details in the [issue tracker](https://github.com/zero-wow/WaffleHouse_EllesmereUI/issues).

Waffle House is made for players who want their UI to do the tedious parts cleanly, visibly, and on their terms.
