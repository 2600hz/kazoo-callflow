## Callflow Variable

### About Callflow Variable

#### Schema

Validator for the callflow_variable callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | an id of the document to fetch | `string()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`variable` | the variable or path to a variable that contains the callflow | `string()` |   | `false` |  



