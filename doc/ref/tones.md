## Tones

### About Tones

#### Schema

Validator for the tones callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`tones.[].duration_off` | duration, in milliseconds, for tone to be off | `integer()` |   | `true` |  
`tones.[].duration_on` | duration, in milliseconds, for the tone to be on | `integer()` |   | `true` |  
`tones.[].frequencies` | list of Frequencies to play | `array(integer())` |   | `true` |  
`tones.[].repeat` | How many times to loop the tones | `integer()` |   | `false` |  
`tones.[].volume` | Volume, in dB. 0 = max, negative = quieter | `integer()` |   | `false` |  
`tones` |   | `array(object())` |   | `false` |  



