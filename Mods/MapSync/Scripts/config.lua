-- MapSync config (LAN FoW sync 0.3.2-poc)
local Config = {
    ModName = "MapSync",
    Version = "0.3.2-poc",

    -- On-screen PrintString overlay (was causing screen spam / "popup tilt").
    -- Keep false for play; press F8 only when debugging.
    EnableOnScreenStatus = false,
    StatusRefreshMs = 5000,

    -- Optional override when NetMode stays Unknown: "Host" | "Client" | "Solo" | nil
    ForceLanRole = nil,

    AutoProbeOnWorld = false,
    AutoProbeDelayMs = 5000,
    -- Delay after ClientRestart before rebinding FoW (zone / overworld transition).
    WorldRebindDelayMs = 2500,

    MaxUObjectScan = 25000,
    MaxCandidatesLogged = 120,

    ProbeDumpOnF7 = false,
    FogOffHoldMs = 3000,

    -- Remnant / Gunfire live class names (Phase 1 GO)
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

    -- Test branch: LAN on by default.
    EnableLanSync = true,
    SyncFogEnabled = true,
    SyncTiles = true,
    MaxTilesPerPacket = 48,
    SyncHostPositions = true,
    HostPositionIntervalMs = 1000,
    RevealRangeRadius = 1500,
    VerboseFoWLogs = true,

    Lan = {
        Magic = "MS01",
        UdpPort = 27071,
        BroadcastPort = 27072,
        QueueDirName = "MapSyncQueue",
        PollMs = 1000,
        HelloIntervalMs = 5000,
    },
}

return Config
