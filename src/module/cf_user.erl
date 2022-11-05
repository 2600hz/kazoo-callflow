%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2022, 2600Hz
%%% @doc
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_user).

-behaviour(gen_cf_action).

-export([handle/2]).

-include("callflow.hrl").

-type endpoint_get_error() :: kz_endpoint:build_errors() | 'endpoint_not_configured' | 'no_endpoints'.

%%------------------------------------------------------------------------------
%% @doc Entry point for this module, attempts to call an endpoint as defined
%% in the Data payload.  Returns continue if fails to connect or
%% stop when successful.
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    UserId = kz_json:get_ne_binary_value(<<"id">>, Data),
    case get_endpoints(UserId, Data, Call) of
        {'ok', Endpoints} -> bridge(Data, Call, Endpoints);
        {'error', Error} -> handle_error(Call, UserId, Error, should_block_self(Call))
    end.

-spec handle_error(kapps_call:call(), kz_term:api_ne_binary(), endpoint_get_error(), boolean()) -> 'ok'.
handle_error(Call, UserId, 'endpoint_called_self', 'true') ->
    lager:warning("endpoint ~s called self with transfer/cfwd", [UserId]),
    cf_exe:stop(Call, <<"DESTINATION_OUT_OF_ORDER">>);
handle_error(Call, UserId, 'owner_called_self', 'true') ->
    lager:warning("owner ~s called self with transfer/cfwd", [UserId]),
    cf_exe:stop(Call, <<"DESTINATION_OUT_OF_ORDER">>);
handle_error(Call, UserId, Error, _) ->
    lager:info("error bridging to user ~s : ~s", [UserId, Error]),
    cf_exe:continue(kz_term:to_upper_binary(Error), Call).

-spec should_block_self(kapps_call:call()) -> boolean().
should_block_self(Call) ->
    kapps_call:is_call_forward(Call)
        orelse kapps_call:is_transfer(Call).

-spec bridge(kz_json:object(), kapps_call:call(), kz_json:objects()) -> 'ok'.
bridge(Data, Call0, Endpoints) ->
    Call = cf_util:maybe_start_recording_to(Call0, <<"onnet">>),

    FailOnSingleReject = kz_json:is_true(<<"fail_on_single_reject">>, Data, kapps_call:custom_channel_var(<<"Require-Fail-On-Single-Reject">>, Call)),
    Timeout = kz_json:get_integer_value(<<"timeout">>, Data, ?DEFAULT_TIMEOUT_S),
    Strategy = kz_json:get_ne_binary_value(<<"strategy">>, Data, <<"simultaneous">>),
    IgnoreEarlyMedia = Strategy =:= <<"simultaneous">>
        orelse kz_endpoints:ignore_early_media(Endpoints),
    CustomSIPHeaders = kz_json:get_ne_json_value(<<"custom_sip_headers">>, Data),

    lager:info("attempting ~b user devices with strategy ~s", [length(Endpoints), Strategy]),

    case kapps_call_command:b_bridge(Endpoints
                                    ,Timeout
                                    ,Strategy
                                    ,IgnoreEarlyMedia
                                    ,'undefined' % Ringback
                                    ,CustomSIPHeaders
                                    ,<<"false">> % IgnoreForward
                                    ,FailOnSingleReject
                                    ,set_context_flags(Call, Data)
                                    )
    of
        {'ok', JObj} ->
            lager:info("completed successful bridge to user"),
            stop(Call, kz_call_event:channel_answer_state(JObj));
        {'fail', JObj}=Reason ->
            lager:info("bridge to user failed : ~s / ~s / ~s"
                      ,[kz_call_event:application_response(JObj)
                       ,kz_call_event:hangup_cause(JObj)
                       ,kz_call_event:hangup_code(JObj)
                       ]
                      ),
            maybe_handle_bridge_failure(kz_call_event:channel_answer_state(JObj), Reason, Call);
        {'error', _R} ->
            lager:info("error bridging to user: ~p", [_R]),
            cf_exe:continue(Call)
    end.

-spec stop(kapps_call:call(), kz_term:api_ne_binary()) -> 'ok'.
stop(Call, <<"hangup">>) -> cf_exe:hard_stop(Call);
stop(Call, _) -> cf_exe:stop(Call).

-type bridge_failure_cause() :: {'fail', kz_json:object()}.

-spec maybe_handle_bridge_failure(kz_term:api_ne_binary(), bridge_failure_cause(), kapps_call:call()) -> 'ok'.
maybe_handle_bridge_failure(<<"hangup">>, _Reason, Call) ->
    cf_exe:hard_stop(Call);
maybe_handle_bridge_failure(_, Reason, Call) ->
    case cf_util:handle_bridge_failure(Reason, Call) of
        'not_found' -> cf_exe:continue(hangup_cause(Reason), Call);
        'ok' -> 'ok'
    end.

-spec hangup_cause(bridge_failure_cause()) -> kz_term:ne_binary().
hangup_cause({'fail', JObj}) ->
    kz_call_event:hangup_cause(JObj, <<"UNSPECIFIED">>).

%%------------------------------------------------------------------------------
%% @doc Loop over the provided endpoints for the callflow and build the
%% json object used in the bridge API
%% @end
%%------------------------------------------------------------------------------
-spec get_endpoints(kz_term:api_binary(), kz_json:object(), kapps_call:call()) ->
          {'ok', [kz_json:object(),...]} |
          {'error', endpoint_get_error()}.
get_endpoints('undefined', _, _) ->
    {'error', 'endpoint_not_configured'};
get_endpoints(UserId, Data, Call) ->
    Params = kz_json:set_value(<<"source">>, kz_term:to_binary(?MODULE), Data),
    case kz_endpoints:by_owner_id(UserId, Params, Call) of
        [] -> {'error', 'no_endpoints'};
        {'error', _} = Err -> Err;
        EPs -> {'ok', EPs}
    end.

set_context_flags(Call, Data) ->
    Flags = lists:filtermap(fun is_context_flag/1, kz_json:to_proplist(Data)),
    kapps_call:kvs_store('context-flags', Flags, Call).

is_context_flag({K, V}) ->
    case kz_term:is_true(V) of
        'true' -> {'true', K};
        'false' -> 'false'
    end.
