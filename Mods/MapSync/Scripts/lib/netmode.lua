local Util = require("lib.util")
local Config = require("config")

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

local function normalize_mode(mode)
    if mode == nil then return nil end
    if type(mode) == "number" then
        return BY_CODE[mode]
    end
    local s = tostring(mode)
    if BY_CODE[tonumber(s)] then return BY_CODE[tonumber(s)] end
    local lower = Util.lower(s)
    if string.find(lower, "listen", 1, true) then return Names.ListenServer end
    if string.find(lower, "dedicated", 1, true) then return Names.DedicatedServer end
    if string.find(lower, "client", 1, true) then return Names.Client end
    if string.find(lower, "standalone", 1, true) then return Names.Standalone end
    return nil
end

local function detect_via_authority()
    local pcs = nil
    pcall(function() pcs = FindAllOf("PlayerController") end)
    if not pcs then
        local one = FindFirstOf("PlayerController")
        if Util.is_valid(one) then pcs = { one } end
    end
    if not pcs then return nil end

    for _, pc in pairs(pcs) do
        if Util.is_valid(pc) then
            local local_ok = false
            pcall(function()
                local_ok = pc.Pawn ~= nil and pc.Pawn:IsValid()
            end)
            if local_ok then
                local auth = nil
                pcall(function()
                    if pc.HasAuthority ~= nil then
                        auth = pc:HasAuthority()
                    end
                end)
                if auth == true then return Names.ListenServer end
                if auth == false then return Names.Client end
            end
        end
    end
    return nil
end

function NetMode.detect()
    if Config.ForceLanRole == "Host" then return Names.ListenServer end
    if Config.ForceLanRole == "Client" then return Names.Client end
    if Config.ForceLanRole == "Solo" then return Names.Standalone end

    local world = NetMode.get_world()
    if Util.is_valid(world) then
        local ok, mode = pcall(function()
            if world.GetNetMode ~= nil then return world:GetNetMode() end
            return world.NetMode
        end)
        if ok then
            local normalized = normalize_mode(mode)
            if normalized then return normalized end
        end
    end

    local via_auth = detect_via_authority()
    if via_auth then return via_auth end
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
