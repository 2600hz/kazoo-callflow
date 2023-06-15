# Callflow Maintenance

## SUP-able functions

| Function | Arguments | Description |
| -------- | --------- | ----------- |
| `account_set_classifier_deny/2` | `(Classifier,Account)` | |
| `account_set_classifier_inherit/2` | `(Classifier,Account)` | |
| `all_accounts_set_classifier_deny/1` | `(Classifier)` | |
| `all_accounts_set_classifier_inherit/1` | `(Classifier)` | |
| `allow_authz_context/1` | `(App)` | |
| `allow_authz_context/2` | `(App,DefaultContext)` | |
| `blocking_refresh/0` |  | |
| `call_count/0` |  | |
| `deny_authz_context/1` | `(App)` | |
| `device_classifier_deny/2` | `(Classifier,Uri)` | |
| `device_classifier_inherit/2` | `(Classifier,Uri)` | |
| `disable_authz_contexts/0` |  | |
| `enable_authz_contexts/0` |  | |
| `flush/0` |  | |
| `is_classifier/1` | `(Classifier)` | |
| `list_account_restrictions/1` | `(Account)` | |
| `lookup_endpoint/1` | `(URI)` | |
| `lookup_endpoint/2` | `(Username,Realm)` | |
| `migrate_menus/0` |  | |
| `migrate_menus/1` | `(Account)` | |
| `migrate_recorded_name/1` | `(Db)` | |
| `migrate_recorded_names/0` |  | |
| `refresh/0` |  | |
| `refresh/1` | `(Account)` | |
| `show_calls/0` |  | |
| `update_feature_codes/0` |  | |
| `update_feature_codes/1` | `(Account)` | |

### About The Maintenance Commands

The maintenance module defines a set of functions useful to sysadmins for adjusting how the callflow app operates.

When processing route requests, the default context of the call does not permit unauthorized calls to make use of the `no_match` callflow. Some Kazoo applications will set the context used (say during a blind transfer) to note that this particular route request should be authorized to use the `no_match` callflow.

```bash
sup callflow_maintenance allow_authz_context {APP_NAME} [{AUTHZ_CONTEXT}]
```

If `{AUTHZ_CONTEXT}` is omitted, the value will be read from `{APP_NAME}`'s `system_config` document (using the `authz_context` key). If the key is missing from that document, a default random hex string will be set in the app's config and used in the callflow doc.

### deny_authz_context/1

Remove an app's `authz_context` from the allowed authz contexts

```bash
sup callflow_maintenance deny_authz_context {APP_NAME}
```

### {enable,disable}_authz_context/0

Toggle whether to allow callflows to check the route request's context and compare to allowed authz_contexts for `no_match` access.

```bash
sup callflow_maintenance enable_authz_context
```

```bash
sup callflow_maintenance disable_authz_context
```
