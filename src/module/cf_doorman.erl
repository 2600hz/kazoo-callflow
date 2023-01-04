%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2023, 2600Hz
%%% @doc Doorman for a user or device
%%%
%%% 1. Have caller record their name and why they're calling (8s limit)
%%% 2. Originate to callee
%%% 3. Play prompt + recording for callee
%%%   a. Press 1, connect caller to callee
%%%   b. Press 2, connect caller to callee, prompt recording started, start recording
%%%   c. Press 3, lookup callee's voicemail and send caller to voicemail
%%%   d. Press 4, reject caller
%%%
%%% Data:
%%%   endpoint_id     | {ID}       | User or device
%%%   recording_limit |  8s        | Caller's time limit for the recording
%%%   ringtone        | [ToneJObj] | The ring tone to play to the caller after recording
%%%   caller_id_name  | "Doorman"  | The caller ID name to be displayed to the callee
%%%   call_timeout    | 30s        | How long to ring the callee
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_doorman).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).

-define(DTMF_CONNECT_CALL, <<"1">>).
-define(DTMF_CONNECT_RECORD, <<"2">>).
-define(DTMF_VM, <<"3">>).
-define(DTMF_HANGUP, <<"4">>).

%%------------------------------------------------------------------------------
%% @doc Doorman entry point
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    kapps_call_command:answer(Call),

    RecordingId = get_caller_recording(Data, Call),

    lager:info("caller has recording message (~s) and is ringing", [RecordingId]),
    contact_callee(Data, kapps_call:kvs_store('caller_recording_id', RecordingId, Call)).

