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
- Hover a live dot for the vignette name and approximate distance when those
  values are available from the game.
- By default the panel appears only while at least one usable minimap vignette
  is active. Disable **Hide When Empty** to keep the field visible.
- Drag the header to move the full panel. The separate circular launcher is
  also draggable, mirrors up to three current dots, animates its sweep and
  detection pulse, and has distinct hover, pressed, and click feedback. Left
  click it to show or tuck away the panel; right click it to toggle preview.
- `/whradar` shows or tucks away the panel, `/whradar preview` toggles sample
  layout mode, and `/whradar off` disables tracking while leaving the launcher
  available to turn it back on.

Coordinates are transformed through `C_Map.GetWorldPosFromMapPos`, so map
aspect ratio and yard distance are respected. Vignettes with unavailable,
protected, off-map, or cross-instance positions are skipped rather than placed
approximately. The feature never changes the minimap or its objects.
