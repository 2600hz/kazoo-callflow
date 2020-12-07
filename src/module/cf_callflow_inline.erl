%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc Callflow action to branch the call to a callflow defined in the module data.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`flow'</dt>
%%%   <dd>`object()', The flow to execute.</dd>
%%% </dl>
%%%
%%% @author Karl Anderson
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_callflow_inline).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2
        ]).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    case kz_json:get_ne_json_value([<<"flow">>], Data) of
        'undefined' ->
            lager:info("could not branch to flow with config: ~p", [Data]),
            cf_exe:continue(Call);
        Flow ->
            lager:info("branching to flow ~p", [Data]),
            cf_exe:branch(Flow, Call)
    end.
