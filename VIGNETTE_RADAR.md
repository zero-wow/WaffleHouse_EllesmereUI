# Vignette Radar

Vignette Radar is a compact, heading-up field for locations that Blizzard is
currently exposing as minimap vignettes. It does not scan for hidden objects,
maintain a rare database, or infer coordinates that the game has not supplied.

- Open **EllesmereUI > Waffle House > Adventure > Vignette Radar** to enable it,
  choose a 150, 300, 450, or 600 yard radius, preview the layout, or reset its
  position.
- The player stays at the center. Red dots move around the field relative to
  the player's facing and distance.
- Hover a live dot for the vignette name and approximate distance when those
  values are available from the game.
- By default the panel appears only while at least one usable minimap vignette
  is active. Disable **Hide When Empty** to keep the field visible.
- Drag the header to move it. `/whradar` toggles the panel, `/whradar preview`
  toggles sample layout mode, and `/whradar off` disables it.

Coordinates are transformed through `C_Map.GetWorldPosFromMapPos`, so map
aspect ratio and yard distance are respected. Vignettes with unavailable,
protected, off-map, or cross-instance positions are skipped rather than placed
approximately. The feature never changes the minimap or its objects.
