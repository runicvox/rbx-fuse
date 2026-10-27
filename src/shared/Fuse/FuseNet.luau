local RunService = game:GetService("RunService")
--[=[
  @class FuseNet

  Manages client-server networking through Jolt.
]=]

local Types = require("./Types")
type Service = Types.Service

local Promise = require("@game/ReplicatedStorage/Packages/promise")

local Jolt = require("./Jolt")

local FuseNet = {}

local EVENT_MARKER = "FUSE_REMOTE_EVENT"

local registryFolder: Folder? = script.Parent

-- PUBLIC API

--[=[
  Returns a marker for a client-facing event.

  @return string -- Event marker.
]=]
function FuseNet.Event(): string
  return EVENT_MARKER
end

--[=[
  Creates a named remote event.

  @param name string -- Remote identifier.
  @return any -- Jolt remote.
]=]
function FuseNet.NewEvent(name: string)
  if RunService:IsServer() then
    return Jolt.Server(name)
  end

  return Jolt.Client(name)
end

--[=[
  Creates a named remote method.

  @param name string -- Remote identifier.
  @param callback function? -- Server callback.
  @return any -- Jolt remote.
]=]
function FuseNet.NewMethod(name: string, callback: ((Player, ...any) -> ...any)?)
  if RunService:IsServer() then
    local remote = Jolt.Server(name)
    remote.OnInvoke = callback

    return remote
  end

  local remote = Jolt.Client(name)

  -- invoke the remote asynchronously
  return function(...)
    local args = table.pack(...)

    return Promise.try(function()
      return remote:Invoke(table.unpack(args, 1, args.n))
    end)
  end
end

--[=[
  Creates remotes for a service's client interface.

  @param service Service -- Registered service.
]=]
function FuseNet.CreateServiceRemotes(service: Service)
  local client = service.Client

  -- register each exposed method or event
  for name, member in client do
    if name == "Server" then
      continue
    end

    local remoteName = `{service.Name}:{name}`
    local remoteType

    if member == EVENT_MARKER then
      remoteType = "Event"
      client[name] = FuseNet.NewEvent(name)
    elseif type(member) == "function" then
      remoteType = "Method"

      FuseNet.NewMethod(remoteName, function(player: Player, ...)
        return member(client, player, ...)
      end)
    end

    -- publish metadata for client service proxies
    (registryFolder :: Folder):SetAttribute(remoteName, remoteType)
  end

  (registryFolder :: Folder):SetAttribute(`Service:{service.Name}`, true)
end

return FuseNet