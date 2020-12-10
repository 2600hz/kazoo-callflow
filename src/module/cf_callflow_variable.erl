%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc Callflow action to branch the call to a callflow defined in a allowed doc type on the account.
%%%
%%% <h4>Data options:</h4>
%%% <dl>
%%%   <dt>`id'</dt>
%%%   <dd>`binary()', The flow to execute.</dd>
%%% </dl>
%%% <dl>
%%%   <dt>`variable'</dt>
%%%   <dd>`binary()|list()', The flow to execute.</dd>
%%% </dl>
%%%
%%% @author Sean Wysor
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_callflow_variable).

-behaviour(gen_cf_action).

-include("callflow.hrl").

-export([handle/2]).

-type variable_key() :: kz_term:api_ne_binary() | kz_term:api_ne_binaries().

-define(ALLOWED_BRANCH_DOC_TYPES, kapps_config:get_ne_binaries(?CF_CONFIG_CAT
                                                              ,<<"allowed_branch_doc_types">>
                                                              ,[<<"users">>
                                                               ,<<"devices">>
                                                               ,<<"locations">>
                                                               ,<<"groups">>
                                                               ]
                                                              )
       ).

%%------------------------------------------------------------------------------
%% @doc Entry point for this module
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    DocId = kz_json:get_ne_binary_value(<<"id">>, Data),
    Variable = normalize_variable(kz_json:get_ne_binary_value(<<"variable">>, Data)),
    lager:info("searching for variable ~s in doc: ~s", [Variable, DocId]),
    case get_variable(DocId, Variable, Call) of
        'undefined' ->
            lager:info("could not find variable ~s in doc: ~s", [Variable, DocId]),
            cf_exe:continue(Call);
        Id ->
            lager:info("branching to callflow id: ~p", [Id]),
            maybe_branch(kz_datamgr:open_cache_doc(kapps_call:account_db(Call), Id), Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Try to branch to the callflow
%% @end
%%------------------------------------------------------------------------------
-spec maybe_branch({'error', any()}|{'ok', kz_json:object()}, kapps_call:call()) -> 'ok'.
maybe_branch({'error', R}, Call) ->
    lager:error("could not branch to callflow ~p", [R]),
    cf_exe:continue(Call);
maybe_branch({'ok', JObj}, Call) ->
    maybe_branch(kz_doc:type(JObj), JObj, Call).

maybe_branch('callflows', JObj, Call) ->
    Flow = kzd_callflows:flow(JObj, kz_json:new()),
    cf_exe:branch(Flow, Call);
maybe_branch(_Type, _, Call) ->
    lager:error("failed to branch due to invalid doc type ~s", [_Type]),
    cf_exe:continue(Call).

%%------------------------------------------------------------------------------
%% @doc Open the document DocId to find the value of the variable which a callflow id
%% @end
%%------------------------------------------------------------------------------
-spec get_variable(kz_term:api_binary(), variable_key(), kapps_call:call()) -> kz_term:api_binary().
get_variable('undefined', _Variable, _Call) ->
    lager:error("could not find document for user with undefined doc id"),
    'undefined';
get_variable(DocId, Variable, Call) ->
    lager:info("fetch doc ~p from db ~p", [DocId, kapps_call:account_db(Call)]),
    case ensure_permitted_doc(kz_datamgr:open_cache_doc(kapps_call:account_db(Call), DocId)) of
        'undefined' ->
            lager:error("failed to open user doc ~s in account ~s", [DocId, kapps_call:account_id(Call)]),
            'undefined';
        JObj ->
            kz_json:get_ne_json_value(Variable, JObj)
    end.

%%------------------------------------------------------------------------------
%% @doc ensure the doc is an allowed doc type or return undefined
%% @end
%%------------------------------------------------------------------------------
-spec ensure_permitted_doc({'ok', kz_json:object()}|{'error', any()}) -> kz_json:object() | 'undefined'.
ensure_permitted_doc({'ok', JObj}) ->
    Type = kz_doc:type(JObj),
    case lists:member(Type, ?ALLOWED_BRANCH_DOC_TYPES) of
        'true' -> JObj;
        'false' ->
            lager:error("invalid type ~p in doc ~p", [Type, kz_doc:id(JObj)]),
            'undefined'
    end;
ensure_permitted_doc({'error', _}) ->
    lager:error("failed to open doc"),
    'undefined'.

%%------------------------------------------------------------------------------
%% @doc Normalize variable. Variable is a json path, so we should accept
%% binary, or a path and ignore others, since the schema requires this to be a string
%% this also supports a dot.delimited.path  which is converted to a list
%% So if ones wants to look into a deep json object, path `[<<"v1">>, <<"v2">>]'
%% can be used to get the value.
%% @end
%%------------------------------------------------------------------------------
-spec normalize_variable(variable_key() | kz_json:path()) -> variable_key().
normalize_variable('undefined') ->
    'undefined';
normalize_variable(Variable) when is_list(Variable) ->
    lists:reverse([kz_json:normalize_key(V)
                   || V <- Variable,
                      not kz_term:is_empty(V)
                  ]
                 );
normalize_variable(?NE_BINARY = Variable) ->
    normalize_variable(binary:split(Variable, <<".">>, ['global']));
normalize_variable(_JObj) ->
    lager:debug("unsupported variable name"),
    'undefined'.
