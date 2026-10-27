
--[=[
  Starts the client framework.
]=]


local Fuse = require("@game/ReplicatedStorage/Fuse/FuseClient")

Fuse.AddControllers(script.Parent:WaitForChild("Controllers"))

Fuse.Start()
  :andThen(function()
    print("FuseClient started.")
  end)
  :catch(warn)
