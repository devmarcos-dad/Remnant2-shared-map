--[[
  Auto-start / stop for MapSync bridges (Windows).
  - Transport=lan   → Mods/MapSync/Bin/lan_bridge.exe
  - Transport=steam → Mods/MapSync/Bin/steam_bridge.exe -mode steam
  - Transport=tcp   → no auto-start (needs -listen/-dial)
]]

local Config = require("config")
local Util = require("lib.util")

local Bridge = {
    ExePath = nil,
    StartedByUs = false,
    LastError = nil,
    Kind = nil, -- "lan" | "steam"
}

local TAG = "LAN"

local function log(fmt, ...)
    Util.flog(TAG, fmt, ...)
end

local function queue_dir()
    local name = (Config.Lan and Config.Lan.QueueDirName) or "MapSyncQueue"
    return Util.temp_queue_dir(name)
end

local function pid_path()
    return queue_dir() .. "\\bridge.pid"
end

local function file_exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local function read_pid()
    local data = Util.read_text_file(pid_path())
    if not data then return nil end
    local n = tonumber(string.match(data, "(%d+)"))
    return n
end

local function process_alive(pid)
    if not pid then return false end
    local cmd = string.format('tasklist /FI "PID eq %d" /NH 2>nul', pid)
    local p = io.popen(cmd)
    if not p then return false end
    local out = p:read("*a") or ""
    p:close()
    return string.find(out, tostring(pid), 1, true) ~= nil
end

local function transport()
    return Util.lower(tostring(Config.Transport or "lan"))
end

local function image_name()
    local t = transport()
    if t == "steam" then
        return "steam_bridge.exe"
    end
    return "lan_bridge.exe"
end

local function any_bridge_running()
    local pid = read_pid()
    if process_alive(pid) then return true, pid end
    local img = image_name()
    local p = io.popen(string.format('tasklist /FI "IMAGENAME eq %s" /NH 2>nul', img))
    if not p then return false, nil end
    local out = p:read("*a") or ""
    p:close()
    if string.find(Util.lower(out), Util.lower(img), 1, true) then
        return true, nil
    end
    return false, nil
end

function Bridge.resolve_exe()
    if Bridge.ExePath and file_exists(Bridge.ExePath) then
        return Bridge.ExePath
    end

    local t = transport()
    local exeName = (t == "steam") and "steam_bridge.exe" or "lan_bridge.exe"
    Bridge.Kind = (t == "steam") and "steam" or "lan"

    local configured = Config.BridgeExePath
    local candidates = {}
    if configured and configured ~= "" then
        table.insert(candidates, configured)
    end

    -- Typical Remnant Win64 cwd: ...\Binaries\Win64
    table.insert(candidates, "ue4ss\\Mods\\MapSync\\Bin\\" .. exeName)
    table.insert(candidates, "Mods\\MapSync\\Bin\\" .. exeName)
    table.insert(candidates, "..\\ue4ss\\Mods\\MapSync\\Bin\\" .. exeName)
    if t == "steam" then
        table.insert(candidates, "tools\\steam_bridge\\steam_bridge.exe")
    else
        table.insert(candidates, "tools\\lan_bridge\\lan_bridge.exe")
    end

    for _, path in ipairs(candidates) do
        if file_exists(path) then
            Bridge.ExePath = path
            log("bridge exe=%s transport=%s", path, t)
            return path
        end
    end

    Bridge.LastError = exeName .. " not found under Mods/MapSync/Bin"
    log("%s", Bridge.LastError)
    return nil
end

function Bridge.is_running()
    return any_bridge_running()
end

local function start_args()
    local t = transport()
    if t == "steam" then
        local args = { "-mode", "steam" }
        local peer = Config.Steam and Config.Steam.PeerId
        if peer and tostring(peer) ~= "" then
            table.insert(args, "-peer")
            table.insert(args, tostring(peer))
        end
        local app = Config.Steam and Config.Steam.AppId
        if app then
            table.insert(args, "-appid")
            table.insert(args, tostring(app))
        end
        return args
    end
    return {}
end

function Bridge.start()
    if Config.AutoStartBridge == false then
        return false, "AutoStartBridge=false"
    end

    local t = transport()
    if t == "tcp" then
        log("skip auto-start (Transport=tcp — use steam_bridge -mode tcp manually)")
        return false, "transport-tcp"
    end
    if t ~= "lan" and t ~= "steam" then
        log("skip auto-start (Transport=%s)", t)
        return false, "transport-unsupported"
    end

    local running, pid = any_bridge_running()
    if running then
        log("bridge already running pid=%s", tostring(pid or "?"))
        return true, "already-running"
    end

    local exe = Bridge.resolve_exe()
    if not exe then
        return false, Bridge.LastError
    end

    Util.ensure_dir(queue_dir())

    local args = start_args()
    local argLit = ""
    if #args > 0 then
        local quoted = {}
        for _, a in ipairs(args) do
            table.insert(quoted, string.format("'%s'", tostring(a):gsub("'", "''")))
        end
        argLit = " -ArgumentList " .. table.concat(quoted, ",")
    end

    -- WorkingDirectory = game Win64 so steam_api64.dll resolves for -mode steam.
    local ps = string.format(
        "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process -FilePath '%s'%s -WorkingDirectory (Get-Location).Path -WindowStyle Hidden\"",
        exe:gsub("'", "''"),
        argLit
    )
    local ok, err = pcall(function()
        os.execute(ps)
    end)
    if not ok then
        Bridge.LastError = tostring(err)
        log("bridge start failed: %s", tostring(err))
        return false, Bridge.LastError
    end

    Bridge.StartedByUs = true
    log("bridge start requested exe=%s transport=%s", exe, t)
    return true, "started"
end

function Bridge.stop()
    if Config.AutoKillBridgeOnExit == false then
        return false, "AutoKillBridgeOnExit=false"
    end

    local pid = read_pid()
    if pid and process_alive(pid) then
        log("killing bridge pid=%d", pid)
        pcall(function()
            os.execute(string.format('taskkill /PID %d /F >nul 2>nul', pid))
        end)
    else
        log("%s", "killing bridge by image name")
        pcall(function()
            os.execute('taskkill /IM lan_bridge.exe /F >nul 2>nul')
            os.execute('taskkill /IM steam_bridge.exe /F >nul 2>nul')
        end)
    end

    pcall(function() os.remove(pid_path()) end)
    Bridge.StartedByUs = false
    return true, "stopped"
end

return Bridge
