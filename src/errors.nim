
type HypsError* = object of CatchableError

func newHypsError*(msg: string): ref HypsError {.raises: [].} =
  result = (ref HypsError)(msg: msg)
