-- MapSync config (LAN Phase 2)
local Config = {
    ModName = "MapSync",
    Version = "0.2.0-poc",

    StatusRefreshMs = 2500,

    AutoProbeOnWorld = false,
    AutoProbeDelayMs = 5000,

    MaxUObjectScan = 25000,
    MaxCandidatesLogged = 120,

    ProbeDumpOnF7 = false,
    FogOffHoldMs = 3000,

    PriorityClassNames = {
        "ExplorableMinimapManager",
        "ExplorableMinimapModelRemnant",
        "ExplorableMinimapModel",
        "ExplorableMinimapComponent",
        "MinimapTileSupport",
        "RemnantPlayerController",
        "Remnant_PlayerController_C",
        "RemnantCheatManager",
    },

    ClassKeywords = {
        "explorableminimap", "minimap", "mini_map", "fogofwar", "fog_of_war",
        "mapreveal", "visitedcoordinates", "exploration", "explored",
    },
    PropertyKeywords = {
        "reveal", "explored", "fog", "tile", "mask", "visited", "discover",
        "coordinates", "visibility", "minimap",
    },
    FunctionKeywords = {
        "reveal", "explore", "unfog", "clearfog", "discover",
        "enablefog", "togglefog", "updatefog", "visib",
    },

    RejectClassNames = {
        "Function", "DelegateFunction", "Class", "Package", "Enum",
        "ScriptStruct", "MetaData", "PackageMap",
    },

    Keys = {
        Dump = "F6",
        ProbeReveal = "F7",
        ToggleStatus = "F8",
        DumpNet = "F9",
    },

    -- Phase 2: set true on BOTH PCs after FoW GO, then run lan_bridge on both.
    EnableLanSync = false,
    SyncFogEnabled = true,
    SyncTiles = true,
    MaxTilesPerPacket = 48,

    Lan = {
        Magic = "MS01",
        UdpPort = 27071,
        BroadcastPort = 27072,
        QueueDirName = "MapSyncQueue",
        PollMs = 750,
        HelloIntervalMs = 2000,
    },
}

return Config
