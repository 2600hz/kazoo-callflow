## Callflow Inline

### About Callflow Inline

#### Schema

Validator for the callflow_inline callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`flow` | A callflow node defines a module to execute, data to provide to that module, and zero or more children to branch to | [#/definitions/callflows.action](#callflowsaction) |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  

### callflows.action

Call flows describe steps to take in order to process a phone call. They are trees of information related to a phone call such as "answer, play file, record file" etc. that are logically grouped together and ordered.


Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`children./.+/` | Call flows describe steps to take in order to process a phone call. They are trees of information related to a phone call such as "answer, play file, record file" etc. that are logically grouped together and ordered. | [#/definitions/callflows.action](#callflowsaction) |   | `false` |  
`children` | Children callflows | `object()` |   | `false` |  
`data` | The data/arguments of the callflow module | `object()` | `{}` | `true` |  
`module` | The name of the callflow module to execute at this node | `string(1..64)` |   | `true` |  