-spec get_caller_recording(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
get_caller_recording(Data, Call) ->
    _ = prompt_caller(Call),
    record_caller(Data, Call).

-spec record_caller(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
record_caller(Data, Call) ->
    RecordingId = <<(kz_binary:rand_hex(16))/binary, ".mp3">>,
    {'ok', _} = kapps_call_command:b_record(RecordingId
                                           ,?ANY_DIGIT
                                           ,recording_limit(Data)
                                           ,Call
                                           ),
    'ok' = thank_caller(Data, Call),
    RecordingId.

recording_limit(Data) ->
    Limit = kz_json:get_integer_value(<<"recording_limit">>, Data, 8),
    kz_math:clamp(16, 6, Limit).

thank_caller(Data, Call) ->
    Text = <<"Thanks!">>,
    {'ok', _} = kapps_call_command:b_tts(Text, Call),
    Tones = cf_tones:convert_tones(tones(Data)),
    kapps_call_command:tones(Tones, Call).

tones(Data) ->
    [kz_json:set_value(<<"repeat">>, 20, Tone)
     || Tone <- kz_json:get_list_value(<<"tones">>, Data, [us_tone()])
    ].

-spec us_tone() -> kz_json:object().
us_tone() ->
    kz_json:from_list([{<<"duration_on">>, 2000}
                      ,{<<"duration_off">>, 4000}
                      ,{<<"frequencies">>, [440,480]}
                      ]).

prompt_caller(Call) ->
    Text = <<"Hi. You have reached the doorman demo. "
             "Please say your first and last name "
             "and the purpose of your call after the beep."
             "Then I'll try to connect you."
           >>,
    {'ok', _} = kapps_call_command:b_tts(Text, Call).

hangup_caller(Call) ->
    Text = <<"The party you dialed could not be reached. Good bye!">>,
    {'ok', _} = kapps_call_command:b_tts(Text, Call),
    'ok' = kapps_call_command:hangup(Call),
    cf_exe:hard_stop(Call).

contact_callee(Data, Call) ->
    EndpointId = kz_doc:id(Data),

    Props = kz_json:from_list([{<<"source">>, <<?MODULE_STRING>>}]),

    case kz_endpoint:build(EndpointId, Props, Call) of
        {'ok', Endpoints} ->
            lager:info("contacting endpoints for  ~s", [EndpointId]),
            contact_callee(Data, Call, Endpoints);
        {'error', _E} ->
            lager:info("failed to build endpoint ~s: ~p", [EndpointId, _E]),
            hangup_caller(Call)
    end.

-spec contact_callee(kz_json:object(), kapps_call:call(), kz_json:objects()) -> 'ok'.
contact_callee(Data, CallerCall, Endpoints) ->
    CalleeCall = create_callee_call(Data, CallerCall, Endpoints),
    contact_callee(Data, CallerCall, Endpoints, CalleeCall).

contact_callee(Data, CallerCall, Endpoints, CalleeCall) ->
    case originate_callee(Data, CallerCall, Endpoints, CalleeCall) of
        {'ok', OriginateResp} ->
            UpdatedCallee = update_callee_call(OriginateResp, CalleeCall),

            update_logging_id(CallerCall, UpdatedCallee),

            lager:info("callee successfully answered the call"),
            doorman_menu(Data, CallerCall, UpdatedCallee);
        {'error', _E} ->
            lager:info("failed to contact callee: ~p", [_E]),
            callee_error(CallerCall)
    end.

doorman_menu(Data, CallerCall, CalleeCall) ->
    _NoopId = doorman_menu_prompt(CallerCall, CalleeCall),
    case kapps_call_command:wait_for_application_or_dtmf(<<"noop">>, 15 * ?MILLISECONDS_IN_SECOND) of
        {'error', 'timeout'} ->
            lager:info("timed out waiting for callee to choose"),
            callee_error(CallerCall);
        {'error', _E} ->
            lager:info("error waiting for callee to choose: ~p", [_E]),
            callee_error(CallerCall);
        {'dtmf', Choice} ->
            handle_choice(Data, CallerCall, CalleeCall, Choice)
    end.


%%     If 1 is pressed the call is connected
%%     If 2 is pressed the call is connected and both parties hear "This call is being recorded" and the callee also hears "to stop the recording press 5 at any time" when either party hangs up or the callee presses #5 the audio file with the recording is posted to this site https://webhook.site/#!/84f01ee0-1cc6-43f3-afa9-f10639c041f4
%%     If 3 is pressed the caller is sent to voicemail and link to file is posted to this site https://webhook.site/#!/84f01ee0-1cc6-43f3-afa9-f10639c041f4, Voicemail is also transcribed and the transcription is sent to the forwarding number (one that owns the app)
%%     If 4 is pressed call is ended
handle_choice(_Data, CallerCall, CalleeCall, ?DTMF_CONNECT_CALL) ->
    TargetCallId = kapps_call:call_id(CallerCall),
    lager:info("callee has chosen to connect the call ~s", [TargetCallId]),

    pickup_caller(TargetCallId, CalleeCall);
handle_choice(Data, CallerCall, CalleeCall, ?DTMF_CONNECT_RECORD) ->
    TargetCallId = kapps_call:call_id(CallerCall),
    lager:info("callee has chosen to connect and record the call ~s", [TargetCallId]),

    RecordData = kz_json:set_values([{<<"origin">>, <<"callflow : " ?MODULE_STRING>>}]
                                   ,Data
                                   ),
    UpdatedCallerCall = cf_record_call:handle(RecordData, CallerCall, <<"start">>),
    _ = cf_exe:update_call(UpdatedCallerCall),

    pickup_caller(TargetCallId, CalleeCall);
handle_choice(Data, CallerCall, CalleeCall, ?DTMF_VM) ->
    VMBoxId = kz_json:get_ne_binary_value(<<"vmbox_id">>, Data),
    lager:info("callee has chosen to send caller to voicemail box ~s", [VMBoxId]),

    kapps_call_command:hangup(CalleeCall),

    VMData = kz_json:from_list([{<<"action">>, <<"compose">>}
                               ,{<<"id">>, VMBoxId}
                               ]),
    cf_voicemail:handle(VMData, CallerCall);
handle_choice(_Data, CallerCall, CalleeCall, _DTMF) ->
    lager:info("callee has selected not to take the call (pressed ~p)", [_DTMF]),
    kapps_call_command:hangup(CalleeCall),
    callee_error(CallerCall).

pickup_caller(TargetCallId, CalleeCall) ->
    kapps_call_command:pickup(TargetCallId, CalleeCall),
    kapps_call_command:wait_for_hangup().

doorman_menu_prompt(CallerCall, CalleeCall) ->
    %%     When you answer the incoming call the following message is played “ Call from” + recording is played + Press 1 to answer; press 2 to answer with recording enabled; press 3 to send the call to voicemail; press 4 to reject or simply hangup.
    AudioMacro = [{'tts', <<"Call from">>}
                 ,{'play', kapps_call:kvs_fetch('call_recording_id', CallerCall)}
                 ,{'tts', <<"Press 1 to answer">>}
                 ,{'tts', <<"Press 2 to answer with recording enabled">>}
                 ,{'tts', <<"Press 3 to send the call to voicemail">>}
                 ,{'tts', <<"Press 4 to reject or simply hangup">>}
                 ],
    NoopId = kapps_call_command:audio_macro(AudioMacro, CalleeCall),
    kapps_call_command:wait_for_noop(CalleeCall, NoopId).

-spec update_logging_id(kapps_call:call(), kapps_call:call()) -> any().
update_logging_id(CallerCall, CalleeCall) ->
    LogId = iolist_to_binary([kapps_call:call_id(CallerCall)
                             ,"-doorman-"
                             ,kapps_call:call_id(CalleeCall)
                             ]),
    kz_log:put_callid(LogId).

update_callee_call(OriginateResp, CalleeCall) ->
    kapps_call:from_originate_resp(OriginateResp, CalleeCall).

originate_callee(Data, CallerCall, Endpoints, CalleeCall) ->
    Request = build_originate_request(Data, CalleeCall, Endpoints, kapps_call:call_id(CallerCall)),

    case originate_request(Request) of
        {'error', _E}=Error -> Error;
        {'ok', JObjs} ->
            handle_originate_resp(lists:partition(fun kapi_resource:originate_resp_v/1, JObjs))
    end.

callee_error(CallerCall) ->
    Text = <<"The caller could not be reached">>,
    {'ok', _} = kapps_call_command:b_tts(Text, CallerCall),
    cf_exe:continue(CallerCall).

-spec handle_originate_resp({kz_json:objects(), kz_json:objects()}) ->
          {'ok', kapi_resource:originate_resp()} |
          {'error', kz_json:object()}.
handle_originate_resp({[], [Error|_]}) ->
    {'error', Error};
handle_originate_resp({[Resp], _Error}) ->
    handle_originate_resp(Resp, kz_call_event:application_response(Resp)).

handle_originate_resp(Resp, <<"SUCCESS">>) ->
    {'ok', Resp};
handle_originate_resp(Resp, _AppResponse) ->
    {'error', Resp}.

originate_request(Request) ->
    CollectTimeoutMs = kz_json:get_integer_value(<<"Timeout">>, Request) * ?MILLISECONDS_IN_SECOND,
    kz_amqp_worker:call_collect(Request
                               ,fun kapi_resource:publish_originate_req/1
                               ,fun is_originate_resp/1
                               ,CollectTimeoutMs
                               ).

is_originate_resp([Resp | _Resps]) ->
    kapi_resource:originate_resp_v(Resp)
        orelse kz_api:error_resp_v(Resp).

build_originate_request(Data, CalleeCall, Endpoints, CallerCallId) ->
    CCVs = [{<<"Account-ID">>, kapps_call:account_id(CalleeCall)}
           ,{<<"Inherit-Codec">>, <<"false">>}
           ,{<<"Authorizing-Type">>, kapps_call:authorizing_type(CalleeCall)}
           ,{<<"Authorizing-ID">>, kapps_call:authorizing_id(CalleeCall)}
           ],
    MsgId = kz_binary:rand_hex(16),
    CallId = iolist_to_binary([kz_binary:rand_hex(16), "-doorman"]),
    CallTimeoutS = kz_json:get_integer_value(<<"call_timeout">>, Data, 30),

    kz_json:from_list(
      [{<<"Application-Name">>, <<"park">>}
      ,{<<"Application-Data">>, kz_json:new()}
      ,{<<"Continue-On-Fail">>, 'false'}
      ,{<<"Custom-Channel-Vars">>, kz_json:from_list(CCVs)}
      ,{<<"Dial-Endpoint-Method">>, <<"simultaneous">>}
      ,{<<"Endpoints">>, Endpoints}
      ,{<<"Existing-Call-ID">>, CallerCallId}
      ,{<<"Export-Custom-Channel-Vars">>, [<<"Account-ID">>
                                          ,<<"Authorizing-ID">>
                                          ,<<"Authorizing-Type">>
                                          ,<<"Outbound-Callee-ID-Name">>
                                          ,<<"Outbound-Callee-ID-Number">>
                                          ,<<"Retain-CID">>
                                          ]}
      ,{<<"Ignore-Early-Media">>, 'true'}
      ,{<<"Media">>, <<"process">>}
      ,{<<"Msg-ID">>, MsgId}
      ,{<<"Outbound-Call-ID">>, CallId}
      ,{<<"Outbound-Caller-ID-Name">>, kapps_call:caller_id_name(CalleeCall)}
      ,{<<"Outbound-Caller-ID-Number">>, kapps_call:caller_id_number(CalleeCall)}
      ,{<<"Timeout">>, CallTimeoutS}
      | kz_api:default_headers(<<"resource">>, <<"originate_req">>, ?APP_NAME, ?APP_VERSION)
      ]).

-spec create_callee_call(kz_json:object(), kapps_call:call(), kz_json:objects()) ->
          kapps_call:call().
create_callee_call(Data, CallerCall, Endpoints) ->
    Routines = [{fun kapps_call:set_account_db/2, kapps_call:account_db(CallerCall)}
               ,{fun kapps_call:set_account_id/2, kapps_call:account_id(CallerCall)}
               ,{fun kapps_call:set_authorizing_id/2, kz_json:find(<<"Endpoint-ID">>, Endpoints)}
               ,{fun kapps_call:set_authorizing_type/2, kz_json:find(<<"Endpoint-Type">>, Endpoints)}
               ,{fun kapps_call:set_caller_id_name/2, kz_json:get_ne_binary_value(<<"caller_id_name">>, Data, <<"Doorman">>)}
               ,{fun kapps_call:set_caller_id_number/2, kapps_call:caller_id_number(CallerCall)}
               ,{fun kapps_call:set_custom_channel_var/3, <<"Retain-CID">>, <<"true">>}
               ,{fun kapps_call:set_owner_id/2, kz_json:find(<<"owner_id">>, Endpoints)}
               ,{fun kapps_call:set_resource_type/2, <<"audio">>}
               ],
    kapps_call:exec(Routines, kapps_call:new()).
