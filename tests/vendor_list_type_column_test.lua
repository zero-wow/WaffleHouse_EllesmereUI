-- Static regression checks for the list-only vendor Type column and its
-- direct header-drag reorder behavior.  Runtime layout is covered by the
-- vendor tracking tests; these checks keep this presentation feature wired.

local SOURCE = arg[1] or "WaffleHouse_EllesmereUI.lua"
local file = assert(io.open(SOURCE, "r"))
local source = file:read("*a")
file:close()

local function expect(fragment, message)
    assert(source:find(fragment, 1, true), message)
end

expect('addon.VendorListColumnDefault = { "icon", "pin", "item", "type", "rarity", "cost" }',
    "default list columns must place Type and Rarity between Item and Cost")
expect('type = "TYPE"', "list header must expose the Type column")
expect('rarity = "RARITY"', "list header must expose a separate Rarity column")
expect('text = "Show Rarity Column"', "Vendor options must expose Rarity column visibility")
expect('pin = "",', "the shopping-list column must not use an ambiguous PIN label")
expect('control.shoppingListIconParts = {}', "the shopping-list column needs a checklist header icon")
expect('Shopping List — pin or unpin this vendor item.', "the shopping-list header needs explanatory hover text")
expect('function addon.GetVendorListItemType(button)', "list items must derive a readable type")
expect('if subclassID == 1 then return "Potion" end', "potions need a compact type label")
expect('if subclassID == 5 then return "Food" end', "food needs a compact type label")
expect('control:SetScript("OnMouseDown", function(self, mouseButton)',
    "headers need a direct mouse-down path")
expect('addon.BeginVendorListHeaderPress(header, self)',
    "a short header press must be distinguished from an intentional reorder drag")
expect('addon.ToggleVendorListSort(control._waffleListColumnKey)',
    "short header clicks must toggle ascending and descending row sorting")
expect('addon.VendorListDragHoldSeconds = 0.25',
    "column reordering must require a 0.25-second held press")
expect('header:SetScript("OnUpdate", addon.UpdateVendorListHeaderDrag)',
    "held header presses need release detection even when mouse-up lands outside the title")
expect('header:SetFrameLevel((frame.ScrollChild:GetFrameLevel() or 0) + 20)',
    "headers must sit above pooled vendor-row click frames")
expect('header._waffleListDropGuide', "header drags must expose a visible EUI-native drop guide")
expect('addon.MoveVendorListColumn(columnKey, fullDrop)', "header drops must persist the reordered columns")
expect('typeLabel:SetShown(typeColumn ~= nil)', "narrow list layouts must safely collapse Type without overlap")
expect('rarityLabel:SetShown(rarityColumn ~= nil)', "Rarity cells must follow the column visibility setting")
expect('function addon.ApplyVendorListEmptyState(frame, isEmpty)',
    "list view must own the native empty-state placement")
expect('label:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 16, -(LIST_HEADER_H + 12))',
    "empty-state copy must start below the list header")

expect('panel.list:SetPoint("RIGHT", panel.saved, "LEFT", -3, 0)',
    "the live list-view checkbox must sit with the other vendor header controls")
expect('settings.vendorItemView = settings.vendorItemView == "list" and "grid" or "list"',
    "the live list-view checkbox must toggle the same saved setting as the configuration page")
expect('function addon.UpdateVendorListViewControl(legend)',
    "the live list-view checkbox must visibly track external configuration changes")
expect('addon.CreatePanelActionIcon(panel.plan, "plan")',
    "the shopping-list action must use a pin icon instead of checkbox-shaped whitespace")
expect('addon.CreatePanelActionIcon(panel.mode, "mode")',
    "the currency text action must use a text-mode icon instead of checkbox-shaped whitespace")
assert(not source:find('panel.clear = CreateFrame("Button", nil, panel)', 1, true),
    "the redundant clear action must not take space in the Currencies header")
expect('header.resizeControls = {}',
    "list headers need dedicated resize hit areas")
expect('divider:SetSize(8, LIST_HEADER_H)',
    "column resize hit areas need a forgiving header-only target")
expect('divider.line:SetShown(header._waffleListResizeDivider == divider)',
    "column divider line must remain hidden until an intentional held drag")
expect('function addon.BeginVendorListHeaderResizePress(header, divider)',
    "column resize must wait for the same held-drag threshold")
expect('function addon.BeginVendorListHeaderResize(header, divider)',
    "header dividers must start a bounded two-column resize")
expect('settings.vendorListColumnWidths[resize.leftKey] = leftWidth',
    "column resize must persist the left width")
expect('settings.vendorListColumnWidths[resize.rightKey] = rightWidth',
    "column resize must persist the right width")

io.write("vendor list type column tests passed\n")
