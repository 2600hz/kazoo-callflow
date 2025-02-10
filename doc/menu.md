# Menu

Menus, also known as IVRs allow you to create branches in the callflow based on the caller's input.

## Overview

Menus essentially play a prompt, then branch based on caller DTMF input. The actual `menu` callflow
has just two options because Menus are managed separately, created and updated by
[API](https://docs.2600hz.com/git/2600hz/crossbar/doc/menus.md).


## Using the Menu module

The DTMF entered is matched against the "children" keys and that branch is taken.

Additionally, `menu` will use the branch keyed `timeout` when the `timeout` is 
reached. Please note this `timeout` value is from the `menu` doc, not the 
`interdigit_timeout` option in the `menu` callflow.

```json
{
    "module":"menu",
    "data": {
        "id": "{MENU ID}"
    },
    "children": {
        "1": {"module":"...",...},
        "2": {"module":"...",...},
        "timeout": {"module":"...",...}
    }
}
```

If no `timeout` child is specified, the menu is retried (until retries are exceeded).

#### Schema

Validator for the menu callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | Menu ID to use | `string()` |   | `false` 
`interdigit_timeout` | Amount of time, in milliseconds, to wait between keypresses | `integer()` |   | `false` 
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` 


#### Menu Options

These options are configured by [API](https://docs.2600hz.com/git/2600hz/crossbar/doc/menus.md).


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`allow_record_from_offnet` | Determines if the record pin can be used by external calls | `boolean()` | `false` | `false` | `supported`
`branch_extension` | Whether or not to branch extension when caller dials an extension. If true, when caller dials an extension, call will be branched, once that branch finishes if menu has a default action set, that action will be executed | `boolean()` | `true` | `false` | `supported`
`flags.[]` |   | `string()` |   | `false` | `supported`
`flags` | Flags set by external applications | `array(string())` |   | `false` | `supported`
`hunt` | Determines if the callers can dial internal extensions directly | `boolean()` | `true` | `false` | `supported`
`hunt_allow` | A regular expression that an extension the caller dialed must match to be allowed to continue | `string(1..256)` |   | `false` | `supported`
`hunt_deny` | A regular expression that if matched does not allow the caller to dial directly | `string(1..256)` |   | `false` | `supported`
`interdigit_timeout` | The amount of time (in milliseconds) to wait for the caller to press the next digit after pressing a digit | `integer(1..10000)` |   | `false` | `supported`
`max_extension_length` | The maximum number of digits that can be collected | `integer(1..6)` | `4` | `false` | `supported`
`media.exit_media` | When a call is transferred from the menu after all retries exhausted this media can be played (prior to transfer if enabled) | `boolean() | string(3..2048)` |   | `false` | `supported`
`media.greeting` | The ID of a media object that should be used as the menu greeting | `string(3..2048)` |   | `false` | `supported`
`media.invalid_media` | When the collected digits don't result in a match or hunt this media can be played | `boolean() | string(3..2048)` |   | `false` | `supported`
`media.transfer_media` | When a call is transferred from the menu, either after all retries exhausted or a successful hunt, this media can be played | `boolean() | string(3..2048)` |   | `false` | `supported`
`media` | The media (prompt) parameters | `object()` | `{}` | `false` | `supported`
`name` | A friendly name for the menu | `string(1..128)` |   | `true` | `supported`
`record_pin` | The pin number used to record the menu prompt | `string(3..6)` |   | `false` | `supported`
`retries` | The number of times a menu should be played until a valid entry is collected | `integer(1..10)` | `3` | `false` | `supported`
`suppress_media` | Determines if the playing of 'Invalid Entry' is suppressed. | `boolean()` | `false` | `false` | `supported`
`timeout` | The amount of time (in milliseconds) to wait for the caller to begin entering digits | `integer(1..60000)` |   | `false` | `supported`
