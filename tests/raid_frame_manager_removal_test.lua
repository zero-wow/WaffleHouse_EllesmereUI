local sourcePath = "WaffleHouse_Adventure.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = assert(file:read("*a"))
file:close()

for _, forbidden in ipairs({
    "CompactRaidFrameManager",
    "RefreshRaidFrameManager",
    "Raid Frame Manager Visibility",
    "raidFrameManagerVisibility",
    "raidFrameManagerPosition",
    "raidFrameManagerGroupFrameRestoreStates",
}) do
    assert(not source:find(forbidden, 1, true), "raid-manager integration remains: " .. forbidden)
end

io.write("raid_frame_manager_removal_test: ok\n")
