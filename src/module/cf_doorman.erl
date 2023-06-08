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

-type failure_reason() ::
        'callee_endpoint_fail' |
        'callee_busy' |
        'callee_no_answer' |
        'callee_error' |
        'callee_hungup' |
        'caller_timeout'.

-type contact_callee_return() ::
        {'error', failure_reason()} |
        {'error', 'caller_hungup', kapps_call:call()} |
        {'ok', binary(), kapps_call:call()}.

%%------------------------------------------------------------------------------
%% @doc Doorman entry point
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    kapps_call_command:answer(Call),
    CallerCall = get_caller_recording(Data, Call),
    play_ringtone_to_caller(Data, CallerCall),
    lager:info("caller has recorded message (~s) and is ringing now", [kapps_call:kvs_fetch('caller_recording_id', CallerCall)]),
    _ = case contact_callee(Data, CallerCall) of
            {'ok', Choice, CalleeCall} ->
                handle_choice(Choice, Data, CallerCall, CalleeCall);
            {'error', 'callee_endpoint_fail'} ->
                lager:info("failed to build callee endpoint"),
                hangup_caller(CallerCall);
            {'error', 'callee_busy'} ->
                lager:info("callee is busy"),
                hangup_caller(CallerCall);
            {'error', 'callee_no_answer'} ->
                lager:info("callee did not answer"),
                hangup_caller(CallerCall);
            {'error', 'callee_error'} ->
                lager:info("callee is unreachable"),
                hangup_caller(CallerCall);
            {'error', 'callee_hungup'} ->
                hangup_caller(CallerCall);
            {'error', 'caller_hungup', CalleeCall} ->
                handle_caller_termination(CallerCall, CalleeCall);
            {'error', 'caller_timeout'} ->
                lager:info("caller waiting timeout expired"),
                hangup_caller(CallerCall)
        end,
    maybe_delete_recording(kapps_call:kvs_fetch('caller_recording_id', CallerCall)),
    cf_exe:continue(Call).

-spec get_caller_recording(kz_json:object(), kapps_call:call()) -> kapps_call:call().
get_caller_recording(Data, Call) ->
    prompt_caller(Call),
    RecordingId = record_caller(Data, Call),
    UpdatedCall = kapps_call:kvs_store('caller_recording_id', RecordingId, Call),
    thank_caller(Data, UpdatedCall),
    UpdatedCall.

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
            lager:info("caller hung up during message recording"),
            maybe_delete_recording(RecordingId),
            exit('normal');
        Other ->
            lager:error("unhandled channel answer state: ~p", [Other]),
            maybe_delete_recording(RecordingId),
            exit('normal')
    end.

-spec recording_limit(kz_json:object()) -> number().
recording_limit(Data) ->
    Limit = kz_json:get_integer_value(<<"recording_limit">>, Data, 8),
    lager:debug("recording limit: ~p", [Limit]),
    kz_math:clamp(16, 2, Limit).

prompt_caller(Call) ->
    Beep = kz_json:from_list([{<<"Frequencies">>, [<<"440">>]}
                             ,{<<"Duration-ON">>, <<"500">>}
                             ,{<<"Duration-OFF">>, <<"100">>}
                             ]),
    AudioMacro = [{'tts', <<"Hi there. Record your name and a short message.">>}
                 ,{'tones', [Beep]}
                 ],
    NoopId = kapps_call_command:audio_macro(AudioMacro, Call),
    case kapps_call_command:wait_for_noop(Call, NoopId) of
        {'ok', _} -> 'ok';
        {'error', 'channel_hungup'} ->
            lager:debug("caller hung up during doorman's prompt"),
            exit('normal')
    end.

thank_caller(_Data, Call) ->
    Text = <<"Thank you.">>,
    case kapps_call_command:b_tts(Text, Call) of
        {'ok', _} -> 'ok';
        {'error', 'channel_hungup'} ->
            lager:debug("caller hung up during doorman's thank message"),
            maybe_delete_recording(kapps_call:kvs_fetch('caller_recording_id', Call)),
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
    {'ok', _} = kapps_call_command:b_flush(Call),
    {'ok', _} = kapps_call_command:b_tts(Text, Call),
    'ok' = kapps_call_command:hangup(Call),
    cf_exe:hard_stop(Call).

