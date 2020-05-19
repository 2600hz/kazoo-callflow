## Detect Speech

### About Detect Speech

#### Schema

Validator for the detect_speech callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`action` |   | `string()` |   | `false` |  
`asr_engine` |   | `string()` |   | `false` |  
`asr_params` |   | `object()` |   | `false` |  
`asr_settings` |   | `object()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  



