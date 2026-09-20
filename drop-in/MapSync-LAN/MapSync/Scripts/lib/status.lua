local Util = require("lib.util")
local Config = require("config")

local Status = {
    State = "Boot",
    Detail = "loading",
    -- Off by default: PrintString refresh was flashing the screen every ~2.5s.
    Visible = false,
    FoWViable = false,
    CandidateCount = 0,
    RevealAttempts = 0,
    RevealSuccesses = 0,
    NetMode = "Unknown",
    Lan = "Off",
    _refresh_started = false,
}

local COLORS = {
    Boot = { R = 0.75, G = 0.75, B = 0.75, A = 1.0 },
    Probing = { R = 1.0, G = 0.85, B = 0.2, A = 1.0 },
    ["FoW OK"] = { R = 0.2, G = 1.0, B = 0.4, A = 1.0 },
    ["FoW FAIL"] = { R = 1.0, G = 0.25, B = 0.25, A = 1.0 },
    Searching = { R = 0.4, G = 0.8, B = 1.0, A = 1.0 },
    Connected = { R = 0.3, G = 1.0, B = 0.7, A = 1.0 },
    Syncing = { R = 0.6, G = 0.9, B = 1.0, A = 1.0 },
    Offline = { R = 0.7, G = 0.7, B = 0.7, A = 1.0 },
    World = { R = 0.7, G = 0.9, B = 1.0, A = 1.0 },
}

function Status.set(state, detail, opts)
    opts = opts or {}
    local next_state = state or Status.State
    local next_detail = detail
    if next_detail == nil then next_detail = Status.Detail end

    local changed = (next_state ~= Status.State) or (tostring(next_detail) ~= tostring(Status.Detail))
    Status.State = next_state
    Status.Detail = next_detail

    -- Avoid flooding UE4SS.log / console on repeated HELLO/status ticks.
    if changed or opts.force_log then
        Util.log("status=%s detail=%s", Status.State, tostring(Status.Detail))
    end

    if opts.print then
        Status.print_screen(opts.duration or 2.0)
    end
end

function Status.toggle()
    Status.Visible = not Status.Visible
    Util.log("on-screen status %s", Status.Visible and "ON" or "OFF")
    if Status.Visible then
        Status.print_screen(3.0)
    end
end

function Status.line()
    return string.format(
        "[MapSync: %s] %s | candidates=%d reveal=%d/%d net=%s lan=%s",
        Status.State, Status.Detail or "",
        Status.CandidateCount or 0,
        Status.RevealSuccesses or 0,
        Status.RevealAttempts or 0,
        tostring(Status.NetMode),
        tostring(Status.Lan)
    )
end

local function get_kismet()
    local ok, obj = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    end)
    if ok and Util.is_valid(obj) then return obj end
    return nil
end

function Status.print_screen(duration_seconds)
    if not Status.Visible then return end
    if Config.EnableOnScreenStatus == false then return end
    local msg = Status.line()
    local color = COLORS[Status.State] or COLORS.Boot
    local kismet = get_kismet()
    if not kismet then return end
    -- Print to screen only (not log). Keep duration short to avoid stacked spam.
    local dur = math.min(tonumber(duration_seconds) or 1.5, 2.0)
    pcall(function()
        kismet:PrintString(nil, msg, true, false, color, dur)
    end)
end

function Status.start_refresh_loop(interval_ms)
    if Status._refresh_started then return end
    if Config.EnableOnScreenStatus == false then
        Util.log("%s", "on-screen status disabled (F8 to toggle if enabled in config)")
        return
    end
    if interval_ms == nil or interval_ms <= 0 then return end
    if LoopAsync == nil then
        Util.log("%s", "LoopAsync unavailable; status refresh loop disabled")
        return
    end
    Status._refresh_started = true
    -- Only refresh while Visible; default Visible=false so this is idle.
    LoopAsync(interval_ms, function()
        if Status.Visible then
            Status.print_screen(math.min(interval_ms / 1000.0, 1.5))
        end
        return false
    end)
end

return Status
