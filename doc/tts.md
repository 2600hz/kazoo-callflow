# TTS

Speak in calls with text-to-speech

## About TTS

Speak in calls automatically using tts engines. In order to use tts, the account must have an engine configured. {% BRAND_NAME %} has Flite configured out of the box. For different engines, see 
[this tutorial](https://docs.2600hz.com/git/2600hz/docs-sysadmin/doc/config/adding-ispeech-tts.md) for adding a tts engine.

#### Schema

Validator for the TTS (Text-to-speech) callflow action



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`endless_playback` | Loop the media until canceled | `boolean()` |   | `false` |  
`engine` | What TTS engine to use | `string('flite' \| 'google' \| 'ispeech' \| 'voicefabric')` |   | `false` |  
`language` | The language of the speaker | `string()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`terminators.[]` |   | `string()` |   | `false` |  
`terminators` | What DTMF can terminate playback of the audio | `array(string())` | `["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]` | `false` |  
`text` | The text to speak | `string(1..1000)` |   | `true` |  
`voice` | What voice to use when speaking the text | `string()` | `female` | `false` |  



### Examples

This example will use the default TTS engine to speak the text and then hang up.
```
{
    "module": "tts",
    "data": {
        "text": "Pivot is pretty awesome. Have a great day."
    }
}
```