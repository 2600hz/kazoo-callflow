%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2023, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_device).

-behaviour(gen_cf_action).

-include_lib("callflow/src/callflow.hrl").

-export([handle/2
        ,bridge_to_endpoints/3
        ]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    case bridge_to_endpoints(Data, Call) of
        {'ok', JObj} ->
            lager:info("completed successful bridge to the device"),
            stop(Call, kz_call_event:channel_answer_state(JObj));
        {'fail', _}=Reason -> maybe_handle_bridge_failure(Reason, Call);
        {'error', _R} when is_atom(_R) ->
            lager:info("failed to build endpoint from device: ~p", [_R]),
            cf_exe:continue(Call);
        {'error', _R} ->
            lager:info("error bridging to device: ~s"
                      ,[kz_json:get_ne_binary_value(<<"Error-Message">>, _R)]
                      ),
            cf_exe:continue(Call)
    end.

-spec stop(kapps_call:call(), kz_term:api_ne_binary()) -> 'ok'.
stop(Call, <<"hangup">>) -> cf_exe:hard_stop(Call);
stop(Call, _) -> cf_exe:stop(Call).

-spec maybe_handle_bridge_failure(any(), kapps_call:call()) -> 'ok'.
maybe_handle_bridge_failure(Reason, Call) ->
    case cf_util:handle_bridge_failure(Reason, Call) of
        'not_found' -> cf_exe:continue(Call);
        'ok' -> 'ok'
    end.

%%------------------------------------------------------------------------------
%% @doc Attempts to bridge to the endpoints created to reach this device
%% @end
%%------------------------------------------------------------------------------
-spec bridge_to_endpoints(kz_json:object(), kapps_call:call()) ->
          cf_api_bridge_return().
bridge_to_endpoints(Data, Call) ->
    EndpointId = kz_json:get_ne_binary_value(<<"id">>, Data),
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),

    case kz_endpoint:build(EndpointId, Params, Call) of
        {'error', _}=E -> E;
        {'ok', []} ->
            lager:info("no endpoints built"),
            {'error', 'not_found'};
        {'ok', Endpoints} ->
            bridge_to_endpoints(Data, Call, Endpoints)
    end.

-spec bridge_to_endpoints(kz_json:object(), kapps_call:call(), kz_endpoint:endpoints()) ->
          cf_api_bridge_return().
bridge_to_endpoints(Data, Call0, [_|_]=Endpoints) ->
    %% maybe start recording on inbound leg
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),

    FailOnSingleReject = kz_json:get_binary_boolean(<<"fail_on_single_reject">>, Data),
    Timeout = kz_json:get_integer_value(<<"timeout">>, Data, ?DEFAULT_TIMEOUT_S),
    IgnoreEarlyMedia = kz_endpoints:ignore_early_media(Endpoints),
    Strategy = kz_json:get_ne_binary_value(<<"dial_strategy">>, Data, <<"simultaneous">>),
    CustomSIPHeaders = kz_json:get_ne_json_value(<<"custom_sip_headers">>, Data),

    kapps_call_command:b_bridge(Endpoints
                               ,Timeout
                               ,Strategy
                               ,IgnoreEarlyMedia
                               ,'undefined' % Ringback
                               ,CustomSIPHeaders
                               ,<<"false">> % IgnoreForward
                               ,FailOnSingleReject
                               ,set_context_flags(Call, Data)
                               ).

set_context_flags(Call, Data) ->
    Flags = lists:filtermap(fun is_context_flag/1, kz_json:to_proplist(Data)),
    kapps_call:kvs_store('context-flags', Flags, Call).

is_context_flag({K, V}) ->
    case kz_term:is_true(V) of
        'true' -> {'true', K};
        'false' -> 'false'
    end.
