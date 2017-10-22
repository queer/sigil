# SigilGateway

Gateway for sigil applications.

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
    id: "1111-22-3-44444444"
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
```
 
Note that with OP1, the `t` field is REQUIRED, and must be correctly handled by clients

`DISPATCH` gateway events are sent with a type of `protocol:event`, ex. `discord:shard`

Additionally, the gateway expects the following channel-specific data when connecting:

```
# sigil:gateway:discord
{
  id: "1234-whatever",
  # Allow us to differentiate between bots and have many bots hooked up to one gateway
  bot_name: "super-shiny-bot"
}
```