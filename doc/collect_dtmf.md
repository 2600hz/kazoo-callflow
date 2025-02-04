# Collect Dtmf

Collect DTMF from the caller and store it in the call record. Multiple collections can be stored under custom-named keys. Typically `collect_dtmf` is used with [Pivot](https://docs.2600hz.com/git/2600hz/kazoo-pivot/doc/README.md). Most flows built outside of Pivot use [menu](./menu.md).

If you aren't using Pivot but still want to use `collect_dtmf` instead of [menu](./menu.md), ignore the PHP portions of examples in this document.


## Collecting DTMF

The initial {% BRAND_NAME %} JSON to collect DTMF could look something like:

```php
<?php

header('content-type:application/json');

?>
{
    "module":"tts",
    "data":{
        "text": "Please enter up to four digits."
    },
    "children": {
        "_": {
            "module": "collect_dtmf",
            "data": {
                "max_digits": 4,
                "collection_name": "custom_name"
            },
            "children": {
                "_": {
                    "module": "pivot",
                    "data": {
                        "voice_url": "http://pivot.your.company.com/collected.php"
                    },
                    "children": {}
                }
            }
        }
    }
}
```

First, {% BRAND_NAME %} will use the TTS engine to say the `text` field. Next, it will wait for the user to press up to 4 DTMF (with `#` being a terminating DTMF that is not included in the collection). Finally, a second pivot request will be made the the `collected.php` script on your server.

This is a basic menu! Congrats, you can build custom IVRs!

## Processing collected DTMF

Here is demonstrated speaking back the digits pressed to the caller; you could obviously key off the DTMF to do whatever further call processing.

```php
<?php

header('content-type:application/json');

$dtmf = $_REQUEST['Digits'];

if ( empty($dtmf) ) {
?>

{
    "module": "tts",
    "data": {
        "text": "We didn't get that"
    },
    "children": {}
}

<?php } else if ( is_string($dtmf) ) { ?>

{
    "module": "tts",
    "data": {
        "text": "You typed <?= $dtmf ?>"
    },
    "children": {}
}

<?php } else { ?>

{
    "module": "tts",
    "data": {
        "text": "You typed <?= $dtmf['custom_name'] ?>"
    },
    "children": {}
}

<?php } ?>
```

The `is_string($dtmf)` check is to support the old way of returning DTMF in the Pivot request. Otherwise, you should receive an array of DTMF collections, indexed by the key name supplied ("default" if you didn't specify one).

#### Schema

Validator for the Collect DTMF callflow element



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`collection_name` | Store collected DTMF in a named key | `string()` |   | `false` |  
`interdigit_timeout` | How long, in milliseconds, to wait for the next DTMF | `integer(1..)` |   | `false` |  
`max_digits` | How many DTMFs to collect from the caller | `integer(1..)` | `1` | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`terminator` | What DTMF will terminate collection before the timeout occurs | `string('1' \| '2' \| '3' \| '4' \| '5' \| '6' \| '7' \| '8' \| '9' \| '0' \| '#' \| '*')` | `#` | `false` |  
`terminators.[]` |   | `string('1' \| '2' \| '3' \| '4' \| '5' \| '6' \| '7' \| '8' \| '9' \| '0' \| '#' \| '*')` |   | `false` |  
`terminators` | What DTMFs will terminate collection before the timeout occurs | `array(string('1' \| '2' \| '3' \| '4' \| '5' \| '6' \| '7' \| '8' \| '9' \| '0' \| '#' \| '*'))` |   | `false` |  
`timeout` | How long, in milliseconds, to wait for the first DTMF | `integer(1..)` | `5000` | `false` |  



