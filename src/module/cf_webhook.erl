%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2025, 2600Hz
%%% @doc
%%% @author Peter Defebvre
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_webhook).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).
-export([handle_webhook/2]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    _ = handle_webhook(Data, Call),
    cf_exe:continue(Call).

-spec handle_webhook(kz_json:object(), kapps_call:call()) -> 'ok' | {'error', any()}.
handle_webhook(Data, Call) ->
    CallJObj = format_call_data(Call),
    Hook = set_hook(Data, Call),
    Props = [{<<"Hook">>, Hook}
            ,{<<"Timestamp">>, kz_time:now_s()}
            ,{<<"Data">>, CallJObj}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],
    kapps_notify_publisher:cast(Props, fun kapi_notifications:publish_webhook/1).

-spec format_call_data(kapps_call:call()) -> kz_json:object().
format_call_data(Call) ->
    JObj = kapps_call:to_json(Call),
    RemoveKeys = [<<"Key-Value-Store">>
                 ,<<"Control-Queue">>
                 ,<<"Controller-Queue">>
                 ,<<"Custom-Channel-Vars">>
                 ],
    kz_json:normalize_jobj(JObj, RemoveKeys, []).

-spec set_hook(kz_json:object(), kapps_call:call()) -> kz_json:object().
set_hook(Data, Call) ->
    Now = calendar:datetime_to_gregorian_seconds(calendar:local_time()),
    {'ok', Schema} = kz_json_schema:load(<<"webhooks">>),
    PropertyKeys = kz_json:get_keys(<<"properties">>, Schema),

    DefaultWebhook = kz_doc:setters(kzd_webhooks:new()
                                   ,[{fun kz_doc:set_id/2, kz_term:to_binary(Now)}
                                    ,{fun kz_doc:set_account_id/2, kapps_call:account_id(Call)}
                                    ,{fun kzd_webhooks:set_hook/2, <<"notifications">>}
                                    ]),
    {_, Webhook} = lists:foldl(fun add_if_set/2, {Data, DefaultWebhook}, PropertyKeys),
    Webhook.

add_if_set(Key, {Data, Webhook}) ->
    case kz_json:get_value(Key, Data) of
        'undefined' -> {Data, Webhook};
        Value -> {Data, kz_json:set_value(Key, Value, Webhook)}
    end.
