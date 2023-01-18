%%%-------------------------------------------------------------------
%% @doc erlang_p2p_file_sharing public API
%% @end
%%%-------------------------------------------------------------------

-module(erlang_p2p_file_sharing_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    erlang_p2p_file_sharing_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
