import strutils

type
  Element* = ref object
    name*: string
    arguments*: seq[tuple[name, value: string]]
  Info* = object
    elements*: seq[Element]
    `template`*: string
    title*, description*: string
    lazy*: bool

proc body*(elem: Element): lent string =
  elem.arguments[^1].value

const
  NameSet = Letters + {'-', '_'}
  InlineWhitespace = Whitespace - Newlines

proc recordComment(str: string, i: var int) =
  while i < str.len:
    if str[i] in Newlines:
      dec i
      return
    inc i

proc recordName(str: string, i: var int): string =
  while i < str.len:
    if str[i] in NameSet:
      result.add(str[i])
    else:
      dec i
      return
    inc i

proc recordQuoted(str: string, i: var int): string =
  let quote = str[i]
  inc i
  var escaped = false
  while i < str.len:
    let ch = str[i]
    if escaped:
      result.add('\\')
      result.add(ch)
      escaped = false
    elif ch == quote:
      return
    elif ch == '\\':
      escaped = true
    else: result.add(ch)
    inc i

proc recordNamedArgument(str: string, i: var int): tuple[name, value: string] =
  result.name = recordName(str, i)
  inc i
  var waitingForValue = false
  while i < str.len:
    let ch = str[i]
    if not waitingForValue:
      case ch
      of Newlines:
        dec i
        return
      of InlineWhitespace: discard
      of '=':
        waitingForValue = true
      else:
        dec i
        return
    else:
      case ch
      of Newlines, '#':
        dec i
        return
      of NameSet:
        result.value = recordName(str, i)
        return
      of '\'', '"':
        result.value = recordQuoted(str, i)
        return
      else: discard
    inc i

proc recordBlockLine(str: string, i: var int): string =
  var escaped = false
  while i < str.len:
    let ch = str[i]
    if escaped:
      if ch in Newlines:
        result.add(' ')
      else:
        result.add('\\')
        result.add(ch)
      escaped = false
    elif ch == '\\':
      escaped = true
    elif ch in Newlines:
      return
    else: result.add(ch)
    inc i

proc recordBlock(str: string, indent: int, i: var int): string =
  var ind = 0
  result.add(recordBlockLine(str, i))
  while i < str.len:
    let ch = str[i]
    if ind >= indent:
      result.add("\r\n")
      result.add(recordBlockLine(str, i))
      ind = 0
    else:
      case ch
      of Newlines: ind = 0
      of InlineWhitespace:
        inc ind
      else:
        dec i
        return
    inc i

proc recordColon(str: string, i: var int): string =
  while i < str.len:
    let ch = str[i]
    case ch
    of InlineWhitespace:
      discard
    of '"', '\'':
      return recordQuoted(str, i)
    of Newlines:
      var indent = 0
      inc i
      while i < str.len and str[i] in InlineWhitespace:
        inc indent
        inc i
      return recordBlock(str, indent, i)
    else:
      return recordBlockLine(str, i)
    inc i

proc recordElement(str: string, i: var int): Element =
  type State = enum start, attrs
  var
    state = start
  while i < str.len:
    let ch = str[i]
    case state
    of start:
      case ch
      of NameSet:
        result = Element(name: recordName(str, i))
        state = attrs
      of '#':
        recordComment(str, i)
      else:
        discard
    of attrs:
      case ch
      of NameSet:
        result.arguments.add(recordNamedArgument(str, i))
      of Newlines:
        return
      of ':', '=':
        inc i
        result.arguments.add((name: "", value: recordColon(str, i)))
        return
      of '"':
        result.arguments.add((name: "", value: recordQuoted(str, i)))
        return
      of ',', InlineWhitespace: discard
      of '#':
        recordComment(str, i)
        return
      else:
        echo "ignoring char ", ch
    inc i

proc parseInfo*(s: string): Info =
  var i = 0
  while i < s.len:
    let elem = recordElement(s, i)
    if not elem.isNil:
      result.elements.add(elem)
      case elem.name
      of "template": result.`template` = elem.body
      of "title": result.title = elem.body
      of "description": result.description = elem.body
      of "lazy": result.lazy = true
      else: discard
    inc i
