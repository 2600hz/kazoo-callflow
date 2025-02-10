## Send Dtmf

### About Send Dtmf

Sending DTMF to the caller is sometimes necessary (automating IVR navigation, perhaps). Use the `send_dtmf` callflow to do so.

#### Schema

Validator for the Send DTMF callflow action



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`digits` | String of DTMF tones to send | `string()` |   | `true` |  
`duration_ms` | How long, in milliseconds, to send each DTMF | `integer() | string()` | `2000` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  

## Example

```json
{
    "module": "send_dtmf",
    "data": {
        "digits": "123ABC#",
        "duration_ms": 2000
    },
    "children": {}
}
```

* `digits` is a string of DTMF to send.
* `duration_ms` is how long of a tone to send each DTMF (and optional)

The above example would send "1", "2", "3", "A", "B", "C", and finally "#", each as 2 second tones.