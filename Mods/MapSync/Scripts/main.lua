local Config = require("config")
local Util = require("lib.util")
local Status = require("lib.status")
local NetMode = require("lib.netmode")
local FoW = require("fow")
local Lan = require("net.lan")
local Probe = require("probe")

Util.log("%s %s loading", Config.ModName, Config.Version)
Status.set("Boot", Config.Version)
Status.start_refresh_loop(Config.StatusRefreshMs)

local function refresh_net_status()
    local mode = NetMode.detect()
    Status.NetMode = mode
    return mode
end

local function run_probe()
    refresh_net_status()
    local ok = FoW.run_viability_probe()
    if ok and FoW.is_ready_for_lan() then
        Lan.start()
    elseif ok then
        Util.log("%s", "FoW GO — confirm tiles visually, then set EnableLanSync=true in config.lua")
    end
    return ok
end

local function bind_key(name, callback)
    local key = Util.resolve_key(name)
    if key == nil then
        Util.log("unknown key %s", tostring(name))
        return
    end
    if RegisterKeyBind == nil then
        Util.log("%s", "RegisterKeyBind unavailable")
        return
    end
    pcall(function()
        RegisterKeyBind(key, callback)
    end)
end

bind_key(Config.Keys.Dump, function()
    Util.log("%s", "F6: reflection dump")
    local candidates = Probe.run_dump()
    Status.CandidateCount = #candidates
    Status.set("Probing", string.format("dump=%d", #candidates))
    Status.print_screen(3.0)
end)

bind_key(Config.Keys.ProbeReveal, function()
    Util.log("%s", "F7: viability probe")
    run_probe()
end)

bind_key(Config.Keys.ToggleStatus, function()
    Status.toggle()
    Status.print_screen(2.0)
end)

bind_key(Config.Keys.DumpNet, function()
    local mode = refresh_net_status()
    Util.log("netmode=%s role=%s", mode, NetMode.role_label(mode))
    Lan.debug_dump()
    Status.print_screen(3.0)
end)

if Config.AutoProbeOnWorld then
    local delay = Config.AutoProbeDelayMs or 4000
    if ExecuteWithDelay ~= nil then
        ExecuteWithDelay(delay, function()
            refresh_net_status()
            Status.set("Probing", "auto")
            run_probe()
        end)
    elseif LoopAsync ~= nil then
        local fired = false
        LoopAsync(delay, function()
            if fired then return true end
            fired = true
            refresh_net_status()
            Status.set("Probing", "auto")
            run_probe()
            return true
        end)
    else
        Util.log("%s", "No delay API; press F7 in-world to probe")
    end
end

Util.log("%s", "Ready. F6=dump F7=probe F8=status F9=net")
