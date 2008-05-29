%%%-------------------------------------------------------------------
%%% File    : task_master.erl
%%% Author  : Michael Melanson <michael@codeshack.ca>
%%% Description : Manages the task queue
%%%
%%% Created : 26 May 2008 by Michael Melanson <michael@codeshack.ca>
%%%-------------------------------------------------------------------
-module(task_master).

-behaviour(gen_server).

%% API
-export([start_link/0, request_next_task/0, post_result/2, insert_task/1,
         queue_lengths/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("task.hrl").
-include("result.hrl").

-define(SERVER, ?MODULE).

-define(QUERY_INTERVAL, 3600000).

-record(state, {worker_queue, task_queue}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

request_next_task() ->
    gen_server:cast(?SERVER, {request_next_task, self()}).

post_result(Task, Result) ->
    gen_server:cast(?SERVER, {post_result, Task, Result}).

queue_lengths() ->
    gen_server:call(?SERVER, queue_lengths).

insert_task(Task) when is_record(Task, task) ->
    gen_server:cast(?SERVER, {insert_task, Task});
insert_task(Url) ->
    insert_task(#task{url=Url}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{worker_queue = queue:new(),
                task_queue = queue:new()}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(queue_lengths, _From, State) ->
    {reply, {queue:len(State#state.worker_queue),
             queue:len(State#state.task_queue)}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({request_next_task, Pid}, State) ->
    case queue:is_empty(State#state.task_queue) of
        true ->
            {noreply,
             State#state{worker_queue=queue:in(Pid, State#state.worker_queue)}};

        false ->
            {{value, Task}, NewTaskQueue} = queue:out(State#state.task_queue),
            gen_server:cast(Pid, {task, Task}),
            {noreply, State#state{task_queue=NewTaskQueue}}
    end;

handle_cast({post_result, Task, Result}, State) ->
    lists:foreach(fun(T) ->
                          case get(T) of
                              undefined ->
                                  insert_task(T),
                                  put(T, new);
                              
                              _Other ->
                                  % Already got this task
                                  ok
                          end                          
                  end,
                  Result#result.links),

    {ok, Timer} = timer:apply_after(?QUERY_INTERVAL, ?MODULE,
                                    insert_task, [Task]),
    put(Task, Timer),

    {noreply, State};

handle_cast({insert_task, Task}, State) ->
    case queue:is_empty(State#state.worker_queue) of
        true ->
            {noreply,
             State#state{task_queue=queue:in_r(Task,
                                               State#state.task_queue)}};
        false ->
            {{value, Worker}, NewWorkerQueue} =
             queue:out(State#state.worker_queue),

            gen_server:cast(Worker, {task, Task}),
            {noreply, State#state{worker_queue=NewWorkerQueue}}
    end.
             

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
