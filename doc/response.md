# Response

Return a custom SIP response to the caller


## Hangups

Sometimes it is necessary to respond to a call with a hangup cause and code. For extra fun, some phones will display the hangup cause on the display, which can be a source of amusement. For instance, for a while {% BRAND_NAME %} would return a "403 Insert Coin" if the account was out of money.

Optionally, response can play media to the caller before hanging up.

#### Schema

Validator for the Response callflow action



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`code` | The SIP Hangup code to respond with | `integer()` | `486` | `true` |  
`media` | Optional media file to play before responding with the hangup code/cause | `string(0..2048)` |   | `false` |  
`message` | The SIP Hangup cause to respond with | `string()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  


## Example

```json
{
    "module": "response",
    "data": {
        "code": "486",
        "message": "User Busy",
        "media":"id_or_url"
    }
}
```
