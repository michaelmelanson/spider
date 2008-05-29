%%%-------------------------------------------------------------------
%%% File    : clustering.erl
%%% Author  : Michael Melanson <michael@codeshack.ca>
%%% Description : Library functions for document clustering
%%%
%%% Created : 27 May 2008 by Michael Melanson <michael@codeshack.ca>
%%%-------------------------------------------------------------------
-module(clustering).

-include("term.hrl").

%% API
-export([document_tfidf/1]).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: term_frequencies(Document) -> dict()
%% Description: Generate a set of term frequencies for the given document
%%--------------------------------------------------------------------
term_frequencies(Document) ->
    Tokens = string:tokens(Document, " ,.()"),
    TotalTokens = length(Tokens),

    Counts = lists:foldl(fun(Token, Acc) ->
                                 dict:update_counter(Token, 1, Acc)
                         end, dict:new(), Tokens),
    dict:map(fun(_Token, Count) ->
                     Count / TotalTokens
             end, Counts).

update_table(Table, Key, Document) ->    
    Tf = term_frequencies(Document),
    lists:foreach(fun({Term, Freq}) ->
                          dets:insert(Table, {{Key, Term}, Key, Term, Freq})
                  end, Tf).

%%====================================================================
%% Internal functions
%%====================================================================
