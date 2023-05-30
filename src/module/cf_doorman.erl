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
-export([contact_callee/4]).
-export([handle_termination/3]).

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
    play_ringtone_to_caller(Data, Call),
    lager:info("caller has recorded message (~s) and is ringing now", [RecordingId]),
    contact_callee(Data, kapps_call:kvs_store('caller_recording_id', RecordingId, Call)).

-spec get_caller_recording(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
get_caller_recording(Data, Call) ->
    prompt_caller(Call),
    RecordingId = record_caller(Data, Call),
    thank_caller(Data, Call),
    RecordingId.

-spec record_caller(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
record_caller(Data, Call) ->
    RecordingId = <<(kz_binary:rand_hex(16))/binary, ".mp3">>,
    {'ok', JObj} = kapps_call_command:b_record(RecordingId
                                           ,?ANY_DIGIT
                                           ,recording_limit(Data)
                                           ,Call
                                           ),
    case kz_json:get_binary_value(<<"Channel-Answer-State">>, JObj) of
        <<"answered">> -> RecordingId;
        <<"hangup">> ->
            lager:info("Caller hung up during message recording"),
            exit('normal');
        Other ->
            lager:error("Unhandled channel answer state: ~p", [Other]),
            exit('normal')
    end.

-spec recording_limit(kz_json:object()) -> number().
    recording_limit(Data) ->
    Limit = kz_json:get_integer_value(<<"recording_limit">>, Data, 8),
    lager:debug("recording limit: ~p", [Limit]),
    kz_math:clamp(16, 2, Limit).

prompt_caller(Call) ->
    Text = <<"Hi there."
        >>,
    try
        {'ok', _} = kapps_call_command:b_tts(Text, Call)
    catch
        'error':{'badmatch',{'error', 'channel_hungup'}} ->
            lager:info("Caller hung up during doorman prompt"),
            exit('normal')
    end.

thank_caller(_Data, Call) ->
    Text = <<"Thank you.">>,
    try
        {'ok', _} = kapps_call_command:b_tts(Text, Call)
    catch
        'error':{'badmatch',{'error', 'channel_hungup'}} ->
            lager:debug("Caller hung up during doorman thank message"),
            exit('normal')
    end.

play_ringtone_to_caller(Data, Call) ->
    Tones = cf_tones:convert_tones(tones(Data)),
    kapps_call_command:tones(Tones, Call).

tones(Data) ->
    [kz_json:set_value(<<"repeat">>, 4, Tone)
     || Tone <- kz_json:get_list_value(<<"tones">>, Data, [us_tone()])
    ].

-spec us_tone() -> kz_json:object().
us_tone() ->
    kz_json:from_list([{<<"duration_on">>, 2000}
                      ,{<<"duration_off">>, 4000}
                      ,{<<"frequencies">>, [440,480]}
                      ]).

hangup_caller(Call) ->
    Text = <<"The party you have dialed could not be reached. Good bye!">>,
    lager:debug("hangup_caller: ~p", [Call]),
    {'ok', _} = kapps_call_command:b_flush(Call),
    {'ok', _} = kapps_call_command:b_tts(Text, Call),
    'ok' = kapps_call_command:hangup(Call),
    cf_exe:hard_stop(Call).

contact_callee(Data, Call) ->
    EndpointId = kz_doc:id(Data),

    Props = kz_json:from_list([{<<"source">>, <<?MODULE_STRING>>}]),

    case kz_endpoint:build(EndpointId, Props, Call) of
        {'ok', Endpoints} ->
            contact_callee(Data, Call, Endpoints);
        {'error', _E} ->
            lager:info("failed to build endpoint ~s: ~p", [EndpointId, _E]),
            hangup_caller(Call)
    end.

-spec contact_callee(kz_json:object(), kapps_call:call(), kz_json:objects()) -> 'ok'.
contact_callee(Data, CallerCall, Endpoints) ->
    CalleeCall = create_callee_call(Data, CallerCall, Endpoints),
    contact_callee(Data, CallerCall, Endpoints, CalleeCall).

-spec contact_callee(kz_json:object(), kapps_call:call(), kz_json:objects(), kapps_call:call()) -> 'ok'.
contact_callee(Data, CallerCall, Endpoints, CalleeCall) ->
    case originate_callee(Data, CallerCall, Endpoints, CalleeCall) of
        {'ok', OriginateResp} ->
            lager:info("callee successfully answered the call"),
            UpdatedCallee = update_callee_call(OriginateResp, CalleeCall),
            cf_exe:add_termination_handler(CallerCall, {?MODULE, 'handle_termination', [UpdatedCallee]}),
            update_logging_id(CallerCall, UpdatedCallee),
            doorman_menu(Data, CallerCall, UpdatedCallee);
        {'error', _E} ->
            lager:info("failed to contact callee: ~p", [_E]),
            hangup_caller(CallerCall)
    end.

-spec doorman_menu(kz_json:object(), kapps_call:call(), kapps_call:call()) -> 'ok'.
doorman_menu(Data, CallerCall, CalleeCall) ->
    NoopId = doorman_menu_prompt(CallerCall, CalleeCall),
    lager:info("waiting for callee to choose from menu"),
    kz_events:bind_call_id(kapps_call:call_id(CalleeCall)),

    CalleeResponse = kapps_call_command:collect_digits(1
                                          ,kapps_call_command:default_collect_timeout()
                                          ,2 * ?MILLISECONDS_IN_SECOND
                                          ,NoopId
                                          ,CalleeCall
                                          ),
    kz_events:unbind_call_id(kapps_call:call_id(CalleeCall)),
    case CalleeResponse of
        {'ok', <<>>} ->
            lager:info("callee chose to hangup"),
            kapps_call_command:hangup(CalleeCall),
            hangup_caller(CallerCall);
        {'ok', Choice} ->
            lager:info("callee chose ~p", [Choice]),
            handle_choice(Data, CallerCall, CalleeCall, Choice);
        {'error', 'channel_hungup'} ->
            lager:info("Callee hungup without making choice"),
            hangup_caller(CallerCall);
        {'error', _E} ->
            lager:error("error waiting for callee to choose: ~p", [_E]),
            hangup_caller(CallerCall)
    end.

-spec doorman_menu_prompt(kapps_call:call(), kapps_call:call()) -> kz_term:ne_binary().
doorman_menu_prompt(CallerCall, CalleeCall) ->
    %% When you answer the incoming call the following message is played:
    %% “Call from” + recording is played +
    %% "Press 1 to answer;" +
    %% "Press 2 to answer with recording enabled;" +
    %% "Press 3 to send the call to voicemail;" +
    %% "Press 4 to reject or simply hangup."
    lager:info("playing doorman menu to callee"),
    AudioMacro = [{'tts', <<"Call from">>}
                 ,{'play', kapps_call:kvs_fetch('caller_recording_id', CallerCall)}
                 ,{'tts', <<"Press 1 to answer">>}
                 ,{'tts', <<"Press 2 to answer with recording enabled">>}
                 ,{'tts', <<"Press 3 to send the call to voicemail">>}
                 ,{'tts', <<"Press 4 to reject or simply hangup">>}
                 ],
    NoopId = kapps_call_command:audio_macro(AudioMacro, CalleeCall),
    NoopId.

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
handle_choice(_Data, CallerCall, CalleeCall, ?DTMF_HANGUP) ->
    lager:info("callee has selected not to take the call (pressed ~p)", [?DTMF_HANGUP]),
    kapps_call_command:hangup(CalleeCall),
    hangup_caller(CallerCall);
handle_choice(Data, CallerCall, CalleeCall, _DTMF) ->
    lager:info("callee has selected option which doesn't exist - (pressed ~p)", [_DTMF]),
    kz_events:bind_call_id(kapps_call:call_id(CalleeCall)),
    Text = <<"Wrong option, try again please.">>,
    try
        {'ok', _} = kapps_call_command:b_tts(Text, CalleeCall)
    catch
        'error':{'badmatch',{'error', 'channel_hungup'}} ->
            lager:debug("Callee hung up during doorman prompt message"),
            exit('normal')
    end,
    kz_events:unbind_call_id(kapps_call:call_id(CalleeCall)),
    doorman_menu(Data, CallerCall, CalleeCall).

pickup_caller(TargetCallId, CalleeCall) ->
    kapps_call_command:pickup(TargetCallId, CalleeCall),
    kapps_call_command:wait_for_hangup().

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
    TerminationMFA = {?MODULE, 'handle_termination', [CalleeCall]},
    cf_exe:add_termination_handler(CallerCall, TerminationMFA),

    Resp = case originate_request(Request) of
        {'error', _E}=Error -> Error;
        {'ok', JObjs} ->
            handle_originate_resp(lists:partition(fun kapi_resource:originate_resp_v/1, JObjs))
    end,

    cf_exe:remove_termination_handler(CallerCall, TerminationMFA),
    Resp.

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
    lager:debug("got originate response: ~p", [Resp]),
    kapi_resource:originate_resp_v(Resp)
        orelse kz_api:error_resp_v(Resp).

build_originate_request(Data, CalleeCall, Endpoints, _CallerCallId) ->
    CCVs = [{<<"Account-ID">>, kapps_call:account_id(CalleeCall)}
           ,{<<"Inherit-Codec">>, <<"false">>}
           ,{<<"Authorizing-Type">>, kapps_call:authorizing_type(CalleeCall)}
           ,{<<"Authorizing-ID">>, kapps_call:authorizing_id(CalleeCall)}
           ],
    MsgId = kz_binary:rand_hex(16),
    CallId = kapps_call:call_id_direct(CalleeCall),
    CallTimeoutS = kz_json:get_integer_value(<<"call_timeout">>, Data, 30),

    kz_json:from_list(
      [{<<"Application-Name">>, <<"park">>}
      ,{<<"Application-Data">>, kz_json:new()}
      ,{<<"Continue-On-Fail">>, 'false'}
      ,{<<"Custom-Channel-Vars">>, kz_json:from_list(CCVs)}
      ,{<<"Dial-Endpoint-Method">>, <<"simultaneous">>}
      ,{<<"Endpoints">>, Endpoints}
    %   ,{<<"Existing-Call-ID">>, CallerCallId}
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
               ,{fun kapps_call:set_call_id/2, iolist_to_binary([kz_binary:rand_hex(16), "-doorman"])}
            %    ,{fun kapps_call:set_authorizing_type/2, kz_json:find(<<"Endpoint-Type">>, Endpoints)}
               ,{fun kapps_call:set_caller_id_name/2, kz_json:get_ne_binary_value(<<"caller_id_name">>, Data, <<"Doorman">>)}
               ,{fun kapps_call:set_caller_id_number/2, kapps_call:caller_id_number(CallerCall)}
               ,{fun kapps_call:set_custom_channel_var/3, <<"Retain-CID">>, <<"true">>}
            %    ,{fun kapps_call:set_owner_id/2, kz_json:find(<<"owner_id">>, Endpoints)}
               ,{fun kapps_call:set_resource_type/2, <<"audio">>}
               ],
    kapps_call:exec(Routines, kapps_call:new()).

-spec handle_termination(kapps_call:call(), kz_json:object(), kz_json:object()) -> 'ok'.
handle_termination(CallerCall, HangupInfo, CalleeCall) ->
    lager:info("Premature termination of Caller (A-leg) ~s prior to bridge", [kapps_call:call_id_direct(CallerCall)]),
    lager:debug("Caller (A-leg) hangup info: ~p", [HangupInfo]),
    case kapps_call_command:b_channel_status(CalleeCall) of
        {'ok', JObj} ->
            case kz_json:get_boolean_value(<<"Answered">>, JObj) of
                'true' ->
                    lager:debug("Callee (B-leg) ~s has already answered. Terminating it.", [kapps_call:call_id_direct(CalleeCall)]),
                    kapps_call_command:hangup(CalleeCall);
                'false' ->
                    UpdatedCalleeCall = kapps_call:from_json(JObj, CalleeCall),
                    lager:debug("Callee (B-leg) ~s has not answered yet. Terminating it.", [kapps_call:call_id_direct(UpdatedCalleeCall)]),
                    _ = freeswitch:api(binary_to_atom(kapps_call:switch_nodename(UpdatedCalleeCall)), 'uuid_kill', kapps_call:call_id_direct(UpdatedCalleeCall))
            end;
        {'error','not_found'} ->
            lager:debug("Callee (B-leg) ~s was not found. Already terminated", [kapps_call:call_id_direct(CalleeCall)]);
        {'error', _Else} ->
            lager:error("Cannot obtain Callee channel status and terminate the call: ~p", [_Else])
    end,
    'ok'.