%%     If 1 is pressed the call is connected
%%     If 2 is pressed the call is connected and both parties hear "This call is being recorded" and the callee also hears "to stop the recording press 5 at any time" when either party hangs up or the callee presses #5 the audio file with the recording is posted to this site https://webhook.site/#!/84f01ee0-1cc6-43f3-afa9-f10639c041f4
%%     If 3 is pressed the caller is sent to voicemail and link to file is posted to this site https://webhook.site/#!/84f01ee0-1cc6-43f3-afa9-f10639c041f4, Voicemail is also transcribed and the transcription is sent to the forwarding number (one that owns the app)
%%     If 4 is pressed call is ended
handle_choice(?DTMF_CONNECT_CALL, _Data, CallerCall, CalleeCall) ->
    TargetCallId = kapps_call:call_id(CallerCall),
    lager:info("callee has chosen to accept call ~s", [TargetCallId]),
    pickup_caller(TargetCallId, CalleeCall),
    {'ok', CalleeCall};
handle_choice(?DTMF_CONNECT_RECORD, Data, CallerCall, CalleeCall) ->
    TargetCallId = kapps_call:call_id(CallerCall),
    lager:info("callee has chosen to connect and record the call ~s", [TargetCallId]),

    RecordData = kz_json:set_values([{<<"origin">>, <<"callflow : " ?MODULE_STRING>>}]
                                   ,Data
                                   ),
    UpdatedCallerCall = cf_record_call:handle(RecordData, CallerCall, <<"start">>),
    _ = cf_exe:update_call(UpdatedCallerCall),
    pickup_caller(TargetCallId, CalleeCall);
handle_choice(?DTMF_VM, Data, CallerCall, CalleeCall) ->
    VMBoxId = kz_json:get_ne_binary_value(<<"vmbox_id">>, Data),
    lager:info("callee has chosen to send caller to voicemail box ~s", [VMBoxId]),

    kapps_call_command:hangup(CalleeCall),

    VMData = kz_json:from_list([{<<"action">>, <<"compose">>}
                               ,{<<"id">>, VMBoxId}
                               ]),
    cf_voicemail:handle(VMData, CallerCall).

-spec maybe_delete_recording(binary() | 'undefined') -> 'ok'.
maybe_delete_recording('undefined') -> 'ok';
maybe_delete_recording(RecordingId) ->
    RecordingFile = filename:join("/tmp", RecordingId),
    _ = file:delete(RecordingFile),
    'ok'.

-spec wait_for_calee(kz_term:pid_ref(), 'undefined' | kapps_call:call(), kapps_call:call(), timeout()) -> contact_callee_return().
wait_for_calee({CalleePid, CalleeRef}=CalleeProc, CalleeCall, CallerCall, Timeout) ->
    Start = kz_time:start_time(),
    receive
        {_Pid, 'update_callee', UpdatedCalleeCall} ->
            lager:debug("callee call updated: ~p", [kapps_call:to_json(UpdatedCalleeCall)]),
            wait_for_calee(CalleeProc, UpdatedCalleeCall, CallerCall, kz_time:decr_timeout(Timeout, Start));
        {CalleePid, CalleeResponse} ->
            erlang:demonitor(CalleeRef, ['flush']),
            CalleeResponse;
        {'DOWN', CalleeRef, 'process', _Pid, 'normal'} ->
            lager:info("callee process ended normally"),
            erlang:demonitor(CalleeRef, ['flush']),
            {'ok', 'callee_process_ended'};
        {'DOWN', CalleeRef, 'process', Pid, _Reason} ->
            lager:error("callee proces ~p exited abnormally: ~p", [Pid, _Reason]),
            erlang:demonitor(CalleeRef, ['flush']),
            {'error', 'callee_process_error'};
        {'amqp_msg', JObj} ->
            CallerCallID = kapps_call:call_id(CallerCall),
            case {kz_api:event_type(JObj), kz_call_event:call_id(JObj)} of
                {{<<"call_event">>, <<"CHANNEL_DESTROY">>}, CallerCallID} ->
                    {'error', 'caller_hungup', CalleeCall};
                {{<<"call_event">>, <<"CHANNEL_DISCONNECTED">>}, CallerCallID} ->
                    {'error', 'caller_hungup', CalleeCall};
                {_Evt, _CallId} ->
                    lager:debug("ignoring event: ~p", [JObj]),
                    wait_for_calee(CalleeProc, CalleeCall, CallerCall, kz_time:decr_timeout(Timeout, Start))
            end;
        _Other ->
            lager:debug("ignoring event: ~p", [_Other]),
            wait_for_calee(CalleeProc, CalleeCall, CallerCall, kz_time:decr_timeout(Timeout, Start))
    after
        Timeout -> {'error', 'caller_timeout'}
    end.

