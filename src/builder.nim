import builder/[common, pages], os, strutils

proc main() =
  var builder = Builder(
    pagesDir: "pages",
    assetsDir: "assets",
    templatesDir: "assets/templates",
    outputDir: (when defined(testrun): "output" else: "public"),
    host:
      case getEnv("SITE_HOST").toLowerAscii
      of "firebase": firebase
      of "cloudflare": cloudflare
      of "githubpages": githubPages
      else: unspecified
  )

  copyDir(builder.pagesDir, builder.outputDir)
  copyDir(builder.assetsDir, builder.outputDir / builder.assetsDir)
  
  pipeline(builder):
    var
      pages: Pages

when isMainModule: main()
