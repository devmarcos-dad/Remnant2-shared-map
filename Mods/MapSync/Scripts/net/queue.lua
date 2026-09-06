local Util = require("lib.util")
local Config = require("config")
local Protocol = require("net.protocol")

local Queue = {
    Dir = nil,
    Outbox = nil,
    Inbox = nil,
    Seq = 0,
    SeenFiles = {},
}

function Queue.init()
    local name = (Config.Lan and Config.Lan.QueueDirName) or "MapSyncQueue"
    Queue.Dir = Util.temp_queue_dir(name)
    Queue.Outbox = Queue.Dir .. "\\outbox"
    Queue.Inbox = Queue.Dir .. "\\inbox"
    Util.ensure_dir(Queue.Outbox)
    Util.ensure_dir(Queue.Inbox)
    Util.log("queue dir=%s", Queue.Dir)
    return Queue.Dir
end

function Queue.next_seq()
    Queue.Seq = Queue.Seq + 1
    return Queue.Seq
end

function Queue.publish(line)
    if Queue.Outbox == nil then Queue.init() end
    local seq = Queue.next_seq()
    local path = string.format("%s\\%d_%d.msg", Queue.Outbox, os.time(), seq)
    local body = line
    if not string.find(line, "\n", 1, true) then body = line .. "\n" end
    local ok, err = Util.write_text_file(path, body)
    if not ok then
        Util.flog("LAN", "outbox write fail path=%s err=%s", tostring(path), tostring(err))
        return false
    end
    return true
end

function Queue.send_hello(role)
    return Queue.publish(Protocol.encode_hello(role, Queue.Seq))
end

function Queue.send_bye(role)
    return Queue.publish(Protocol.encode_bye(role, Queue.next_seq()))
end

function Queue.send_fog(enabled)
    return Queue.publish(Protocol.encode_fog(enabled, Queue.next_seq()))
end

function Queue.send_tile(zone_id, x, y)
    return Queue.publish(Protocol.encode_tile(zone_id, x, y, Queue.next_seq()))
end

function Queue.send_tiles(tiles)
    return Queue.publish(Protocol.encode_tiles(tiles, Queue.next_seq()))
end

function Queue.send_pos(x, y, z)
    return Queue.publish(Protocol.encode_pos(x, y, z, Queue.next_seq()))
end

function Queue.poll_inbox()
    if Queue.Inbox == nil then Queue.init() end
    local messages = {}
    local files = Util.list_files_with_prefix(Queue.Inbox, "")
    table.sort(files)
    for _, name in ipairs(files) do
        if string.match(name, "%.msg$") then
            local full = Queue.Inbox .. "\\" .. name
            if not Queue.SeenFiles[full] then
                local data = Util.read_text_file(full)
                Queue.SeenFiles[full] = true
                if data then
                    for line in string.gmatch(data, "[^\r\n]+") do
                        local msg = Protocol.decode(line)
                        if msg then
                            table.insert(messages, msg)
                        else
                            Util.flog("LAN", "inbox decode fail line=%s", tostring(line):sub(1, 120))
                        end
                    end
                end
                pcall(function() os.remove(full) end)
            end
        end
    end
    return messages
end

return Queue