-spec contact_callee(kz_json:object(), kapps_call:call()) -> contact_callee_return().
contact_callee(Data, Call) ->
    EndpointId = kz_doc:id(Data),
    Props = kz_json:from_list([{<<"source">>, <<?MODULE_STRING>>}]),

    case kz_endpoint:build(EndpointId, Props, Call) of
        {'ok', Endpoints} ->
            contact_callee(Data, Call, Endpoints);
        {'error', _E} ->
            lager:error("failed to build endpoint for ~p", [EndpointId]),
            {'error', 'callee_endpoint_fail'}
    end.

-spec contact_callee(kz_json:object(), kapps_call:call(), kz_json:objects()) -> contact_callee_return().
contact_callee(Data, CallerCall, Endpoints) ->
    AMQPConsumer = kz_amqp_channel:consumer_pid(),
    AMQPChannel = kz_amqp_channel:consumer_channel(),
    CalleeProc = kz_process:spawn_monitor(fun contact_callee/6, [Data, CallerCall, Endpoints, self(), AMQPConsumer, AMQPChannel]),
    wait_for_calee(CalleeProc, 'undefined', CallerCall, 60 * ?MILLISECONDS_IN_SECOND).

contact_callee(Data, CallerCall, Endpoints, DoormanProc, AMQPConsumer, AMQPChannel) ->
    _ = kz_amqp_channel:consumer_channel(AMQPChannel),
    _ = kz_amqp_channel:consumer_pid(AMQPConsumer),

    CalleeCall = create_callee_call(Data, CallerCall, Endpoints),
    Request = build_originate_request(Data, CalleeCall, Endpoints, kapps_call:call_id(CallerCall)),
    Validator = fun(Resp) -> validate_originate_resp(Resp, CalleeCall, DoormanProc) end,

    _ = case kz_amqp_worker:call_collect(
               Request
              ,fun kapi_resource:publish_originate_req/1
              ,Validator
              ,30 * ?MILLISECONDS_IN_SECOND)
        of
            {'ok', [OriginateResp|_]} ->
                case kz_json:get_value(<<"Event-Category">>, OriginateResp) of
                    <<"resource">> ->
                        lager:info("callee answered the call ~p", [OriginateResp]),
                        UpdatedCallee = kapps_call:from_originate_resp(OriginateResp, CalleeCall),
                        DoormanProc ! {self(), 'update_callee', UpdatedCallee},
                        update_logging_id(CallerCall, UpdatedCallee),
                        kz_events:bind_call_id(kapps_call:call_id(CalleeCall)),
                        Resp = doorman_menu(UpdatedCallee),
                        kz_events:unbind_call_id(kapps_call:call_id(CalleeCall)),
                        DoormanProc ! {self(), Resp};
                    <<"error">> ->
                        case kz_json:get_value(<<"Error-Message">>, OriginateResp) of
                            <<"USER_BUSY">> ->
                                DoormanProc ! {self(), {'error', 'callee_busy'}};
                            <<"ORIGINATOR_CANCEL">> ->
                                lager:info("caller has canceled the call");
                            <<"NO_ANSWER">> ->
                                DoormanProc ! {self(), {'error', 'callee_no_answer'}};
                            _Reason ->
                                lager:debug("failed to contact callee: ~p", [_Reason]),
                                DoormanProc ! {self(), {'error', 'callee_error'}}
                        end
                end;
            {'error', _E} ->
                lager:debug("failed to contact callee: ~p", [_E]),
                DoormanProc ! {self(), {'error', 'callee_error'}}
        end,
    lager:debug("callee helper process exiting normally"),
    'ok'.

%% custom validator for two reasons:
%% 1. we want to process originate ready response, but not finish collecting responses
%% 2. we want to process error responses immediately and not wait for timeout
-spec validate_originate_resp(kz_term:api_terms(), kapps_call:call(), pid()) -> boolean().
validate_originate_resp([Resp|_], CalleeCall, DoormanProc) ->
    validate_originate_resp(kz_json:get_value(<<"Event-Name">>, Resp), Resp, CalleeCall, DoormanProc).

