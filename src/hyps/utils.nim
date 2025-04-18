import std/[asyncdispatch, strbasics, strutils]

template `?=`*(exp1, exp2: untyped): untyped =
  if exp1 == nil:
    exp1 = exp2

iterator headersIt*(s: string): (Slice[int], Slice[int]) {.inline.} =
  ## Ported from hyperx
  let L = s.len
  var na = 0
  var nb = 0
  var va = 0
  var vb = 0
  while na < L:
    nb = na
    nb += int(s[na] == ':')  # pseudo-header
    nb = find(s, ':', nb)
    doAssert nb != -1
    assert s[nb] == ':'
    assert s[nb+1] == ' '
    va = nb+2  # skip :\s
    vb = find(s, '\r', va)
    doAssert vb != -1
    assert s[vb] == '\r'
    assert s[vb+1] == '\n'
    yield (na .. nb-1, va .. vb-1)
    doAssert vb+2 > na
    na = vb+2  # skip /r/n

func newStringRef*(s: sink string = ""): ref string =
  new result
  result[] = s

proc silent*(fut: Future[void]) {.async.} =
  if fut == nil:
    return
  try:
    await fut
  except CatchableError:
    discard

func addRecordSize(data: var string, n: Natural) {.raises: [].} =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let n = n.uint32
  data.add ((n shr 24) and 8.ones).char
  data.add ((n shr 16) and 8.ones).char
  data.add ((n shr 8) and 8.ones).char
  data.add (n and 8.ones).char

func addRecord*(s: var string, ch: string, msg: string) {.raises: [].} =
  s.addRecordSize(ch.len + msg.len + 2)
  s.add ch  # XXX escape \n
  s.add '\n'
  s.add msg  # XXX escape \n
  s.add '\n'

const prefixSize = 4

func recordSize(data: openArray[char]): int {.raises: [].} =
  doAssert data.len >= prefixSize
  var L = 0'u32
  L += data[0].uint32 shl 24
  L += data[1].uint32 shl 16
  L += data[2].uint32 shl 8
  L += data[3].uint32
  result = L.int

func hasFullRecord(data: openArray[char]): bool {.raises: [].} =
  if data.len < prefixSize:
    return false
  result = data.len >= prefixSize+data.recordSize

func delRecords*(data: var string) {.raises: [].} =
  let L = data.len-1
  var pos = 0
  while hasFullRecord toOpenArray(data, pos, L):
    pos += prefixSize + recordSize toOpenArray(data, pos, L)
  data.setSlice pos .. L

iterator records*(data: string): (Slice[int], Slice[int]) {.inline.} =
  let L = data.len-1
  var pos, next, chA, chB: int
  while hasFullRecord toOpenArray(data, pos, L):
    next += prefixSize + recordSize toOpenArray(data, pos, L)
    chA = prefixSize + pos
    chB = find(toOpenArray(data, chA, next-1), '\n')
    doAssert chB != -1
    chB += chA
    doAssert data[chB] == '\n'
    doAssert data[next-1] == '\n'
    doAssert next-1 >= chB+1
    yield (chA ..< chB, chB+1 ..< next-1)
    pos = next

iterator fullRecords*(data: string): (Slice[int], Slice[int]) {.inline.} =
  let L = data.len-1
  var pos, next, chA, chB: int
  while hasFullRecord toOpenArray(data, pos, L):
    next += prefixSize + recordSize toOpenArray(data, pos, L)
    chA = prefixSize + pos
    chB = find(toOpenArray(data, chA, next-1), '\n')
    doAssert chB != -1
    chB += chA
    doAssert data[chB] == '\n'
    doAssert data[next-1] == '\n'
    doAssert next-1 >= pos
    yield (chA ..< chB, pos ..< next)
    pos = next

