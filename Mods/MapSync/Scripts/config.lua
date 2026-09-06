-- MapSync personal validation config
local Config = {
    ModName = "MapSync",
    Version = "0.1.0-poc",

    StatusRefreshMs = 2500,

    AutoProbeOnWorld = true,
    AutoProbeDelayMs = 4000,

    MaxUObjectScan = 25000,
    MaxCandidatesLogged = 200,

    ClassKeywords = {
        "minimap", "mini_map", "fogofwar", "fog_of_war", "mapreveal",
        "exploration", "explored", "zonemap", "worldmap", "cartograph",
        "mapmanager", "mapcomponent", "mapwidget", "mapfog", "revealed",
    },
    PropertyKeywords = {
        "reveal", "explored", "fog", "tile", "mask", "visited", "discover",
        "uncover", "visible", "exploration", "minimap",
    },
    FunctionKeywords = {
        "reveal", "explore", "unfog", "clearfog", "discover", "uncover",
        "setexplored", "addtile", "updatemap", "showtile", "paint",
    },

    SeedClassNames = {
        "MiniMapComponent", "MiniMapWidget", "MapComponent",
        "FogOfWar", "FogOfWarComponent", "ZoneMap", "ZoneMapManager",
        "WorldMap", "RemnantMap", "GunfireMap", "MapManager", "MapReveal",
        "ExplorationComponent", "TPSGameState",
        "Remnant_PlayerController_C", "Character_Master_Player_C",
    },

    Keys = {
        Dump = "F6",
        ProbeReveal = "F7",
        ToggleStatus = "F8",
        DumpNet = "F9",
    },

    -- Keep false until FoW viability = GO (visual confirmation on minimap).
    EnableLanSync = false,
    Lan = {
        Magic = "MS01",
        UdpPort = 27071,
        BroadcastPort = 27072,
        QueueDirName = "MapSyncQueue",
        PollMs = 500,
        HelloIntervalMs = 2000,
    },
}

return Config
