# Record Call

The `record_call` module makes recording callers (or caller and callee in a bridged-call scenario) straightforward. 
{% BRAND_NAME %} can store the call locally, or send it to a developer's server.

The related [record caller](./record_caller.md) module is used to record only the caller.
## Start Recording

```json
{
    "module": "record_call",
    "data": {
        "action": "start",
        "time_limit": 1200,
        "format": "mp3",
        "url": "http://your.server.com/recordings"
    }
}
```

This will start the call recording, limiting it to 1200 seconds, and will encode the audio into an MP3 file (alternatively, you can use "wav"). The `url` is where the resulting file will be sent via an HTTP PUT request. It is then up to the receiving server to properly handle the request and store the file for later use.

Note: `time_limit` is constrained by the `system_config/media` doc's `max_recording_time_limit` entry (default is 10800 seconds). If your recordings are not long enough, that is the setting that needs increasing.

Note: `url` will be used as the base URL for the resulting PUT. The final URL will be `URL/call_recording_CALL_ID.EXT` where `URL` is the supplied URL, `CALL_ID` is the call ID of the A-leg being recorded, and `EXT` is the `format` parameter.

Note: If `url` is not provided, {% BRAND_NAME %} will check the `system_config/media` doc for the `store_recordings` flag. If "false", the recording will not be stored (kinda pointless). If "true", {% BRAND_NAME %} will store the recording into the account's database.

## Stop Recording

Recording stops automatically when the call ends, but can be stopped during a call with the stop action.

```json
{
    "module": "record_call",
    "data": {
        "action": "stop"
    }
}
```

## Storage of recordings

If you supply a URL in the `data` portion of the callflow, {% BRAND_NAME %} will send an HTTP PUT with the recording to the URL when the recording has finished.

If you omit the URL, there are a couple options for storage:

* Check `system_config/media` for the `store_recordings` boolean()
    * If `false`, no storage will occur
    * If `true`, check `system_config/media` for `third_party_bigcouch_host`
        * If `undefined`, store to the {% BRAND_NAME %} BigCouch cluster
        * If defined, send the recording to the configured URL

#### Schema

Validator for the Record Call callflow action



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` | Whether to start or stop the recording | `string('start' \| 'stop')` | `start` | `true` |  
`format` | What format to store the recording on disk | `string('mp3' \| 'wav')` |   | `false` |  
`label` | Label to include in the origin of call recording | `string()` |   | `false` |  
`media_id` | Doc ID of the created recording - if unspecified, {% BRAND_NAME %} will generate one | `string()` |   | `false` |  
`media_name` | the name of media | `string()` |   | `false` |  
`method` | HTTP verb to use when sending the recording to the supplied URL | `string('put' \| 'post')` | `put` | `false` |  
`origin` | How the recording was started - read-only | `string()` |   | `false` |  
`record_min_sec` | The minimum length, in seconds, the recording must be to be considered successful. Otherwise it is deleted | `integer()` |   | `false` |  
`record_on_answer` | Whether to delay the recording until the channel is answered | `boolean()` | `false` | `false` |  
`record_on_bridge` | Whether to delay the recording until the channel is bridged | `boolean()` | `false` | `false` |  
`record_sample_rate` | What sampling rate to use on the recording | `integer()` |   | `false` |  
`should_follow_transfer` | If true, the recording will continue after a transfer on the active leg | `boolean()` | `true` | `false` |  
`silence_detection` | Whether to stop the recording if no speech is detected for a period of time. When silence is detected, a timer will start, see silence_final_timeout and silence_initial_timeout. | `boolean()` |   | `false` |  
`silence_final_timeout` | The timeout in milliseconds to stop the recording when silence is detected. This timeout is different from initial timeout in that speech was already detected when the recording is started, and now it is stopped. | `integer()` | `5` | `false` |  
`silence_initial_timeout` | The timeout in milliseconds to stop the recording when silence is detected and no speech is detected since the start of recording | `integer()` | `0` | `false` |  
`silence_threshold` | The energy level below which is considered silence. | `integer()` | `200` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`time_limit` | Time limit, in seconds, for the recording | `integer(5..10800)` | `3600` | `false` |  
`url` | The URL to use when sending the recording for storage | `string(5..)` |   | `false` |  


## Examples

### Sample Recording Per User

```json
{
    "module": "record_call",
    "data": {
        "action": "start",
        "format": "mp3",
        "url": "http://my.recording.server/{ACCOUNT_ID}/{USER_ID}",
        "time_limit":360
    },
    "children": {
        "_": {
            "module": "user",
            "data": {
                "id": "{USER_ID}"
            },
            "children": {
                "_": {
                    "module": "record_call",
                    "data": {
                        "action": "stop"
                    },
                    "children": {
                        "module": "voicemail",
                        "data": {
                            "id": "{VMBOX_ID}"
                        },
                        "children": {}
                    }
                }
            }
        }
    }
}
```
Note: Call recording and Voicemail do not play well together. You will need to stop the recording before voicemail to avoid conflict.

### Receiving a recording

Here is a simple PHP/`.htaccess` combo for receiving a recording.

1. Assume `url` in our `data` object is "http://your.server.com/kzr"
2. Create a `.htaccess` file in the DocumentRoot. This will direct the request to `/kzr/index.php` with the `recording` query string parameter set to `CALL_ID.EXT`.

```
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteRule ^kzr/call_recording_(.+)\.(.+)$  kzr/index.php?recording=$1.$2 [QSA,L]
        </IfModule>
```

3. Create `/kzr/index.php` to receive and store the recording.

```php
<?php
/* PUT data comes in on the stdin stream */
$putdata = fopen("php://input", "r");

$r = $_REQUEST["recording"];
/* Open a file for writing */
$fp = fopen("/tmp/$r", "w");
/* Read the data 1 KB at a time and write to the file */
while ($data = fread($putdata, 1024))
    fwrite($fp, $data);

/* Close the streams */
fclose($fp);
fclose($putdata);
?>
```

A file should be created in `/tmp/` named `CALL_ID.EXT`. You could, of course, store this in MySQL, Postgres, S3, feed it to a transcription service, etc.
