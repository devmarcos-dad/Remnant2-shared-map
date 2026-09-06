-- MapSync personal validation config
local Config = {
    ModName = "MapSync",
    Version = "0.1.2-poc",

    StatusRefreshMs = 2500,

    -- Off: old auto-probe ran the heavy dump and froze the game.
    AutoProbeOnWorld = false,
    AutoProbeDelayMs = 5000,

    MaxUObjectScan = 25000,
    MaxCandidatesLogged = 120,

    -- F7 must stay light. Full UObject dump is F6 only.
    ProbeDumpOnF7 = false,

    -- Leave fog disabled this long so the minimap change is obvious.
    FogOffHoldMs = 3000,

    -- Prefer live Remnant / Gunfire minimap instances first.
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

    -- Meta UObject kinds we must never bind/call as gameplay instances.
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