when isMainModule:
  import std/sequtils
  block:
    doAssert "\x00\x00\x00\x00".recordSize == 0
    doAssert "\x00\x00\x00\x01".recordSize == 1
    doAssert "\x00\x00\x00\x02".recordSize == 2
    doAssert "\x00\x00\x01\x00".recordSize == (1 shl 8)
    doAssert "\x00\x01\x00\x00".recordSize == (1 shl 16)
    doAssert "\x01\x00\x00\x00".recordSize == (1 shl 24)
    doAssert "\x00\x00\x00\x00\x01\x01\x01".recordSize == 0
    doAssert "\x00\x00\x00\x01\x01\x01\x01".recordSize == 1
    doAssert "\x00\x00\x00\x02\x01\x01\x01".recordSize == 2
    doAssertRaises AssertionDefect:
      discard "\x00\x00\x00".recordSize
    doAssertRaises AssertionDefect:
      discard "".recordSize
  block:
    doAssert "\x00\x00\x00\x00".hasFullRecord
    doAssert "\x00\x00\x00\x00\x00".hasFullRecord
    doAssert "\x00\x00\x00\x01\x00".hasFullRecord
    doAssert "\x00\x00\x00\x02\x00\x00".hasFullRecord
    doAssert not "\x00\x00\x00\x02\x00".hasFullRecord
    doAssert not "\x00\x00\x00\x03\x00\x00".hasFullRecord
    doAssert not "\x00\x00\x00".hasFullRecord
    doAssert not "".hasFullRecord
    doAssert not "\x00\x00\x00\x01".hasFullRecord
    doAssert not "\x00\x00\x01\x00".hasFullRecord
  block:
    proc delRecords(s: string): string =
      result = s
      delRecords result
    doAssert delRecords("\x00\x00\x00\x00") == ""
    doAssert delRecords("\x00\x00\x00\x00" & "\x00\x00\x00\x00") == ""
    doAssert delRecords("\x00\x00\x00\x00" & "\x11") == "\x11"
    doAssert delRecords("\x00\x00\x00\x01\x11") == ""
    doAssert delRecords("\x00\x00\x00\x02\x11\x11") == ""
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x22") == "\x22"
    doAssert delRecords("\x00\x00\x00") == "\x00\x00\x00"
    doAssert delRecords("\x00\x00") == "\x00\x00"
    doAssert delRecords("\x00") == "\x00"
    doAssert delRecords("") == ""
    doAssert delRecords("\x00\x00\x00\x01") == "\x00\x00\x00\x01"
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x00\x00\x00\x01\x11") == ""
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x00\x00\x00\x01\x11" & "\x22") == "\x22"
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x00\x00\x00") == "\x00\x00\x00"
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x00\x00") == "\x00\x00"
    doAssert delRecords("\x00\x00\x00\x01\x11" & "\x00") == "\x00"
  block:
    proc withSize(n: int): string =
      result = ""
      result.addRecordSize n
    doAssert withSize(0) == "\x00\x00\x00\x00"
    doAssert withSize(1) == "\x00\x00\x00\x01"
    doAssert withSize(2) == "\x00\x00\x00\x02"
    doAssert withSize(1 shl 8) == "\x00\x00\x01\x00"
    doAssert withSize(1 shl 16) == "\x00\x01\x00\x00"
    doAssert withSize(1 shl 24) == "\x01\x00\x00\x00"
  block:
    proc record(s: string): string =
      result = ""
      result.addRecordSize s.len
      result.add s
    proc recordSeq(s: string): seq[(string, string)] =
      for (ch, msg) in records s:
        result.add (s[ch], s[msg])
    doAssert toSeq(records("\x00\x00\x00\x04" & "a\nb\n")) == @[(4 .. 4, 6 .. 6)]
    doAssert toSeq(records "\x00\x00\x00") == @[]
    doAssert toSeq(records "\x00\x00") == @[]
    doAssert toSeq(records "\x00") == @[]
    doAssert toSeq(records "") == @[]
    doAssertRaises AssertionDefect:
      discard toSeq(records "\x00\x00\x00\x00")
    doAssert recordSeq("channel\nmessage\n".record) == @[("channel", "message")]
    doAssert recordSeq("a\nb\n".record) == @[("a", "b")]
    doAssert recordSeq("\n\n".record) == @[("", "")]
    doAssert recordSeq("a\n\n".record) == @[("a", "")]
    doAssert recordSeq("\nb\n".record) == @[("", "b")]
    doAssert recordSeq("a\nb\n".record & "c\nd\n".record) == @[("a", "b"), ("c", "d")]
    doAssert recordSeq("foo\nbar\n".record & "baz\nquz\n".record & "qux\nquux\n".record) ==
      @[("foo", "bar"), ("baz", "quz"), ("qux", "quux")]
    doAssert recordSeq("a\nb\n".record & "\x00") == @[("a", "b")]
    doAssert recordSeq("a\nb\n".record & "\x00\x00") == @[("a", "b")]
    doAssert recordSeq("a\nb\n".record & "\x00\x00\x00") == @[("a", "b")]
    doAssertRaises AssertionDefect:
      discard recordSeq("a\nb".record)
    doAssertRaises AssertionDefect:
      discard recordSeq("a\n".record)
    doAssertRaises AssertionDefect:
      discard recordSeq("a".record)
    doAssertRaises AssertionDefect:
      discard recordSeq("".record)
    doAssertRaises AssertionDefect:
      discard recordSeq("a\nb\n".record & "".record)
  echo "ok"
