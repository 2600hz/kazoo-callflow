## Doorman

### About Doorman

#### Schema

Validator for the doorman callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`call_timeout` | How long to ring the callee | `integer()` | `30` | `false` |  
`caller_id_name` | Custom Caller ID Name to denote the doorman is calling | `string()` | `Doorman` | `false` |  
`id` | The KAZOO device or user ID | `string()` |   | `false` |  
`origin` | Read-only setting if the call is recorded |   | `callflow : cf_doorman` | `false` |  
`recording_limit` | The caller's recording limit for name and reason for calling | `integer()` | `8` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`tones` | Ring tone to play to the caller after recording their name | `array([#/definitions/tone](#tone))` |   | `false` |  
`vmbox_id` | Voicemail box ID to send caller to if callee choses | `string()` |   | `false` |  

### tone

Validator for a teletone config


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`duration_off` | duration, in milliseconds, for tone to be off | `integer()` |   | `true` |  
`duration_on` | duration, in milliseconds, for the tone to be on | `integer()` |   | `true` |  
`frequencies` | list of Frequencies to play | `array(integer())` |   | `true` |  
`repeat` | How many times to loop the tones | `integer()` |   | `false` |  
`volume` | Volume, in dB. 0 = max, negative = quieter | `integer()` |   | `false` |  



