# Package

version       = "0.1.0"
author        = "metagn"
description   = "site builder for blog"
license       = "MIT"


# Dependencies

requires "nim >= 1.6.4"
requires "margrave#HEAD"
requires "https://github.com/metagn/rot#HEAD"

task runBuilder, "runs builder":
  exec "nim r -d:release src/presser"

task testBuilder, "tests builder":
  exec "nim r -d:release -d:testrun src/presser"

task cleanPublic, "clean public folder":
  rmDir "public"
