import std/[asyncdispatch]

const localHost* = "127.0.0.1"
const localPort* = Port 8783

func toSize*(n: Natural): string {.raises: [].} =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  result = ""
  let n = n.uint32
  result.add ((n shr 24) and 8.ones).char
  result.add ((n shr 16) and 8.ones).char
  result.add ((n shr 8) and 8.ones).char
  result.add (n and 8.ones).char
