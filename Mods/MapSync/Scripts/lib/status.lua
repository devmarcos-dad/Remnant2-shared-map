local Util = require("lib.util")

local Status = {
    State = "Boot",
    Detail = "loading",
    Visible = true,
    FoWViable = false,
    CandidateCount = 0,
    RevealAttempts = 0,
    RevealSuccesses = 0,
    NetMode = "Unknown",
    Lan = "Off",
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

function Status.set(state, detail)
    Status.State = state or Status.State
    if detail ~= nil then Status.Detail = detail end
    Util.log("status=%s detail=%s", Status.State, tostring(Status.Detail))
end

function Status.toggle()
    Status.Visible = not Status.Visible
    Util.log("on-screen status %s", Status.Visible and "ON" or "OFF")
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
    local msg = Status.line()
    local color = COLORS[Status.State] or COLORS.Boot
    local kismet = get_kismet()
    if kismet then
        pcall(function()
            kismet:PrintString(nil, msg, true, true, color, duration_seconds or 2.5)
        end)
    end
end

function Status.start_refresh_loop(interval_ms)
    if interval_ms == nil or interval_ms <= 0 then return end
    if LoopAsync == nil then
        Util.log("%s", "LoopAsync unavailable; status refresh loop disabled")
        return
    end
    LoopAsync(interval_ms, function()
        Status.print_screen(interval_ms / 1000.0 + 0.25)
        return false
    end)
end

return Status
