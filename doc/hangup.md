## Hangup

Hangup with a cause and code.

### About Hangup

Sometimes it is necessary to respond to a call with a hangup cause and code. For extra fun, some phones will display the hangup cause on the display, which can be a source of amusement. For instance, for a while {% BRAND_NAME %} would return a "403 Insert Coin" if the account was out of money.

#### Schema

Validator for the hangup callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  



