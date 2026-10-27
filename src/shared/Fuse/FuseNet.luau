
--[=[
  @class FuseNet

  Manages client-server networking through Jolt.
]=]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Promise = require("@game/ReplicatedStorage/Packages/promise")
local Jolt = require("@game/ReplicatedStorage/Packages/jolt")

local Types = require("./Types")
type Service = Types.Service

local FuseNet = {}

local EVENT_MARKER = "FUSE_REMOTE_EVENT"
local MANIFEST_ATTRIBUTE = "RemoteManifest"

local IS_SERVER = RunService:IsServer()

local registry = script.Parent

local remotes: {[string]: any} = {}
local proxies: {[string]: any} = {}

local remoteManifest: {[string]: {[string]: string}} = {}
local registeredServices: {[string]: boolean} = {}

local startPromise = nil

-- PUBLIC API

--[=[
  Returns a marker for a client-facing event.

  @return string -- Event marker.
]=]
function FuseNet.Event(): string
  return EVENT_MARKER
end

--[=[
  Creates or retrieves a named remote event.

  @param remoteName string -- Remote identifier.
  @return any -- Jolt remote.
]=]
function FuseNet.NewEvent(remoteName: string)
  assert(type(remoteName) == "string" and remoteName ~= "", "Invalid remote name.")

  local remote = remotes[remoteName]

  if remote then
    return remote
  end

  -- create a remote for the current environment
  if IS_SERVER then
    remote = Jolt.Server(remoteName)
  else
    remote = Jolt.Client(remoteName)
  end

  remotes[remoteName] = remote

  return remote
end

--[=[
  Creates a named remote method.

  @param remoteName string -- Remote identifier.
  @param callback function? -- Server callback.
  @return any -- Remote method.
]=]
function FuseNet.NewMethod(remoteName: string, callback: ((Player, ...any) -> ...any)?)
  local remote = FuseNet.NewEvent(remoteName)

  if IS_SERVER then
    assert(type(callback) == "function", "Remote method requires a callback.")

    remote.OnInvoke = callback

    return remote
  end

  -- return a promise-based client method
  return function(_, ...)
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
  assert(IS_SERVER, "Service remotes can only be created on the server.")
  assert(not startPromise, "Cannot create service remotes after networking has started.")
  assert(not registeredServices[service.Name], `Service "{service.Name}" already has remotes.`)

  local client = service.Client or {}

  -- reference the original service
  client.Server = service
  service.Client = client

  local members: {[string]: string} = {}

  -- register exposed service members
  for memberName, member in client do
    if memberName == "Server" then
      continue
    end

    assert(type(memberName) == "string" and memberName ~= "", "Invalid client member name.")

    local remoteName = `{service.Name}:{memberName}`

    if member == EVENT_MARKER then
      members[memberName] = "Event"

      -- replace the marker with its jolt remote
      client[memberName] = FuseNet.NewEvent(remoteName)

    elseif type(member) == "function" then
      members[memberName] = "Method"

      -- preserve the client table as self
      FuseNet.NewMethod(remoteName, function(player: Player, ...)
        return member(client, player, ...)
      end)

    else
      error(`Invalid client member "{memberName}" in service "{service.Name}".`)
    end
  end

  -- store the service interface for client discovery
  remoteManifest[service.Name] = members
  registeredServices[service.Name] = true
end

--[=[
  Creates or returns a client-facing service proxy.

  @param serviceName string -- Service name.
  @return table -- Service proxy.
]=]
function FuseNet.CreateServiceProxy(serviceName: string): {[string]: any}
  assert(not IS_SERVER, "Service proxies are client-only.")
  assert(remoteManifest ~= nil and startPromise ~= nil, "FuseNet has not started.")

  local proxy = proxies[serviceName]

  if proxy then
    return proxy
  end

  local serviceMembers = remoteManifest[serviceName]

  assert(serviceMembers ~= nil, `Service "{serviceName}" does not exist.`)

  local members: {[string]: any} = {}

  -- resolve remote members when accessed
  proxy = setmetatable({}, {
    __index = function(_, memberName: string)
      local member = members[memberName]

      if member then
        return member
      end

      local remoteType = serviceMembers[memberName]
      local remoteName = `{serviceName}:{memberName}`

      if remoteType == "Event" then
        member = FuseNet.NewEvent(remoteName)

      elseif remoteType == "Method" then
        member = FuseNet.NewMethod(remoteName)

      else
        error(`Remote "{remoteName}" does not exist.`, 2)
      end

      members[memberName] = member

      return member
    end,
  })

  proxies[serviceName] = proxy

  return proxy
end

--[=[
  Starts networking and resolves when service interfaces are available.

  @return Promise -- Networking readiness.
]=]
function FuseNet.Start()
  if startPromise then
    return startPromise
  end

  if IS_SERVER then
    -- publish the complete service manifest
    local encodedManifest = HttpService:JSONEncode(remoteManifest)

    registry:SetAttribute(MANIFEST_ATTRIBUTE, encodedManifest)

    startPromise = Promise.resolve()
  else
    startPromise = Promise.new(function(resolve, reject, onCancel)
      local connection

      local function loadManifest()
        local encodedManifest = registry:GetAttribute(MANIFEST_ATTRIBUTE)

        if type(encodedManifest) ~= "string" then
          return
        end

        -- decode the replicated service interfaces
        local success, manifest = pcall(function()
          return HttpService:JSONDecode(encodedManifest)
        end)

        if not success then
          if connection then
            connection:Disconnect()
          end

          reject(manifest)
          return
        end

        remoteManifest = manifest

        if connection then
          connection:Disconnect()
        end

        resolve()
      end

      -- listen for the server's published manifest
      connection = registry:GetAttributeChangedSignal(MANIFEST_ATTRIBUTE):Connect(loadManifest)

      onCancel(function()
        connection:Disconnect()
      end)

      -- handle a manifest that has already replicated
      loadManifest()
    end)
  end

  return startPromise
end

return FuseNet
