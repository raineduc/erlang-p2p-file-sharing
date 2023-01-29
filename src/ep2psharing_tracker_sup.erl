%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(ep2psharing_tracker_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags =
        #{strategy => one_for_one,
          intensity => 5,
          period => 10},
    Tracker =
        #{id => peer,
          start => {ep2psharing_tracker_server, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    {ok, {SupFlags, [Tracker]}}.
