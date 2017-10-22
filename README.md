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
