%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2022, 2600Hz
%%% @doc
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_listener_sup).

-behaviour(supervisor).

-include("callflow.hrl").

-define(SERVER, ?MODULE).

-export([start_link/0]).
-export([init/1]).
-export([forward/1]).

-define(CHILDREN(A), [?WORKER_ARGS_TYPE('cf_listener', [A], 'temporary')]).

%% ===================================================================
%% API functions
%% ===================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the supervisor
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    {'ok', Pid} = supervisor:start_link({'local', ?SERVER}, ?MODULE, []),
    _ = kz_process:spawn(fun start_workers/1 , [Pid]),
    {'ok', Pid}.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%%------------------------------------------------------------------------------
%% @doc Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%% @end
%%------------------------------------------------------------------------------
-spec init(list()) -> kz_types:sup_init_ret().
init([]) ->
    RestartStrategy = 'simple_one_for_one',
    MaxRestarts = 0,
    MaxSecondsBetweenRestarts = 1,
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    {'ok', {SupFlags, ?CHILDREN(child_args())}}.

-spec child_args() -> map().
child_args() ->
    #{instance => instance_name()
     ,shared => cfg_shared_listener()
     ,share_type => cfg_shared_listener_type()
     ,hash_header => cfg_shared_listener_hash_header()
     }.

-spec instance_name() -> kz_term:ne_binary().
instance_name() ->
    kz_binary:rand_hex(16).

-spec cfg_shared_listener() -> boolean().
cfg_shared_listener() ->
    kz_app_config:is_true(?APP, <<"callflow_listeners_shared_instance">>, 'false').

-spec cfg_shared_listener_hash_header() -> kz_term:ne_binary().
cfg_shared_listener_hash_header() ->
    kz_app_config:get_ne_binary(?APP, <<"callflow_listeners_shared_instance_hash_header">>, <<"call-id">>).

cfg_shared_listener_type() ->
    kz_app_config:get_atom(?APP, <<"callflow_listeners_shared_instance_type">>, cfg_default_shared_listener_type()).

cfg_default_shared_listener_type() ->
    case cfg_listeners() of
        1 -> queue;
        _ -> hashed
    end.

cfg_listeners() ->
    lists:max([1, kz_app_config:get_integer(?APP, <<"callflow_listeners">>, 5)]).

-spec forward(Msg) -> {'forward', Msg}.
forward(Msg) ->
    Listeners = supervisor:which_children(?MODULE),
    Size = length(Listeners),
    Selected = rand:uniform(Size),
    {_, Listener, _, _} = lists:nth(Selected, Listeners),
    Listener ! {forward, Msg}.

-spec start_workers(pid()) -> ok.
start_workers(Pid) ->
    Workers = cfg_listeners(),
    Pause = kz_app_config:get_integer(?APP, <<"callflow_listeners_start_pause_ms">>, ?MILLISECONDS_IN_SECOND * 3),
    lager:debug("starting ~B workers with ~Bms pause between", [Workers, Pause]),
    lists:foreach(fun(I) -> start_worker(I, Pid, Pause) end, lists:seq(1, Workers)).

-spec start_worker(integer(), pid(), integer()) -> 'ok'.
start_worker(Instance, Pid, Pause) ->
    _ = supervisor:start_child(Pid, [Instance]),
    timer:sleep(Pause).