-spec validate_originate_resp(kz_json:api_json_term(), kz_term:api_terms(), kapps_call:call(), pid()) -> boolean().
validate_originate_resp(<<"originate_resp">>, Resp, _CalleeCall, _DoormanProc) ->
    kapi_resource:originate_resp_v(Resp)
        orelse kz_api:error_resp_v(Resp);
validate_originate_resp(<<"originate_ready">>, Resp, CalleeCall, DoormanProc) ->
    case kapi_resource:originate_ready_v(Resp) of
        'true' ->
            lager:debug("received originate ready response: ~p", [Resp]),
            OriginateUUID = kz_json:get_ne_binary_value(<<"Originate-UUID">>, Resp),
            OriginateQueue = kz_json:get_ne_binary_value(<<"Originate-Queue">>, Resp),
            ServerId = kz_json:get_value(<<"Server-ID">>, Resp),
            Routines = [
                        {fun kapps_call:from_originate_ready/2, Resp}
                       ,{fun kapps_call:kvs_store/3, 'Server-ID', ServerId}
                       ,{fun kapps_call:kvs_store/3, 'Originate-UUID', OriginateUUID}
                       ,{fun kapps_call:kvs_store/3, 'Originate-Queue', OriginateQueue}
                       ],
            UpdatedCallee = kapps_call:exec(Routines, kapps_call:from_originate_ready(Resp, CalleeCall)),
            lager:info("updated callee call: ~p, DoormanProc: ~p", [UpdatedCallee, DoormanProc]),
            DoormanProc ! {self(), 'update_callee', UpdatedCallee},
            Request = [
                       {<<"Originate-UUID">>, OriginateUUID}
                      | kz_api:default_headers(ServerId, ?APP_NAME, ?APP_VERSION)
                      ],
            Publisher = fun(P) -> kapi_dialplan:publish_originate_execute(ServerId, P) end,
            _ = kz_amqp_worker:cast(Request, Publisher),
            'false';
        'false' ->
            'true'
    end;
validate_originate_resp(_Event, Resp, _CalleeCall, _DoormanProc) ->
    kz_api:error_resp_v(Resp).

-type doorman_menu_return() :: {'ok', binary(), kapps_call:call()} | {'error', 'callee_hungup' | 'callee_error'}.

-spec doorman_menu(kapps_call:call()) -> doorman_menu_return().
doorman_menu(CalleeCall) ->
    NoopId = doorman_menu_prompt(CalleeCall),
    lager:info("waiting for callee to choose from menu"),

    CalleeResponse = kapps_call_command:collect_digits(1
                                                      ,kapps_call_command:default_collect_timeout()
                                                      ,2 * ?MILLISECONDS_IN_SECOND
                                                      ,NoopId
                                                      ,CalleeCall
                                                      ),
    case CalleeResponse of
        {'ok', <<>>} ->
            lager:info("doorman menu timeout expired, callee didn't make choice, going to hangup"),
            kapps_call_command:hangup(CalleeCall),
            {'error', 'callee_hungup'};
        {'ok', ?DTMF_CONNECT_CALL=Choice} -> {'ok', Choice, CalleeCall};
        {'ok', ?DTMF_CONNECT_RECORD=Choice} -> {'ok', Choice, CalleeCall};
        {'ok', ?DTMF_VM=Choice} -> {'ok', Choice, CalleeCall};
        {'ok', ?DTMF_HANGUP=Choice} ->
            lager:info("callee has selected not to take the call (pressed ~p)", [Choice]),
            kapps_call_command:hangup(CalleeCall),
            {'error', 'callee_hungup'};
        {'ok', BadChoice} ->
            bad_choice(BadChoice, CalleeCall),
            doorman_menu(CalleeCall);
        {'error', 'channel_hungup'} ->
            lager:info("callee hungup without making choice"),
            {'error', 'callee_hungup'};
        {'error', _E} ->
            lager:error("error waiting for callee to choose: ~p", [_E]),
            {'error', 'callee_error'}
    end.

