# Hyps

Hyps is an async pub/sub client and server.

> [!WARNING]
> This is Work In Progress; APIs are not stable and will change in patch versions without deprecation.

## What

This pub/sub offers:

- Concurrent subscriptions, publishing, and receiving messages over one single connection through multiplexing.
- Creating one or more subscriptions to any and many channels using one connection. Which allows a client instance to handle many subscriptions using one connection.
- Automatic batching/pipelining for all operations.
- At most once delivery. A message may not be received if messages are produced much faster than they are consumed; there is a buffer that will eventually fill up and start dropping messages.
- Subscriptions and published messages are ACKed. This means there is no fire and forget without knowing if an operation succeeded or not.
- Received messages are ordered in the published order.
- No persistence. Messages are only delivered to subscribers who are actively connected at the time the message is published.
- No message delivery retrying. Messages are realtime only.

If you care about receving all messages, you may store them in a persistent storage on your own before publish, detect when there is a gap in the received messages, and fetch them from storage. Alternatively use a *log/stream* (kafka, redis streams, etc) instead of a pub/sub, which makes other trade-offs.

## Refc only

For now this only supports refc and so it requires compiling with `--mm:refc`. The `--mm:orc` cycle collector is not supported for now. Pls, do not open issues related to orc.

## Message format

The messages are batched/concatenated in `len(msg) & "channel_name\n" & "message\n"` format. The first 4 bytes contain the rest of the message length. This detail can be used for performance reasons.

## Usage

Server:

```nim
import std/asyncdispatch
import hyps/server

proc main {.async.} =
  echo "Serving forever"
  await serve("127.0.0.1", Port 8787)

waitFor main()
```

^make sure not to start more than one server instance; which is allowed at the moment but it should not.

Client:

```nim
import std/sequtils
import std/asyncdispatch
import hyps/client

proc main {.async.} =
  let pb = newPubsub("127.0.0.1", Port 8787)
  with pb:
    let sub = newSubscriber()
    await pb.subscribe(sub, @["foo_ch"])
    await pb.publish("foo_ch", "foo_msg")
    await pb.readMessages(sub)
    doAssert sub.messages == "\x00\x00\x00\x0Ffoo_ch\nfoo_msg\n"
    doAssert toSeq(sub.messages.records) == @[("foo_ch", "foo_msg")]
    sub.messages.setLen 0  # clear buffer

waitFor main()
```

Use `await pf.connect()` and `await pf.shutdown()` instead of `with` for unstructured programming.

## Proper usage

For servers using this library:

- Create one pub/sub client instance per server instance.
- Create one subscription per user connecting (usually through SSE or WS) to the server.
- Use the subscription for subscribing to channels and receiving messages.
- Use the pub/sub client instance to send messages.

## Prolog, httpx, etc

These web frameworks (AFAIK) don't play nice with structured programming. The way you would use this library is probably using a `{.threadvar.}` to store the `newPubsub` result and `connect/shutdown` on first usage initialization. Then use a single pub/sub connection per server instance, which is fine. Do not use a global var, since that get shared per server instance (thread); yes, prolog/httpx starts an event-loop per CPU by default.

I'll try to provide examples later, but PRs are welcome.

## Sync usage

Using `waitFor` to make this library API (subscribe, publish, etc) synchronous won't work as expected. This is not supported, and it won't be supported either.

## LICENSE

MIT
