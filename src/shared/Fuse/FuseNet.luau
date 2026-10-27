local RunService = game:GetService("RunService")
--[=[
  @class FuseNet

  Manages client-server networking through Jolt.
]=]

local Jolt = require("./Jolt")

local FuseNet = {}

local EVENT_MARKER = "FUSE_REMOTE_EVENT"

-- PUBLIC API

--[=[
  Returns a marker for a client-facing event.

  @return string -- Event marker.
]=]
function FuseNet.Event(): string
  return EVENT_MARKER
end

return FuseNet