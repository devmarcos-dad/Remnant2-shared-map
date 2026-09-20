--[[
  Auto-start / stop for tools lan_bridge.exe (Windows).
  Ships under Mods/MapSync/Bin/lan_bridge.exe.
]]

local Config = require("config")
local Util = require("lib.util")

local Bridge = {
    ExePath = nil,
    StartedByUs = false,
    LastError = nil,
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

local function any_bridge_running()
    local pid = read_pid()
    if process_alive(pid) then return true, pid end
    local p = io.popen('tasklist /FI "IMAGENAME eq lan_bridge.exe" /NH 2>nul')
    if not p then return false, nil end
    local out = p:read("*a") or ""
    p:close()
    if string.find(Util.lower(out), "lan_bridge.exe", 1, true) then
        return true, nil
    end
    return false, nil
end

function Bridge.resolve_exe()
    if Bridge.ExePath and file_exists(Bridge.ExePath) then
        return Bridge.ExePath
    end

    local configured = Config.BridgeExePath
    local candidates = {}
    if configured and configured ~= "" then
        table.insert(candidates, configured)
    end

    -- Typical Remnant Win64 cwd: ...\Binaries\Win64
    table.insert(candidates, "ue4ss\\Mods\\MapSync\\Bin\\lan_bridge.exe")
    table.insert(candidates, "Mods\\MapSync\\Bin\\lan_bridge.exe")
    table.insert(candidates, "..\\ue4ss\\Mods\\MapSync\\Bin\\lan_bridge.exe")
    -- Dev / repo layout next to game (rare)
    table.insert(candidates, "tools\\lan_bridge\\lan_bridge.exe")

    for _, path in ipairs(candidates) do
        if file_exists(path) then
            Bridge.ExePath = path
            log("bridge exe=%s", path)
            return path
        end
    end

    Bridge.LastError = "lan_bridge.exe not found under Mods/MapSync/Bin"
    log("%s", Bridge.LastError)
    return nil
end

function Bridge.is_running()
    local running = any_bridge_running()
    return running
end

function Bridge.start()
    if Config.AutoStartBridge == false then
        return false, "AutoStartBridge=false"
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

    -- Hidden Start-Process so no console steals focus.
    local ps = string.format(
        "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process -FilePath '%s' -WindowStyle Hidden\"",
        exe:gsub("'", "''")
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
    log("bridge start requested exe=%s", exe)
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
        end)
    end

    pcall(function() os.remove(pid_path()) end)
    Bridge.StartedByUs = false
    return true, "stopped"
end

return Bridge
