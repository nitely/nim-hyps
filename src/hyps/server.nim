import std/[asyncdispatch, tables, sets, hashes]
import pkg/hyperx/[server, signal, errors]
import ./utils

type Subscriber = ref object
  signal: SignalAsync
  messages: string
  channels: seq[string]

proc newSubscriber: Subscriber {.raises: [].} =
  Subscriber(signal: newSignal(), messages: "", channels: @[])

proc close(sub: Subscriber) {.raises: [].} =
  sub.signal.close()

proc hash(sub: Subscriber): Hash =
  hash(addr sub[])

type Channels = ref object
  t: Table[string, HashSet[Subscriber]]

proc newChannels: Channels {.raises: [].} =
  Channels(t: initTable[string, HashSet[Subscriber]]())

proc close(chs: Channels, sub: Subscriber) {.raises: [].} =
  try:
    for ch in sub.channels:
      if ch in chs.t:
        chs.t[ch].excl sub
        if chs.t[ch].len == 0:
          chs.t.del ch
  except KeyError as err:
    doAssert false

proc publish(strm: ClientStream, chs: Channels) {.async.} =
  await strm.sendHeaders(@[(":status", "200")], finish = false)
  let data = newStringRef()
  let acks = newStringRef()
  while not strm.recvEnded:
    await strm.recvBody data
    acks[].setLen 0
    for (ch, record) in fullRecords data[]:
      acks[].add 'k'
      for sub in chs.t.getOrDefault data[ch]:
        if sub.messages.len < 64 * 1024:
          sub.messages.add data[record]
          sub.signal.trigger()
    delRecords data[]
    await strm.sendBody(acks, finish = false)

proc subscribe(strm: ClientStream, sub: Subscriber, chs: Channels) {.async.} =
  await strm.sendHeaders(@[(":status", "200")], finish = false)
  let data = newStringRef()
  let acks = newStringRef()
  while not strm.recvEnded:
    await strm.recvBody data
    for (ch, msg) in records data[]:
      if data[ch] notin chs.t:
        chs.t[data[ch]] = initHashSet[Subscriber](0)
      chs.t[data[ch]].incl sub
      sub.channels.add data[ch]
      acks[].add 'k'
    delRecords data[]
    await strm.sendBody(acks, finish = false)
    acks[].setLen 0
  data[].setLen 0
  await strm.sendBody(data, finish = true)

proc messages(strm: ClientStream, sub: Subscriber) {.async.} =
  doAssert strm.recvEnded
  await strm.sendHeaders(@[(":status", "200")], finish = false)
  var data = newStringRef()
  while true:
    if sub.signal.len > 0:
      return
    while sub.messages.len == 0:
      await sub.signal.waitFor()
    data[].setLen 0
    data[].add sub.messages
    sub.messages.setLen 0
    await strm.sendBody(data, finish = false)

proc getPath(headers: string): string {.raises: [].} =
  result = ""
  for (k, v) in headersIt headers:
    if toOpenArray(headers, k.a, k.b) == ":path":
      return headers[v]

proc router(strm: ClientStream, sub: Subscriber, chs: Channels) {.async.} =
  try:
    let data = newStringRef()
    await strm.recvHeaders data
    case data[].getPath()
    of "/publish":
      await publish(strm, chs)
    of "/subscribe":
      await subscribe(strm, sub, chs)
    of "/messages":
      await messages(strm, sub)
    else:
      await strm.sendHeaders(@[(":status", "404")], finish = true)
  finally:
    await silent strm.cancel(hyxCancel)

proc onNewClient(client: ClientContext, chs: Channels): StreamCallback =
  let sub = newSubscriber()
  client.onClose proc =
    chs.close sub
    sub.close()
  proc (strm: ClientStream): Future[void] =
    router(strm, sub, chs)

proc onNewServer(server: ServerContext): ClientCallback =
  let chs = newChannels()
  proc (client: ClientContext): StreamCallback =
    onNewClient(client, chs)

proc serve*(host: string, port: Port): Future[void] =
  let server = newServer(host, port, ssl = false)
  return server.serve onNewServer