-spec doorman_menu_prompt(kapps_call:call()) -> kz_term:ne_binary().
doorman_menu_prompt(CalleeCall) ->
    lager:info("playing doorman menu to callee"),
    AudioMacro = [{'tts', <<"Call from">>}
                 ,{'play', kapps_call:kvs_fetch('caller_recording_id', CalleeCall), ?ANY_DIGIT, <<"both">> }
                 ,{'tts', <<"Press 1 to answer">>}
                 ,{'tts', <<"Press 2 to answer with recording enabled">>}
                 ,{'tts', <<"Press 3 to send the call to voicemail">>}
                 ,{'tts', <<"Press 4 to reject or simply hangup">>}
                 ],
    kapps_call_command:audio_macro(AudioMacro, CalleeCall).

bad_choice(BadChoice, CalleeCall) ->
    lager:info("callee has selected option which doesn't exist - (pressed ~p)", [BadChoice]),
    Text = <<"Wrong option, try again please.">>,
    case kapps_call_command:b_tts(Text, CalleeCall) of
        {'ok', _} -> 'ok';
        {'error', 'channel_hungup'} ->
            lager:debug("callee hung up during doorman prompt message"),
            exit('normal');
        {'error', _E} -> lager:error("error playing tts: ~p", [_E])
    end.

pickup_caller(TargetCallId, CalleeCall) ->
    kapps_call_command:pickup(TargetCallId, CalleeCall).

-spec update_logging_id(kapps_call:call(), kapps_call:call()) -> any().
update_logging_id(CallerCall, CalleeCall) ->
    LogId = iolist_to_binary([kapps_call:call_id(CallerCall)
                             ,"-"
                             ,kapps_call:call_id(CalleeCall)
                             ]),
    kz_log:put_callid(LogId).

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
      ,{<<"Export-Custom-Channel-Vars">>, [<<"Account-ID">>
                                          ,<<"Authorizing-ID">>
                                          ,<<"Authorizing-Type">>
                                          ,<<"Outbound-Callee-ID-Name">>
                                          ,<<"Outbound-Callee-ID-Number">>
                                          ,<<"Retain-CID">>
                                          ]}
      ,{<<"Ignore-Early-Media">>, 'true'}
      ,{<<"Originate-Immediate">>, 'false'}
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
               ,{fun kapps_call:set_caller_id_name/2, kz_json:get_ne_binary_value(<<"caller_id_name">>, Data, <<"Doorman">>)}
               ,{fun kapps_call:set_caller_id_number/2, kapps_call:caller_id_number(CallerCall)}
               ,{fun kapps_call:set_custom_channel_var/3, <<"Retain-CID">>, <<"true">>}
               ,{fun kapps_call:set_resource_type/2, <<"audio">>}
               ,{fun kapps_call:kvs_store/3, 'caller_recording_id', kapps_call:kvs_fetch('caller_recording_id', CallerCall)}
               ],
    kapps_call:exec(Routines, kapps_call:new()).

-spec handle_caller_termination(kapps_call:call(), kapps_call:call()) -> 'ok'.
handle_caller_termination(CallerCall, CalleeCall) ->
    lager:info("premature termination of Caller (A-leg) ~s prior to bridge", [kapps_call:call_id_direct(CallerCall)]),
    case kapps_call_command:b_channel_status(CalleeCall) of
        {'ok', JObj} ->
            case kz_json:get_boolean_value(<<"Answered">>, JObj) of
                'true' ->
                    lager:debug("callee (B-leg) ~s has already answered. Terminating it.", [kapps_call:call_id_direct(CalleeCall)]),
                    kapps_call_command:hangup(CalleeCall);
                'false' ->
                    lager:debug("callee (B-leg) ~s has not answered yet. Canceling it.", [kapps_call:call_id_direct(CalleeCall)]),
                    cancel_callee_call(CalleeCall)
            end;
        {'error','not_found'} ->
            lager:debug("callee (B-leg) ~s was not found. Already terminated", [kapps_call:call_id_direct(CalleeCall)]);
        {'error', _Else} ->
            lager:error("cannot obtain Callee channel status and terminate the call: ~p", [_Else])
    end,
    'ok'.

cancel_callee_call(CalleeCall) ->
    Payload = [{<<"Originate-UUID">>, kapps_call:kvs_fetch(<<"Originate-UUID">>, CalleeCall)}
              | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
              ],
    kapi_dialplan:publish_originate_cancel(kapps_call:kvs_fetch(<<"Originate-Queue">>, CalleeCall),  Payload).
