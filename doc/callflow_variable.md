## Callflow Variable

### About Callflow Variable

#### Schema

Validator for the callflow_variable callflow data object



Key | Description | Type | Default | Required | Support Level
--- | ----------- | ---- | ------- | -------- | -------------
`id` | an id of the document to fetch | `string()` |   | `false` |  
`skip_module` | When set to true this callflow action is skipped, advancing to the wildcard branch (if any) | `boolean()` |   | `false` |  
`variable` | the variable or path to a variable that contains the callflow id to execute | `string()` |   | `false` |  



### Usage / Example  

A `user`'s document may look like:  
```
{
  id: "userid123",
  favorite_callflow_id: "callflowid123",
  ...(more info such as first_name, last_name, etc)
}
```

So the `callflow_variable` module would look like:  
```
{
  module: "callflow_variable",
  data: {
    id: "userid123",
    variable: "favorite_callflow_id"
  }
}
```
