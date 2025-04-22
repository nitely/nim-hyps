import std/[asyncdispatch, tables]
import pkg/hyperx/[client, signal]
from pkg/hyperx/clientserver import close
import ./[clientserver, utils, errors]

export
  records,
  fullRecords,
  Subscriber,
  newSubscriber,
  hash

type Buff = ref object
  data: ref string
  signal, ackSignal: SignalAsync
  count, ack: int

proc initBuff: Buff =
  Buff(
    data: new string,
    signal: newSignal(),
    ackSignal: newSignal(),
    count: 0,
    ack: 0,
  )

proc add(buff: var Buff, ch, msg: string) =
  buff.data[].addRecord(ch, msg)
  inc buff.count

proc add(buff: var Buff, ch: string) =
  buff.data[].addRecord(ch, "")
  inc buff.count

proc close(buff: Buff) =
  buff.signal.close()
  buff.ackSignal.close()

type Pubsub* = ref object
  client: ClientContext
  channels: Channels
  subscriberFut, publisherFut, dispFut: Future[void]
  pubBuff, subBuff: Buff
  error: ref HypsError

proc newPubsub*(host: string, port: Port, ssl: static[bool] = false): Pubsub =
  Pubsub(
    client: newClient(host, port, ssl),
    channels: newChannels(),
    pubBuff: initBuff(),
    subBuff: initBuff(),
    publisherFut: nil,
    dispFut: nil
  )

proc close(pb: Pubsub) =
  pb.channels.close()
  pb.pubBuff.close()
  pb.subBuff.close()
  pb.client.close()

proc readMessages*(pb: Pubsub, sub: Subscriber) {.async.} =
  ## Wait for one or more messages to be available
  ## in `sub.messages`. Raises `HypsError` if the pubsub is closed.
  try:
    while sub.messages.len == 0:
      await sub.signal.waitFor()
  except SignalClosedError:
    if pb.error != nil:
      raise newHypsError(pb.error.msg)
    raise

proc readMessages*(pb: Pubsub, sub: Subscriber, i: int): Future[string] {.async.} =
  ## Returns at least `i` messages and clears `sub.messages`.
  ## Raises `HypsError` if the pubsub is closed.
  var count = 0
  result = ""
  while count < i:
    await pb.readMessages(sub)
    for (ch, record) in fullRecords sub.messages:
      result.add sub.messages[record]
      inc count
    sub.messages.setLen 0

proc sender(pb: Pubsub, pbBuff: Buff, path: string) {.async.} =
  var buff = new string
  buff[] = ""
  let headers = @[
    (":method", "POST"),
    (":scheme", "https"),
    (":path", path),
    (":authority", pb.client.hostname)
  ]
  try:
    let strm = pb.client.newClientStream()
    with strm:
      await strm.sendHeaders(headers, finish = false)
      await strm.recvHeaders buff
      while pb.client.isConnected:
        while pbBuff.data[].len == 0:
          await pbBuff.signal.waitFor()
        swap buff, pbBuff.data
        pbBuff.data[].setLen 0
        await strm.sendBody(buff, finish = false)
        # XXX recv Ack's async
        buff[].setLen 0
        await strm.recvBody buff
        pbBuff.ack += buff[].len
        pbBuff.ackSignal.trigger()
  except HyperxError as err:
    pb.error ?= newHypsError(err.msg)
    raise
  finally:
    #echo "sender_exit " & path
    pb.close()

proc publisher(pb: Pubsub): Future[void] =
  sender(pb, pb.pubBuff, "/publish")

proc publish*(pb: Pubsub, ch, msg: string) {.async.} =
  ## Publish message to channel. The channel cannot contain new lines `\n`.
  ## Raises `HypsError` if the pubsub is closed.
  doAssert '\n' notin ch
  try:
    pb.pubBuff.add(ch, msg)
    pb.pubBuff.signal.trigger()
    let count = pb.pubBuff.count
    while pb.pubBuff.ack < count:
      await pb.pubBuff.ackSignal.waitFor()
  except SignalClosedError:
    if pb.error != nil:
      raise newHypsError(pb.error.msg)
    raise

proc subscriber(pb: Pubsub): Future[void] =
  sender(pb, pb.subBuff, "/subscribe")

proc subscribe*(pb: PubSub, sub: Subscriber, chs: seq[string]) {.async.} =
  ## Subscribe to one or more channels.
  ## Raises `HypsError` if the pubsub is closed.
  for ch in chs:
    pb.channels.subTo(sub, ch)
    pb.subbuff.add ch
  try:
    pb.subBuff.signal.trigger()
    let count = pb.subBuff.count
    while pb.subBuff.ack < count:
      await pb.subBuff.ackSignal.waitFor()
  except SignalClosedError:
    pb.channels.close sub
    if pb.error != nil:
      raise newHypsError(pb.error.msg)
    raise

proc dispatch(pb: Pubsub, data: string) =
  for (ch, record) in fullRecords data:
    let subs = pb.channels.getOrDefault(data[ch])
    for sub in subs:
      if sub.messages.len < 64 * 1024:
        #toOpenArray(data, record.a, record.b)
        sub.messages.add data[record]
        sub.signal.trigger()

proc dispatcher(pb: Pubsub) {.async.} =
  let headers = @[
    (":method", "GET"),
    (":scheme", "https"),
    (":path", "/messages"),
    (":authority", pb.client.hostname)
  ]
  try:
    let strm = pb.client.newClientStream()
    with strm:
      await strm.sendHeaders(headers, finish = true)
      var data = new string
      await strm.recvHeaders data
      data[].setLen 0
      while not strm.recvEnded:
        await strm.recvBody data
        pb.dispatch data[]
        delRecords data[]
  except HyperxError as err:
    pb.error ?= newHypsError(err.msg)
    raise
  finally:
    pb.close()

proc connect*(pb: Pubsub) {.async.} =
  discard getGlobalDispatcher()
  await pb.client.connect()
  pb.subscriberFut = pb.subscriber()
  pb.publisherFut = pb.publisher()
  pb.dispFut = pb.dispatcher()

proc shutdown*(pb: Pubsub) {.async.} =
  pb.close()
  await silent pb.subscriberFut
  await silent pb.publisherFut
  await silent pb.dispFut
  await pb.client.shutdown()

template with*(pb: Pubsub, body: untyped): untyped =
  doAssert not pb.client.isConnected
  try:
    await pb.connect()
    body
  finally:
    await pb.shutdown()
