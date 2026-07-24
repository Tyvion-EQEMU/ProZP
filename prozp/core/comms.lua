-- Thin wrapper over MQ's native actors module: fire-and-forget broadcast pub/sub,
-- keyed by a `type` field on the payload. No DanNet/EQBC dependency for runtime state —
-- every ProZP instance registers the same anonymous per-script actor and broadcasts to it.

local actors = require('actors')

local Comms = {}

local _actor    = nil
local _handlers = {}

local function dispatch(message)
    local content = message.content
    if not content or not content.type then return end
    local handler = _handlers[content.type]
    if handler then handler(content, message.sender) end
end

function Comms.Init()
    if _actor then return end
    _actor = actors.register(dispatch)
end

-- Register a callback for a message type. content is the payload table (with .type set).
function Comms.On(msgType, callback)
    _handlers[msgType] = callback
end

-- Broadcasts payload (tagged with msgType) to every client running this script.
function Comms.Send(msgType, payload)
    payload = payload or {}
    payload.type = msgType
    actors.send(payload)
end

return Comms
