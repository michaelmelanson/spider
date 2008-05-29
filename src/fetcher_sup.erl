%%%-------------------------------------------------------------------
%%% File    : fetcher_sup.erl
%%% Author  : Michael Melanson <michael@codeshack.ca>
%%% Description : Supervisor for fetcher processes
%%%
%%% Created : 26 May 2008 by Michael Melanson <michael@codeshack.ca>
%%%-------------------------------------------------------------------
-module(fetcher_sup).

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
    Children = make_children(N),
    {ok,{{one_for_one,3,5}, Children}}.

%%====================================================================
%% Internal functions
%%====================================================================
make_children(0) -> [];
make_children(N) ->
    [{{fetcher, N}, {fetcher, start_link, []},
      permanent, 2000, worker, [fetcher]} 
     | make_children(N-1)].
