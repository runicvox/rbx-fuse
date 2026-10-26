--[=[
  @class FuseClient
  @client

  Manages client-side controllers and their lifecycle.
]=]

local Types = require("./Types")
type Controller = Types.Controller

local Promise = require("@game/ReplicatedStorage/Packages/promise")
local t = require("@game/ReplicatedStorage/Packages/t")

local FuseClient = {}

local controllers: {[string]: Controller} = {}

local started = false

local resolveReady
local rejectReady

local readyPromise = Promise.new(function(resolve, reject)
  resolveReady = resolve
  rejectReady = reject
end)

local validateController = t.interface({
  Name = t.string,
  Priority = t.optional(t.number),
  Init = t.optional(t.callback),
  Start = t.optional(t.callback),
})

-- PUBLIC API

--[=[
  Registers and returns a controller.

  @param def any? -- Controller definition.
  @return Controller -- Registered controller.
]=]
function FuseClient.NewController(def: any): Controller
  assert(validateController(def), `Invalid service definition.`)
  assert(controllers[def.Name] == nil, `Service "{def.Name}" is already registered.`)

  local controller = def :: Controller

  -- assign defaults
  controller.Priority = controller.Priority or 0

  controllers[controller.Name] = controller

  return controller
end

--[=[
  Returns a registered controller by name.

  @param name string -- Controller name.
  @return Controller? -- Registered controller, if found.
]=]
function FuseClient.GetController(name: string): Controller?
  return controllers[name]
end

--[=[
  Adds and returns controllers from descendant modules.

  @param folder Instance -- Parent container.
  @return {Controller} -- Added controllers.
]=]
function FuseClient.AddControllers(folder: Instance): {Controller}
  local addedControllers: {Controller} = {}

  -- collect registered controllers
  for _, instance in folder:GetDescendants() do
    if not instance:IsA("ModuleScript") then
      continue
    end

    local controller = require(instance)
    table.insert(addedControllers, controller)
  end

  return addedControllers
end

--[=[
  Initialises and starts registered services.

  @return Promise -- Server startup.
]=]
function FuseClient.Start()
  if started then
    return Promise.reject("FuseClient has already started.")
  end

  started = true

  local sortedControllers = getSortedControllers()

  local startup = initControllers(sortedControllers)
    :andThen(function()
      startControllers(sortedControllers)
    end)

  startup:andThen(resolveReady, rejectReady)

  return startup
end

--[=[
  Resolves when the server lifecycle is ready.

  @return Promise -- Server readiness.
]=]
function FuseClient.Ready()
  return readyPromise
end

-- PRIVATE FUNCTIONS

--[=[
  Initialises all registered controllers.

  @param sortedControllers {Controller} -- Sorted controllers.
  @return Promise -- Initialisation completion.
]=]
function initControllers(sortedControllers: {Controller})
  local promises = {}

  for _, controller in sortedControllers do
    if controller.Init then
      table.insert(promises, Promise.try(controller.Init, controller))
    end
  end

  return Promise.all(promises)
end

--[=[
  Schedules startup for all registered controllers.

  @param sortedControllers {Controller} -- Sorted controllers.
]=]
function startControllers(sortedControllers: {Controller})
  for _, controller in sortedControllers do
    if controller.Start then
      task.spawn(controller.Start, controller)
    end
  end
end

--[=[
  Returns controllers sorted by priority and name.

  @return {Controller} -- Sorted controllers.
]=]
function getSortedControllers(): {Controller}
  local sortedControllers: {Controller} = {}

  -- collect registered controllers
  for _, controller in controllers do
    table.insert(sortedControllers, controller)
  end

  -- sort by descending priority, then name
  table.sort(sortedControllers, function(controller1, controller2)
    if controller1.Priority == controller2.Priority then
      return controller1.Name < controller2.Name
    end

    return controller1.Priority > controller2.Priority
  end)

  return sortedControllers
end

return FuseClient