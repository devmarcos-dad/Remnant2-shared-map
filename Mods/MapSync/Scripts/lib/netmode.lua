local Util = require("lib.util")

local Names = {
    Unknown = "Unknown",
    Standalone = "Standalone",
    DedicatedServer = "DedicatedServer",
    ListenServer = "ListenServer",
    Client = "Client",
}

local BY_CODE = {
    [0] = Names.Standalone,
    [1] = Names.DedicatedServer,
    [2] = Names.ListenServer,
    [3] = Names.Client,
}

local NetMode = { Names = Names }

function NetMode.get_world()
    local world = FindFirstOf("World")
    if Util.is_valid(world) then return world end

    local engine = FindFirstOf("GameEngine")
    if Util.is_valid(engine) then
        local ok, w = pcall(function()
            return engine.GameViewport and engine.GameViewport.World
        end)
        if ok and Util.is_valid(w) then return w end
    end

    local pc = FindFirstOf("PlayerController")
    if Util.is_valid(pc) then
        local ok, w = pcall(function() return pc:GetWorld() end)
        if ok and Util.is_valid(w) then return w end
    end
    return nil
end

function NetMode.detect()
    local world = NetMode.get_world()
    if not Util.is_valid(world) then return Names.Unknown end
    local ok, mode = pcall(function()
        if world.GetNetMode ~= nil then return world:GetNetMode() end
        return world.NetMode
    end)
    if ok and mode ~= nil then return BY_CODE[mode] or tostring(mode) end
    return Names.Unknown
end

function NetMode.is_multiplayer(mode)
    return mode == Names.ListenServer
        or mode == Names.Client
        or mode == Names.DedicatedServer
end

function NetMode.role_label(mode)
    if mode == Names.ListenServer or mode == Names.DedicatedServer then return "Host" end
    if mode == Names.Client then return "Client" end
    if mode == Names.Standalone then return "Solo" end
    return "Unknown"
end

return NetMode
