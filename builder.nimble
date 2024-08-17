# Package

version       = "0.1.0"
author        = "blog"
description   = "site builder for blog"
license       = "MIT"


# Dependencies

requires "nim >= 1.6.4"
requires "margrave#HEAD"

task runBuilder, "runs builder":
  exec "nim r -d:release src/builder"

task testBuilder, "tests builder":
  exec "nim r -d:release -d:testrun src/builder"

task cleanPublic, "clean public folder":
  rmDir "public"
