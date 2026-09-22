# Vignette Radar

Vignette Radar is a compact, heading-up field for locations that Blizzard is
currently exposing as minimap vignettes. It does not scan for hidden objects,
maintain a rare database, or infer coordinates that the game has not supplied.

- Open **EllesmereUI > Waffle House > Adventure > Vignette Radar** to enable it,
  choose a 150, 300, 450, or 600 yard radius, preview the layout, show or hide
  the launcher, or reset both positions.
- The player stays at the center. Category-colored dots move around the field
  relative to the player's facing and distance.
- The header's legend button opens filters for rares, treasure, events, and
  other vignettes. Click a category row to spotlight it while retaining dim
  spatial context; use its ON/OFF control to remove that category entirely.
- The neighboring reticle button lists current detections by name and distance.
  Choose one to isolate it across both radar views, use **Show All** to clear
  the focus, or right-click the reticle for the same reset.
- Hover a live dot for the vignette name and approximate distance when those
  values are available from the game.
- By default the panel appears only while at least one usable minimap vignette
  is active. Disable **Hide When Empty** to keep the field visible.
- Drag the header to move the full panel. The separate 44-pixel launcher is
  also draggable. Disabled tracking uses a closed jeweled emblem; enabled
  tracking opens its center into a live 150-yard view with up to five current
  dots and a restrained sweep. Detections use a slow, two-percent bezel
  shimmer instead of flashing the face or drawing an outer halo. Left click it
  to show or tuck away the panel; right click it to toggle preview.
- `/whradar` shows or tucks away the panel, `/whradar preview` toggles sample
  layout mode, and `/whradar off` disables tracking while leaving the launcher
  available to turn it back on.

Coordinates are transformed through `C_Map.GetWorldPosFromMapPos`, so map
aspect ratio and yard distance are respected. Vignettes with unavailable,
protected, off-map, or cross-instance positions are skipped rather than placed
approximately. The feature never changes the minimap or its objects.

The launcher reuses the radar's existing vignette scan. It rescans at most once
per second while the main panel is closed, repositions up to five miniature
dots every 0.15 seconds, and caps its two-line decorative sweep at 30 updates
per second. It does not run a second location scan or duplicate the minimap.
