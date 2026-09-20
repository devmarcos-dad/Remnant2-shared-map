-- MapSync config (Steam + bidirectional FoW sync 0.4.1-poc)
local Config = {
    ModName = "MapSync",
    Version = "0.4.1-poc",

    -- On-screen PrintString overlay (was causing screen spam / "popup tilt").
    -- Keep false for play; press F8 only when debugging.
    EnableOnScreenStatus = false,
    StatusRefreshMs = 5000,

    -- Optional override when NetMode stays Unknown: "Host" | "Client" | "Solo" | nil
    ForceLanRole = nil,

    -- Auto-manage lan_bridge.exe (shipped in Mods/MapSync/Bin/)
    AutoStartBridge = true,
    AutoKillBridgeOnExit = true,
    -- Optional absolute/relative override; nil = auto-detect under Mods/MapSync/Bin
    BridgeExePath = nil,

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
        -- Push local FoW + request peer to push theirs (both roles).
        ForceSync = "F10",
    },

    -- Test branch: queue sync on by default (bridge transport selected below).
    EnableLanSync = true,
    SyncFogEnabled = true,
    SyncTiles = true,
    MaxTilesPerPacket = 48,
    -- Host and client both emit TILES/POS when true (merge on receive).
    BidirectionalSync = true,
    SyncHostPositions = true,
    -- Shared POS trail interval for whoever is emitting (host and/or client).
    HostPositionIntervalMs = 1000,
    PositionIntervalMs = 1000,
    RevealRangeRadius = 1500,
    VerboseFoWLogs = true,

    -- Bridge transport: "lan" (UDP same-house) | "tcp" (WAN test) | "steam" (Steam P2P).
    -- Lua always uses the file queue; only the external bridge binary changes.
    -- AutoStartBridge currently launches lan_bridge.exe (Transport = "lan").
    Transport = "lan",

    Lan = {
        Magic = "MS01",
        UdpPort = 27071,
        BroadcastPort = 27072,
        QueueDirName = "MapSyncQueue",
        -- How often Lua polls inbox + emits map deltas (ms).
        PollMs = 1000,
        HelloIntervalMs = 5000,
    },

    -- Used by tools/steam_bridge (and documented for peer pairing).
    Steam = {
        AppId = 1282100, -- Remnant II
        -- 64-bit SteamID of the co-op partner. Leave "" to read steam_peer.txt from the queue dir.
        PeerId = "",
        Channel = 1,
        -- Optional TCP fallback when Steamworks SDK is not linked yet:
        -- steam_bridge -mode tcp -listen :27073   /   -mode tcp -dial host:27073
        TcpListen = ":27073",
        TcpDial = "",
    },
}

return Config
