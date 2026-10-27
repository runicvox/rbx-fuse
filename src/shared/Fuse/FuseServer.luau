--[=[
  @class FuseServer
  @server

  Manages server-side services and their lifecycle.
]=]

local Types = require("./Types")
type Service = Types.Service

local Promise = require("@game/ReplicatedStorage/Packages/promise")
local t = require("@game/ReplicatedStorage/Packages/t")

local FuseNet = require("./FuseNet")

local FuseServer = {}

FuseServer.Event = FuseNet.Event

local services: {[string]: Service} = {}

local started = false

local resolveReady
local rejectReady

local readyPromise = Promise.new(function(resolve, reject)
  resolveReady = resolve
  rejectReady = reject
end)

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

--[=[
  Initialises and starts registered services.

  @return Promise -- Server startup.
]=]

function FuseServer.Start()
  if started then
    return Promise.reject("FuseServer has already started.")
  end

  started = true

  local sortedServices = getSortedServices()

  -- register remotes before initialisation
  for _, service in sortedServices do
    FuseNet.CreateServiceRemotes(service)
  end

  local startup = initServices(sortedServices)
    :andThen(function()
      return FuseNet.Start()
    end)
    :andThen(function()
      startServices(sortedServices)
    end)

  startup:andThen(resolveReady, rejectReady)

  return startup
end


--[=[
  Resolves when the server lifecycle is ready.

  @return Promise -- Server readiness.
]=]
function FuseServer.Ready()
  return readyPromise
end

-- PRIVATE FUNCTIONS

--[=[
  Initialises all registered services.

  @param sortedServices {Service} -- Sorted services.
  @return Promise -- Initialisation completion.
]=]
function initServices(sortedServices: {Service})
  local promises = {}

  for _, service in sortedServices do
    if service.Init then
      table.insert(promises, Promise.try(service.Init, service))
    end
  end

  return Promise.all(promises)
end

--[=[
  Schedules startup for all registered services.

  @param sortedServices {Service} -- Sorted services.
]=]
function startServices(sortedServices: {Service})
  for _, service in sortedServices do
    if service.Start then
      task.spawn(service.Start, service)
    end
  end
end

--[=[
  Returns services sorted by priority and name.

  @return {Service} -- Sorted services.
]=]
function getSortedServices(): {Service}
  local sortedServices: {Service} = {}

  -- collect registered services
  for _, service in services do
    table.insert(sortedServices, service)
  end

  -- sort by descending priority, then name
  table.sort(sortedServices, function(service1, service2)
    if service1.Priority == service2.Priority then
      return service1.Name < service2.Name
    end

    return service1.Priority > service2.Priority
  end)

  return sortedServices
end

return FuseServer