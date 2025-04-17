import std/[asyncdispatch]
import ../src/server
import ./utils

proc main() {.async.} =
  echo "Serving forever"
  await serve(localHost, localPort)

when isMainModule:
  waitFor main()
  doAssert not hasPendingOperations()
  echo "ok"
