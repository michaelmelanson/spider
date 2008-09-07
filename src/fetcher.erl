%%%-------------------------------------------------------------------
%%% File    : fetcher.erl
%%% Author  : Michael Melanson <michael@codeshack.ca>
%%% Description : Worker process for spidering the web
%%%
%%% Created : 26 May 2008 by Michael Melanson <michael@codeshack.ca>
%%%-------------------------------------------------------------------
-module(fetcher).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("task.hrl").
-include("result.hrl").

-define(SERVER, ?MODULE).
-define(HEADERS(Host),
        [{"Host", Host},
         {"User-Agent", "a-priori spiderbot (michael@codeshack.ca)"},
         {"Accept", "text/xml"}]).
-record(state, {}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
     gen_server:start_link( ?MODULE, [], []).

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
    task_master:request_next_task(),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({task, Task}, State) ->
    Result = process_task(Task),
    task_master:post_result(Task, Result),

    task_master:request_next_task(),
    {noreply, State}.

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

process_task(Task) ->
    Url = Task#task.url,

    io:format("~p Processing ~p~n", [self(), Url]),

    {http, Host, Port, File} = parse(Url),

    case http:request(get, {Url, ?HEADERS(Host)},
                      [], [{body_format, string}]) of
        {ok, {{_Version, 200, _Reason}, _Headers, Body}} ->
            Parsed = mochiweb_html:parse(Body),
	  
	    % Extracts all links from the document and ensures they
	    % are within the sandbox
            Links = filter_regex(extract_document_links(Parsed, {http, Host, Port, File}), Task#task.sandboxRegex),

	   
            %DocumentText = clean_document(Parsed),
            %TermFrequencies = clustering:term_frequencies(DocumentText),

            #result{status=success, body=Body,
                    code="", links=Links};

        {ok, {{_Version, 404, _Reason}, _Headers, _Body}} ->
            #result{status=failure, code=404};

        Other ->
            io:format("<~p> Unknown return: ~p~n", [self(), Other]),
            #result{status=failure, code=Other}
    end.

extract_document_links(Html, {http, Host, Port, File}) ->
    BinaryLinks = lists:flatten(extract_links(Html)),
    StringLinks = lists:map(fun(X) -> binary_to_list(X) end,
                            BinaryLinks),
    CleanedLinks = clean_links(StringLinks, {http, Host, Port, File}),
    
    lists:filter(fun(dud) -> false;
                    (_X) -> true
                 end, CleanedLinks).


extract_links({<<"HTML">>, Attrs, Contents}) ->
    extract_links({<<"html">>, Attrs, Contents});
extract_links([{<<"A">>, Attrs, Contents}|Tail]) ->
    extract_links([{<<"a">>, Attrs, Contents}|Tail]);

extract_links({<<"html">>, _Attrs, Contents}) -> extract_links(Contents);
extract_links([{<<"a">>, Attrs, _Text}|Tail]) ->
    case lists:keysearch(<<"href">>, 1, Attrs) of
        {value, {<<"href">>, Link}} ->
            [Link|extract_links(Tail)];
        _Other ->
            extract_links(Tail)
    end;
extract_links([{_Tag, _Attrs, Children}|Tail]) ->
    [extract_links(Children)|extract_links(Tail)];
extract_links([_Head|Tail]) -> extract_links(Tail);
extract_links(X) when is_binary(X) -> [];
extract_links([]) -> [];
extract_links(X) ->
%    io:format("DEBUG: extract_links(~p)~n", [X]),
    [].

clean_links(Links, {http, Host, Port, File}) ->
    lists:map(fun("") -> dud; % Probably an AJAX link.
                 ("javascript:" ++ _Tail) -> dud; % Don't care about JS
                 ("http:") -> dud; % These appear on Google pages sometimes...
                 ("#") -> dud; % Ignore page-local links
                 ("/" ++ Tail) -> % Site-relative URL, convert to absolute
		      case Port of
			  80 ->"http://" ++ Host ++ "/" ++ Tail;
			  _ ->"http://" ++Host++":"+ integer_to_list(Port) ++ "/" ++ Tail
		      end;   
                 ("mailto:" ++ _Tail) -> dud; % Mail links... don't care!
                 ("http://" ++ Tail) -> "http://" ++ Tail;
                 (Other) ->
                      io:format("Dud link: ~p~n", [Other]),
                      dud
              end, Links).

clean_document(List) when is_list(List) ->
    lists:map(fun clean_document/1, List);
clean_document({_Tag, _Attrs, Contents}) -> clean_document(Contents);
clean_document(Text) when is_binary(Text) -> Text;
clean_document(_) -> [].

parse([$h,$t,$t,$p,$:,$/,$/|T]) ->  parse_http(T);
parse([$f,$t,$p,$:,$/,$/|_T])    ->  {error, no_ftp};
parse([$f,$i,$l,$e,$:,$/,$/|F]) ->  {file, F};
parse(_X)                        ->  {error, unknown_url_type}.

parse_http(X) ->
    case string:chr(X, $/) of
        0 ->
            %% not terminated by "/" (sigh)
            %% try again
            parse_http(X ++ "/");
        N ->
            %% The Host is up to the first "/"
            %% The file is everything else
            Host = string:substr(X, 1, N-1),
            File = string:substr(X, N, length(X)),
            %% Now check to see if the host name contains a colon
            %% i.e. there is an explicit port address in the hostname
            case string:chr(Host, $:) of
                0 ->
                    %% no colon
                    Port = 80,
                    {http, Host, Port, File};
                M ->
                    Site = string:substr(Host,1,M-1),
                    case (catch list_to_integer(
                                  string:substr(Host, M+1, length(Host)))) of
                        {'EXIT', _} ->
                            {http, Site, 80, File};
                        Port ->
                            {http, Site, Port, File}
                    end
            end
    end.

% In order to assemble fully qualified links from relative ones, we need
% to figure out the base href of a document, given a link; this is a naive
% and buggy skeleton I'm committing at 2:41a :)
get_base_href(Url) -> 
    X = lists:reverse(Url),
    scan_for_slash(X).

scan_for_slash(X) ->
    [FirstChar|Rest] = X,
    case FirstChar of
	$/ -> lists:reverse(Rest);
	_  -> scan_for_slash(Rest)
    end.


% Filters a list for all items that match a given regular expression. 
% Items with no match are discarded
filter_regex(ItemList, Regex) ->
    lists:filter(fun(Item) ->
		   case regexp:first_match(Item, Regex) of
		       {match, _, _} -> true;
		       _ -> false
		   end
	   end,
	   ItemList).

