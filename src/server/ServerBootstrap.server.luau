--[[
  Starts the server framework.
]]

local Fuse = require("@game/ReplicatedStorage/Fuse/FuseServer")

Fuse.AddServices(script.Parent:WaitForChild("Server"))

Fuse.Start()
  :andThen(function()
    warn("FuseServer started.")
  end)
  :catch(warn)
