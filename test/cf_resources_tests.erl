%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2022, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_resources_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_fixturedb/include/kz_fixturedb.hrl").

get_caller_id_test_() ->
    {'setup'
    ,fun get_caller_id_setup/0
    ,fun get_caller_id_cleanup/1
    ,fun get_caller_id/1
    }.

get_caller_id_setup() ->
    Pid = kz_fixturedb_util:start_me('true'),
    Pid.

get_caller_id_cleanup(Pid) ->
    kz_fixturedb_util:stop_me(Pid).

get_caller_id(_SetupData) ->
    Data = kz_json:from_list([{<<"caller_id_type">>, <<"external">>}]),
    Test = fun(Call, ShouldEnforceAccountCID)-> cf_resources:get_caller_id(Data, Call, ShouldEnforceAccountCID) end,

    UserCID = {<<"user-external-number">>, <<"user-external-name">>},
    %% +19995552600 number is configured within account0000000000000000000000003 account db.
    AccountCID = {<<"+19995552600">>, <<"account-external-name">>},

    UserCIDCall = new_call(<<"account0000000000000000000000003">>, UserCID),

    [{"Not enforcing account cid", ?_assertMatch(UserCID, Test(UserCIDCall, 'false'))}
    ,{"Enforcing account cid", ?_assertMatch(AccountCID, Test(UserCIDCall, 'true'))}
    ].


%% Helpers
-spec new_call(kz_term:ne_binary(), kz_attributes:cid()) -> kapps_call:call().
new_call(AccountId, {CIDNumber, CIDName}) ->
    kapps_call:exec([{fun kapps_call:set_account_id/2, AccountId}
                    ,{fun kapps_call:set_caller_id_name/2, CIDName}
                    ,{fun kapps_call:set_caller_id_number/2, CIDNumber}
                    ]
                   ,kapps_call:new()
                   ).
