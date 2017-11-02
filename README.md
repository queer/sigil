# sigil

Simple distributed gateway/controller. WIP

## Configuration

The following env. vars. are expected
```
ETCD_URL=http://1.2.3.4:2379
```

## Gateway ops

The gateway supports the following operations:
```
0: HEARTBEAT
{
  op: 0,
  d: {
    id: "1111-22-3-44444444",
    bot_name: "memes",
    shard: 42
  }
}

1: DISPATCH
{
  op: 1,
  t: "EVENT_TYPE",
  d: {
    # whatever data goes here
  }
}

2: BROADCAST_DISPATCH
{
  op: 2,
  d: {
    # whatever data goes here
  }
}
```
 
Note that with OP1, the `t` field is REQUIRED, and must be correctly handled by clients

`DISPATCH` gateway events are sent with a type of `protocol:event`, ex. `discord:shard`

`BROADCAST_DISPATCH` messages are meant for broadcasting to clients of a specific type; an opcode needs to be added for gateway-internal broadcasts

Additionally, the gateway expects the following channel-specific data when connecting:

```
# sigil:gateway:discord
{
  id: "1234-whatever",
  # Allow us to differentiate between bots and have many bots hooked up to one gateway setup
  bot_name: "super-shiny-bot"
}
```

Discord shard allocation looks something like:

```
{
  op: 1,
  t: "discord:shard",
  d: {
    bot_name: "fancy bot",
    id: "1-2-3-4",
    shard_count: 2
  }
}
```

## Commentary

### This is Elixir, why are you not using nodes like a nice human?

While it would be nice to be able to do that, I'm using websockets instead of Elixir node communication mainly just so that there's no *requirement* for parts of the stack being written in non-Elixir languages. Gateway nodes communicate with each other through `eden`, but external nodes use websockets. 