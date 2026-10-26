
--[=[
  @class Types

  Defines shared Fuse types.
]=]

export type Service = {
  Name: string,
  Priority: number?,
  Client: {[string]: any}?,

  Init: ((self: Service) -> ())?,
  Start: ((self: Service) -> ())?,
}

export type Controller = {
  Name: string,
  Priority: number?,
  
  Init: ((self: Controller) -> ())?,
  Start: ((self: Controller) -> ())?,
}

return {}
