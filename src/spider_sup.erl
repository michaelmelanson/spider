%%%-------------------------------------------------------------------
%%% File    : spider_sup.erl
%%% Author  : Michael Melanson <michael@codeshack.ca>
%%% Description : Top supervisor for the spider
%%%
%%% Created : 26 May 2008 by Michael Melanson <michael@codeshack.ca>
%%%-------------------------------------------------------------------
-module(spider_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the supervisor
%%--------------------------------------------------------------------
start_link(StartArgs) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, StartArgs).

%%====================================================================
%% Supervisor callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init(Args) -> {ok,  {SupFlags,  [ChildSpec]}} |
%%                     ignore                          |
%%                     {error, Reason}
%% Description: Whenever a supervisor is started using 
%% supervisor:start_link/[2,3], this function is called by the new process 
%% to find out about restart strategy, maximum restart frequency and child 
%% specifications.
%%--------------------------------------------------------------------
init([{pool_size, N}]) ->
    TaskMaster = {task_master, {task_master, start_link, []},
                  permanent, 2000, worker, [task_master]},
    FetcherSup = {fetcher_sup, {fetcher_sup, start_link, [[{pool_size, N}]]},
                  permanent, 2000, supervisor, [fetcher_sup]},
    StatsCollector = {stats_collector, {stats_collector, start_link, []},
                      permanent, 2000, worker, [stats_collector]},
    {ok,{{one_for_all,0,1}, [TaskMaster, FetcherSup, StatsCollector]}}.

%%====================================================================
%% Internal functions
%%====================================================================
