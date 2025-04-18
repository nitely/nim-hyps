import std/[asyncdispatch]
import ../src/hyps/client
import ./utils

template testAsync(name: string, body: untyped): untyped =
  (proc () =
    echo "test " & name
    var checked = false
    proc test {.async.} =
      body
      checked = true
    discard getGlobalDispatcher()
    waitFor test()
    doAssert not hasPendingOperations()
    doAssert checked
  )()

proc sleepCycle: Future[void] =
  let fut = newFuture[void]()
  proc wakeup = fut.complete()
  callSoon wakeup
  return fut

testAsync "publish 1 msg":
  var checked = 0
  let pb = newPubsub(localHost, localPort)
  with pb:
    let sub = newSubscriber()
    await pb.subscribe(sub, @["foo_ch"])
    await pb.publish("foo_ch", "foo_msg")
    await pb.readMessages(sub)
    let msg = "foo_ch\nfoo_msg\n"
    doAssert sub.messages == toSize(msg.len) & msg
    inc checked
  doAssert checked == 1

testAsync "publish many msgs":
  var checked = 0
  let pb = newPubsub(localHost, localPort)
  with pb:
    let sub = newSubscriber()
    await pb.subscribe(sub, @["foo_ch"])
    await pb.publish("foo_ch", "foo_msg0")
    await pb.publish("foo_ch", "foo_msg1")
    await pb.publish("foo_ch", "foo_msg2")
    let msgs = await pb.readMessages(sub, 3)
    let msgSize = toSize "foo_ch\nfoo_msgX\n".len
    doAssert msgs ==
      msgSize & "foo_ch\nfoo_msg0\n" &
      msgSize & "foo_ch\nfoo_msg1\n" &
      msgSize & "foo_ch\nfoo_msg2\n"
    inc checked
  doAssert checked == 1

testAsync "publish to many channels":
  var checked = 0
  let pb = newPubsub(localHost, localPort)
  with pb:
    let sub = newSubscriber()
    await pb.subscribe(sub, @["foo_ch1"])
    await pb.subscribe(sub, @["foo_ch2"])
    await pb.publish("foo_ch1", "foo_msg0")
    await pb.publish("foo_ch2", "foo_msg1")
    let msgs = await pb.readMessages(sub, 2)
    let msgSize = toSize "foo_chX\nfoo_msgX\n".len
    doAssert msgs ==
      msgSize & "foo_ch1\nfoo_msg0\n" &
      msgSize & "foo_ch2\nfoo_msg1\n"
    inc checked
  doAssert checked == 1

testAsync "publish to many channels with many subs":
  var checked = 0
  let pb = newPubsub(localHost, localPort)
  with pb:
    let sub1 = newSubscriber()
    let sub2 = newSubscriber()
    await pb.subscribe(sub1, @["foo_ch1"])
    await pb.subscribe(sub2, @["foo_ch2"])
    await pb.publish("foo_ch1", "foo_msg0")
    await pb.publish("foo_ch2", "foo_msg1")
    await pb.readMessages(sub1)
    await pb.readMessages(sub2)
    let msgSize = toSize "foo_chX\nfoo_msgX\n".len
    doAssert sub1.messages == msgSize & "foo_ch1\nfoo_msg0\n"
    doAssert sub2.messages == msgSize & "foo_ch2\nfoo_msg1\n"
    inc checked
  doAssert checked == 1

testAsync "publish to 1 channel with many subs":
  var checked = 0
  let pb = newPubsub(localHost, localPort)
  with pb:
    let sub1 = newSubscriber()
    let sub2 = newSubscriber()
    await pb.subscribe(sub1, @["foo_ch"])
    await pb.subscribe(sub2, @["foo_ch"])
    await pb.publish("foo_ch", "foo_msg0")
    await pb.readMessages(sub1)
    await pb.readMessages(sub2)
    let msg = "foo_ch\nfoo_msg0\n"
    doAssert sub1.messages == toSize(msg.len) & msg
    doAssert sub2.messages == toSize(msg.len) & msg
    inc checked
  doAssert checked == 1

testAsync "publish to many clients":
  var checked = 0
  let pb1 = newPubsub(localHost, localPort)
  let pb2 = newPubsub(localHost, localPort)
  with pb1:
    with pb2:
      let sub1 = newSubscriber()
      let sub2 = newSubscriber()
      await pb1.subscribe(sub1, @["foo_ch"])
      await pb2.subscribe(sub2, @["foo_ch"])
      await pb1.publish("foo_ch", "foo_msg0")
      await pb2.publish("foo_ch", "foo_msg1")
      let msgs1 = await pb1.readMessages(sub1, 2)
      let msgs2 = await pb2.readMessages(sub2, 2)
      let msgSize = toSize "foo_ch\nfoo_msgX\n".len
      doAssert msgs1 ==
        msgSize & "foo_ch\nfoo_msg0\n" &
        msgSize & "foo_ch\nfoo_msg1\n"
      doAssert msgs2 ==
        msgSize & "foo_ch\nfoo_msg0\n" &
        msgSize & "foo_ch\nfoo_msg1\n"
      inc checked
  doAssert checked == 1
