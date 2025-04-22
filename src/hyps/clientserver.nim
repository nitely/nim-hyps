import std/[tables, sets, hashes]
import pkg/hyperx/[signal]

export sets

type Subscriber* = ref object
  signal*: SignalAsync
  messages*: string
  channels: seq[string]

proc newSubscriber*: Subscriber {.raises: [].} =
  Subscriber(signal: newSignal(), messages: "", channels: @[])

proc close(sub: Subscriber) {.raises: [].} =
  sub.signal.close()

proc hash*(sub: Subscriber): Hash {.raises: [].} =
  hash(addr sub[])

type Channels* = TableRef[string, HashSet[Subscriber]]

proc newChannels*: Channels {.raises: [].} =
  newTable[string, HashSet[Subscriber]]()

proc subTo*(chs: Channels, sub: Subscriber, ch: string) =#{.raises: [].} =
  ## Subscribe ``sub`` to ``ch`` channel
  if sub.signal.isClosed:
    return
  if sub notin chs.getOrDefault(ch):
    sub.channels.add ch
  chs.mgetOrPut(ch).incl sub

proc close*(chs: Channels, sub: Subscriber) {.raises: [].} =
  sub.close()
  for ch in sub.channels:
    chs.mgetOrPut(ch).excl sub
    if chs.getOrDefault(ch).len == 0:
      chs.del ch

proc close*(chs: Channels) {.raises: [].} =
  for subs in values chs:
    for sub in subs:
      sub.close()
  chs.clear()
