# Package

version = "0.1.0"
author = "Esteban Castro Borsani (@nitely)"
description = "An async pub/sub client and server"
license = "MIT"
srcDir = "src"
skipDirs = @["tests", "examples"]

requires "nim >= 2.2.0"
requires "hyperx >= 0.1.53"

task test, "Test":
  exec "nim c -r src/hyps/utils.nim"

task tserve, "Test serve":
  exec "nim c -r tests/tserver.nim"

task tclient, "Test client":
  exec "nim c -r tests/tclient.nim"
