local Util = {}

function Util.log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    print(string.format("[MapSync] %s\n", msg))
end

function Util.lower(s)
    if s == nil then return "" end
    return string.lower(tostring(s))
end

function Util.is_valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

function Util.safe_name(obj)
    if obj == nil then return "<nil>" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and name then return name end
    return "<invalid>"
end

function Util.safe_class_name(obj)
    if obj == nil then return "<nil>" end
    local ok, name = pcall(function()
        local cls = obj:GetClass()
        if cls and cls:IsValid() then
            return cls:GetFName():ToString()
        end
        return nil
    end)
    if ok and name then return name end
    return "<unknown>"
end

function Util.ue_type(value)
    local ok, t = pcall(function() return type(value) end)
    if ok then return t end
    return "unknown"
end

function Util.resolve_key(name)
    if Key ~= nil and Key[name] ~= nil then return Key[name] end
    local fallback = { F6 = 0x75, F7 = 0x76, F8 = 0x77, F9 = 0x78 }
    return fallback[name]
end

function Util.ensure_dir(path)
    if path == nil or path == "" then return false end
    pcall(function() os.execute(string.format('mkdir "%s" 2>nul', path)) end)
    return true
end

function Util.temp_queue_dir(name)
    local base = os.getenv("TEMP") or os.getenv("TMP") or "."
    local path = string.format("%s\\%s", base, name or "MapSyncQueue")
    Util.ensure_dir(path)
    return path
end

function Util.write_text_file(path, contents)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(contents)
    f:close()
    return true
end

function Util.read_text_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function Util.list_files_with_prefix(dir, prefix)
    local results = {}
    local cmd = string.format('dir /b "%s\\%s*" 2>nul', dir, prefix or "")
    local p = io.popen(cmd)
    if not p then return results end
    for line in p:lines() do
        if line and line ~= "" then table.insert(results, line) end
    end
    p:close()
    return results
end

return Util
