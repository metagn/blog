import common, pages/[generator, info], std/[tables, os, strutils, json, locks]

const MargThreadpoolSize = 1 shl (when defined(gcDestructors): 3 else: 0)

type
  Redirect = object
    source, destination: string
    `type`: int

  Pages* = object
    builder*: Builder
    redirects: seq[Redirect]
    templateLock: Lock
    templates {.guard: templateLock.}: Table[string, string]
    defaultTemplate: tuple[path, content: string]
    margThreads: array[MargThreadpoolSize, Thread[(ptr Pages, ptr Channel[string])]]
    margChannels: array[MargThreadpoolSize, Channel[string]]

proc processRedirect(pages: var Pages, path: string): Redirect =
  let s = readFile(path).splitWhitespace()
  if s.len == 0:
    echo "redirect file ", path, " does not have url inside"
    return
  result.destination = s[0]
  result.source = path[pages.builder.outputDir.len ..< ^".redirect".len].replace('\\', '/')
  if result.source.len > 1 and result.source[^1] == '/':
    result.source.setLen(result.source.len - 1)
  if s.len > 1 and s[1].len != 0:
    result.type = s[1].parseInt
  else:
    result.type = 301

proc processRedirects(pages: var Pages, path: string): seq[Redirect] =
  let dir = path[pages.builder.outputDir.len ..< ^".redirects".len].replace('\\', '/')
  var f: File
  if not open(f, path):
    echo "could not open redirects file ", path
    return
  var line: string
  while readLine(f, line):
    let s = splitWhitespace(line, 2)
    if s.len != 2 or s[0].len == 0 or s[1].len == 0:
      echo "redirects file ", path, " has invalid redirect ", line
      continue
    # xxx make destination path relative opt-in
    var redir = Redirect(type: 301, source: dir, destination: s[1])
    proc join(a: var string, b: string) =
      if b[0] != '/': a.add('/')
      elif a[^1] == '/': a.setLen(a.len - 1)
      a.add(b)
    join(redir.source, s[0])
    result.add(redir)

proc getTemplate(pages: var Pages, name: string): lent string =
  withLock pages.templateLock:
    if not pages.templates.hasKey(name):
      pages.templates[name] = readFile(name)
    result = pages.templates[name]
  
proc margger(arg: (ptr Pages, ptr Channel[string])) {.thread.} =
  let (pages, chan) = arg
  let builder = pages.builder
  while true:
    let f = chan[].recv()
    if f == "": break
    let page = loadPage(pkMargrave, f)
    var templ: string
    if page.info.`template`.len != 0:
      templ = pages[].getTemplate(page.info.`template`)
    if templ.len == 0:
      templ = pages[].defaultTemplate.content
    let html = page.toHtml(templ)
    builder.output(f[0..<f.rfind('.')] & ".html", html)
    echo "margged file: ", f

proc finishRedirects(pages: var Pages) =
  if pages.builder.host == githubPages: return
  if pages.builder.host in {firebase, unspecified}:
    let config = json.parseFile(pages.builder.templatesDir & "/firebase.json")
    if not config["hosting"].hasKey("redirects"):
      config["hosting"]["redirects"] = %[]
    for r in pages.redirects:
      config["hosting"]["redirects"].add(%r)
    when defined(testrun):
      writeFile(pages.builder.outputDir & "/firebase.json", pretty(config))
    else:
      writeFile("firebase.json", $config)
  if pages.builder.host in {cloudflare, unspecified}:
    var redirectsFile = ""
    for r in pages.redirects:
      redirectsFile.add(r.source)
      redirectsFile.add(' ')
      redirectsFile.add(r.destination)
      redirectsFile.add(' ')
      redirectsFile.addInt(r.type)
      redirectsFile.add("\n")
    when defined(testrun):
      writeFile(pages.builder.outputDir & "/_redirects", redirectsFile)
    else:
      writeFile("_redirects", redirectsFile)
  echo "added redirects to config"
  reset(pages.redirects)

proc finishMargs(pages: var Pages) =
  joinThreads(pages.margThreads)
  echo "all margged"

  for i in 0 ..< MargThreadpoolSize:
    pages.margChannels[i].close()
  reset(pages.defaultTemplate)
  withLock pages.templateLock:
    pages.templates.clear()
  deinitLock(pages.templateLock)

proc process*(pages: var Pages) =
  let builder = pages.builder
  initLock(pages.templateLock)
  let defaultTempl = builder.templatesDir & "/default.html"
  pages.defaultTemplate = (path: defaultTempl, content: pages.getTemplate(defaultTempl))
  for i in 0 ..< MargThreadpoolSize:
    pages.margChannels[i].open()
    createThread(pages.margThreads[i], margger, (addr pages, addr pages.margChannels[i]))
  
  var currentThread = 0
  for f in walkDirRec(builder.outputDir):
    if f.endsWith(".md") or f.endsWith(".mrg"):
      echo "queueing the enmargging of file: ", f
      pages.margChannels[currentThread].send(f)
      currentThread = (currentThread + 1) and (MargThreadpoolSize - 1)
    elif f.endsWith(".redirect"):
      pages.redirects.add processRedirect(pages, f)
    elif f.endsWith(".redirects"):
      pages.redirects.add processRedirects(pages, f)
  for i in 0 ..< MargThreadpoolSize:
    pages.margChannels[i].send("")

  pages.finishRedirects()
  pages.finishMargs()
