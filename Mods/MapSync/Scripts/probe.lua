local Util = require("lib.util")
local Config = require("config")

local Probe = {
    LastCandidates = {},
    LastDumpPath = nil,
}

local function score_text(text, keywords)
    local score = 0
    local lower = Util.lower(text)
    for _, kw in ipairs(keywords or {}) do
        if string.find(lower, Util.lower(kw), 1, true) then
            score = score + 1
        end
    end
    return score
end

local function is_rejected_class(class_name)
    local lower = Util.lower(class_name)
    for _, bad in ipairs(Config.RejectClassNames or {}) do
        if lower == Util.lower(bad) then
            return true
        end
    end
    return false
end

local function is_live_instance(obj, full_name, class_name)
    if not Util.is_valid(obj) then return false end
    if is_rejected_class(class_name) then return false end
    local full = Util.lower(full_name or "")
    if string.find(full, "default__", 1, true) then return false end
    if string.find(full, "function ", 1, true) or string.find(full, " class ", 1, true) then
        return false
    end
    if string.find(full, "/script/", 1, true)
        and not string.find(full, "persistentlevel", 1, true)
        and not string.find(full, "transient", 1, true) then
        if class_name == "Class" or class_name == "Function" then
            return false
        end
    end
    return true
end

local function collect_reflection(obj)
    local props = {}
    local funcs = {}

    pcall(function()
        if obj.ForEachProperty == nil then return end
        obj:ForEachProperty(function(prop)
            local name = nil
            pcall(function() name = prop:GetFName():ToString() end)
            if name and score_text(name, Config.PropertyKeywords) > 0 then
                table.insert(props, { name = name, score = score_text(name, Config.PropertyKeywords) })
            end
        end)
    end)

    pcall(function()
        if obj.ForEachFunction == nil then return end
        obj:ForEachFunction(function(fn)
            local name = nil
            pcall(function() name = fn:GetFName():ToString() end)
            if name and score_text(name, Config.FunctionKeywords) > 0 then
                table.insert(funcs, { name = name, score = score_text(name, Config.FunctionKeywords) })
            end
        end)
    end)

    if #props == 0 then
        for _, pname in ipairs({
            "ExplorableMinimapModel", "VisitedCoordinatesOwner", "VisitedCoordinatesMap",
            "RevealRange", "RevealRangeZ", "RevealedHiddenAreasIDs",
        }) do
            local ok, value = pcall(function() return obj[pname] end)
            if ok and value ~= nil then
                table.insert(props, { name = pname, score = 3, preview = Util.ue_type(value) })
            end
        end
    end

    if #funcs == 0 then
        for _, fname in ipairs({
            "EnableFogOfWar", "IsFogOfWarEnabled", "GetExplorableMinimapModel",
            "RevealHiddenArea", "ToggleFogOfWar", "ClientUpdateFogOfWar",
        }) do
            local ok, value = pcall(function() return obj[fname] end)
            if ok and value ~= nil then
                table.insert(funcs, { name = fname, score = 3 })
            end
        end
    end

    return props, funcs
end

local function format_candidate(c)
    local lines = {
        string.format("score=%d class=%s", c.score or 0, c.class_name or "?"),
        string.format("name=%s", c.full_name or "?"),
    }
    if c.props and #c.props > 0 then
        local names = {}
        for i, p in ipairs(c.props) do
            if i > 8 then break end
            table.insert(names, p.name)
        end
        table.insert(lines, "props=" .. table.concat(names, ","))
    end
    if c.funcs and #c.funcs > 0 then
        local names = {}
        for i, f in ipairs(c.funcs) do
            if i > 8 then break end
            table.insert(names, f.name)
        end
        table.insert(lines, "funcs=" .. table.concat(names, ","))
    end
    return table.concat(lines, "\n") .. "\n\n"
end

local function consider(obj, bucket)
    if not Util.is_valid(obj) then return end
    local full = Util.safe_name(obj)
    local class_name = Util.safe_class_name(obj)
    if not is_live_instance(obj, full, class_name) then return end
    if bucket._seen[full] then return end
    bucket._seen[full] = true

    local cscore = score_text(class_name .. " " .. full, Config.ClassKeywords)
    for _, name in ipairs(Config.PriorityClassNames or {}) do
        if string.find(Util.lower(class_name .. " " .. full), Util.lower(name), 1, true) then
            cscore = cscore + 5
        end
    end
    if cscore <= 0 then return end

    local props, funcs = collect_reflection(obj)
    table.insert(bucket, {
        score = cscore + #props + #funcs,
        class_name = class_name,
        full_name = full,
        props = props,
        funcs = funcs,
    })
end

local function dump_priority_classes(bucket)
    for _, class_name in ipairs(Config.PriorityClassNames or {}) do
        local ok, all = pcall(function() return FindAllOf(class_name) end)
        local count = 0
        if ok and all then
            for _, obj in pairs(all) do
                consider(obj, bucket)
                count = count + 1
            end
            Util.log("priority FindAllOf(%s) => %d", class_name, count)
        else
            local one = nil
            pcall(function() one = FindFirstOf(class_name) end)
            if Util.is_valid(one) then
                consider(one, bucket)
                Util.log("priority FindFirstOf(%s) => 1", class_name)
            else
                Util.log("priority miss %s", class_name)
            end
        end
    end
end

local function dump_uobject_scan(bucket)
    if ForEachUObject == nil then
        Util.log("%s", "ForEachUObject unavailable; skipping full scan")
        return
    end
    local max_scan = Config.MaxUObjectScan or 25000
    local scanned = 0
    pcall(function()
        ForEachUObject(function(obj)
            scanned = scanned + 1
            if scanned > max_scan then return false end
            consider(obj, bucket)
            return true
        end)
    end)
    Util.log("uobject scan counted=%d candidates=%d", scanned, #bucket)
end

function Probe.run_dump()
    Util.log("%s", "=== FoW reflection dump start ===")
    local bucket = { _seen = {} }
    dump_priority_classes(bucket)
    dump_uobject_scan(bucket)
    bucket._seen = nil

    table.sort(bucket, function(a, b)
        if a.score == b.score then return tostring(a.full_name) < tostring(b.full_name) end
        return a.score > b.score
    end)

    local max_log = Config.MaxCandidatesLogged or 120
    local lines = {
        string.format("# MapSync FoW dump %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ")),
        string.format("# candidates=%d\n\n", #bucket),
    }
    for i, c in ipairs(bucket) do
        if i > max_log then break end
        local block = format_candidate(c)
        table.insert(lines, block)
        Util.log("[%d] %s", i, (block:gsub("\n", " | ")))
    end

    local dir = Util.temp_queue_dir("MapSyncLogs")
    local path = string.format("%s\\fow_dump_%s.txt", dir, os.date("%Y%m%d_%H%M%S"))
    local ok, err = Util.write_text_file(path, table.concat(lines))
    if ok then
        Probe.LastDumpPath = path
        Util.log("dump written to %s", path)
    else
        Util.log("failed to write dump: %s", tostring(err))
    end

    Probe.LastCandidates = bucket
    Util.log("%s", "=== FoW reflection dump end ===")
    return bucket
end

return Probe
