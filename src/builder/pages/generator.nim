import strutils, info, margrave, margrave/[common, element], margrave/parser/[defs, utils]

type
  PageKind* = enum
    pkAsset, pkMargrave
  Page* = ref object
    case kind*: PageKind
    of pkMargrave:
      info*: Info
      body*: string
    of pkAsset: discard

proc loadFrom*(page: Page, file: File) =
  var 
    line = ""
    recordMeta = false

  while file.readLine(line):
    if line.isEmptyOrWhitespace:
      continue
    elif line == "---":
      recordMeta = true
    else:
      page.body.add(line)
      page.body.add("\n")
    break
  if recordMeta:
    var meta: string
    while file.readLine(line) and line != "---":
      meta.add(line)
      meta.add("\n")
    page.info = parseInfo(meta)
  while file.readLine(line):
    page.body.add(line)
    page.body.add("\n")

proc loadFrom*(page: Page, text: string) =
  let lines = text.splitLines
  var
    i = 0
    recordMeta = false

  while i < lines.len:
    let line = lines[i]
    inc i
    if line.isEmptyOrWhitespace:
      continue
    elif line == "---":
      recordMeta = true
    else:
      page.body.add(line)
      page.body.add("\n")
    break
  if recordMeta:
    var meta: string
    while i < lines.len:
      let line = lines[i]
      inc i
      if line == "---":
        break
      else:
        meta.add(line)
        meta.add("\n")
    page.info = parseInfo(meta)
  while i < lines.len:
    let line = lines[i]
    inc i
    page.body.add(line)
    page.body.add("\n")

proc loadPage*(kind: PageKind, path: string): Page =
  result = Page(kind: kind)
  let file = open(path, fmRead)
  defer: file.close()
  result.loadFrom(file)

proc processSingleElement(page: Page, element: MargraveElement) =
  if page.info.lazy:
    if not element.isText:
      case element.tag
      of img: element.attr("loading", "lazy")
      of audio, video: element.attr("preload", "none")
      else: discard

proc processNested(page: Page, element: MargraveElement) =
  processSingleElement(page, element)
  if not element.isText:
    for c in element.content:
      processNested(page, c)

import uri

proc setYoutube(element: MargraveElement, id: NativeString) =
  element.tag = otherTag
  element.attr("tag", "iframe")
  element.attr("width", "953")
  element.attr("height", "536")
  element.attr("src", NativeString"https://www.youtube.com/embed/" & id)
  element.attr("title", "(youtube embed)")
  element.attr("frameborder", "0")
  element.attr("allow", "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture")
  element.attr("allowfullscreen", "")

proc setLink(element: MargraveElement, link: Link) =
  if not element.isText and element.tag == img:
    let uri = parseUri($link)
    var h = uri.hostname
    h.removePrefix("www.")
    case h
    of "youtu.be":
      let id = toNativeString(uri.path)
      if id.len != 0:
        setYoutube(element, id)
        return
    of "youtube.com":
      var id: NativeString
      for k, v in decodeQuery(uri.query):
        if k == "v":
          id = toNativeString(v)
          break
      if id.len != 0:
        setYoutube(element, id)
        return
    else: discard
  setLinkDefault(element, link)

proc genMg(page: Page): string =
  let options = MargraveOptions(setLinkHandler: setLink, insertLineBreaks: true, disableTextAlignExtension: false)
  for b in parseMargrave(page.body, options):
    processNested(page, b)
    result.add($b)

proc toHead*(meta: Info): string =
  # XXX no HTML escaping here
  for a in meta.elements:
    case a.name
    of "template", "lazy": discard
    of "title":
      result.add("<title>")
      result.add(a.body)
      result.add("</title>")
      result.add("<meta property=\"og:title\" content=\"")
      result.add(a.body)
      result.add("\"/>")
    of "description":
      result.add("<meta property=\"description\" content=\"")
      result.add(a.body)
      result.add("\"/>")
      result.add("<meta property=\"og:description\" content=\"")
      result.add(a.body)
      result.add("\"/>")
    of "background":
      let val = a.body
      result.add("<style>body{background-")
      if '/' in val:
        result.add("image:url(\"")
        result.add(val)
        result.add("\")")
      else:
        result.add("color:")
        result.add(val)
      result.add("}</style>")
    of "icon":
      let link = a.body
      result.add("<link rel=\"icon\" ")
      if link.endsWith(".ico"):
        result.add("type=\"image/x-icon\" ")
      elif link.endsWith(".png"):
        result.add("type=\"image/png\" ")
      elif link.endsWith(".jpg") or link.endsWith(".jpeg"):
        result.add("type=\"image/jpeg\" ")
      result.add("href=\"")
      result.add(link)
      result.add("\"/>")
    of "stylesheet":
      result.add("<link rel=\"stylesheet\" href=\"")
      result.add(a.body)
      result.add("\"/>")
    else:
      result.add('<')
      result.add(a.name)
      proc addArgument(res: var string, arg: tuple[name, value: string]) =
        if arg.name.len == 0:
          echo "got argument without name"
        else:
          res.add(' ')
          res.add(arg.name)
        if arg.value.len != 0:
          res.add("=\"")
          res.add(arg.value)
          res.add('"')
      for i in 0 ..< a.arguments.len - 1:
        addArgument(result, a.arguments[i])
      let needsBody = a.name in ["script"]
      if a.arguments.len != 0:
        let last = a.arguments[^1]
        if last.name.len != 0:
          addArgument(result, last)
          if needsBody:
            result.add("></")
            result.add(a.name)
            result.add('>')
          else:
            result.add("/>")
        else:
          result.add('>')
          result.add(last.value)
          result.add("</")
          result.add(a.name)
          result.add('>')
      else:
        if needsBody:
          result.add("></")
          result.add(a.name)
          result.add('>')
        else:
          result.add("/>")

proc toHtml*(page: Page, tmpl: string): string =
  result = tmpl.multiReplace({
    "$head": toHead(page.info),
    "$body": case page.kind
             of pkMargrave: genMg(page)
             else: ""
  })
