%%%-------------------------------------------------------------------
%% @doc ep2psharing public API
%% @end
%%%-------------------------------------------------------------------

-module(ep2psharing_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ep2psharing_peer_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
