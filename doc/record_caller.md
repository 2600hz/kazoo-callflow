## Record Caller

### About Record Caller

Record the media stream, sending it to a configured URL on call completion. To record both caller
and callee, use [record call](./record_call.md).

#### Schema

Record the caller's audio stream



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`format` | What format to store the recording on disk | `string('mp3' \| 'wav')` |   | `false` |  
`media_id` | Doc ID of the created recording - if unspecified, {% BRAND_NAME %} will generate one | `string()` |   | `false` |  
`media_name` | the name of media | `string()` |   | `false` |  
`method` | HTTP verb to use when sending the recording to the supplied URL | `string('put' \| 'post')` | `put` | `false` |  
`origin` | How the recording was started | `string()` |   | `false` |  
`record_min_sec` | The minimum length, in seconds, the recording must be to be considered successful. Otherwise it is deleted | `integer()` |   | `false` |  
`record_on_answer` | Whether to delay the recording until the channel is answered | `boolean()` | `false` | `false` |  
`record_on_bridge` | Whether to delay the recording until the channel is bridged | `boolean()` | `false` | `false` |  
`record_sample_rate` | What sampling rate to use on the recording | `integer()` |   | `false` |  
`should_follow_transfer` | If true, the recording will continue after a transfer on the active leg | `boolean()` | `true` | `false` |  
`silence_detection` | Whether to stop the recording if no speech is detected for a period of time. When silence is detected, a timer will start, see silence_final_timeout and silence_initial_timeout. | `boolean()` |   | `false` |  
`silence_final_timeout` | The timeout in milliseconds to stop the recording when silence is detected. This timeout is different from initial timeout in that in final timeout the speech is already detected since the recording is started. | `integer()` | `5` | `false` |  
`silence_initial_timeout` | The timeout in milliseconds to stop the recording when silence is detected and no speech is detected since the start of recording | `integer()` | `0` | `false` |  
`silence_threshold` | The energy level below which is considered silence. | `integer()` | `200` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`time_limit` | Time limit, in seconds, for the recording | `integer(5..10800)` | `3600` | `false` |  
`url` | The URL to use when sending the recording for storage | `string(5..)` |   | `false` |  


## Examples

### Record only the caller

 Useful for voicemail or recording menu prompts.

```json
{
    "module": "say",
    "data": {
        "text": "Please leave your message after the beep"
    },
    "children": {
        "_": {
            "module": "record_caller",
            "data": {
                "format": "mp3",
                "url": "http://my.recording.server/voicemail/{ACCOUNT_ID}/{BOX_ID}",
                "time_limit":360
            }
        }
    }
}
```