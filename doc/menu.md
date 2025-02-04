# Menu

## About Menu

Also known as IVR. Play a prompt and branch based on caller DTMF. Menus are configured by 
[API](https://docs.2600hz.com/git/2600hz/crossbar/doc/menus.md). In a flow, configured menus
are used with the 'id' key.

#### Schema

Validator for the menu callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | Menu ID to use | `string()` |   | `false` |  
`interdigit_timeout` | Amount of time, in milliseconds, to wait between keypresses | `integer()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  



