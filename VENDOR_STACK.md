# Vendor stack purchases

In the Ellesmere vendor grid or list, **Shift-right-click** an item to open
Blizzard's quantity picker. EllesmereUI's existing Stack Split skin styles
that popup. Type a quantity or use its arrows, then confirm; opening or
cancelling it does not buy anything. You can choose up to the native merchant
stack limit, subject to affordability. Items sold in bundles use the native
bundle increments and total-item display.

Ordinary clicks, Shift-left-click linking, and Ctrl-click previews keep their
existing behavior. Buyback entries do not open the purchase picker.

The addon preserves Blizzard's extended-cost and nonrefundable confirmations.
It rechecks the item and quantity before handing the purchase to Blizzard.
Closing/updating the merchant or recycling the vendor row cancels the pending
picker. The picker uses Blizzard's gold and item-token affordability rules;
named currency limits and inventory constraints still receive native/server
validation when buying. There is no buy-all or repeated-purchase loop.

Local tests cover the click route, maximum and smaller quantities, bundle
rounding, confirmation dispatch, changed offers, cancellation and stale rows.
Client interaction and appearance still require in-game verification.

Native reference: [12.0.5 merchant quantity flow](https://github.com/Gethe/wow-ui-source/blob/12.0.5/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua).
