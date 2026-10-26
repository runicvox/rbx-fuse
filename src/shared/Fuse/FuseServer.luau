--[=[
  @class FuseServer
  @server

  Manages server-side services and their lifecycle.
]=]

local Types = require("./Types")
type Service = Types.Service

local t = require("@game/ReplicatedStorage/Packages/t")

local FuseServer = {}

local services: {[string]: Service} = {}

local validateService = t.interface({
  Name = t.string,
  Priority = t.optional(t.number),
  Client = t.optional(t.table),
  Init = t.optional(t.callback),
  Start = t.optional(t.callback),
})

-- PUBLIC API

--[=[
  Registers and returns a service.

  @param def any? -- Service definition.
  @return Service -- Registered service.
]=]
function FuseServer.NewService(def: any): Service
  assert(validateService(def), `Invalid service definition.`)
  assert(services[def.Name] == nil, `Service "{def.Name}" is already registered.`)

  local service = def :: Service

  -- assign defaults
  service.Priority = service.Priority or 0
  service.Client = service.Client or {}
  service.Client.Server = service

  services[service.Name] = service

  return service
end

--[=[
  Returns a registered service by name.

  @param name string -- Service name.
  @return Service? -- Registered service, if found.
]=]
function FuseServer.GetService(name: string): Service?
  return services[name]
end

--[=[
  Adds and returns services from descendant modules.

  @param folder Instance -- Parent container.
  @return {Service} -- Added services.
]=]
function FuseServer.AddServices(folder: Instance): {Service}
  local addedServices: {Service} = {}

  -- collect registered services
  for _, instance in folder:GetDescendants() do
    if not instance:IsA("ModuleScript") then
      continue
    end

    local service = require(instance)
    table.insert(addedServices, service)
  end

  return addedServices
end

return FuseServer