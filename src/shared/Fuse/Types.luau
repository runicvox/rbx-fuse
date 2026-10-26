export type Service = {
  Name: string,
  Priority: number?,
  Client: {
    Server: Service,
  },

  Init: ((self: Service) -> ())?,
  Start: ((self: Service) -> ())?,
}

return {}