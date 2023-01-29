%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(ep2psharing_worker_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_leecher/3]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 2,
          period => 10},
    LeecherSpecs =
        #{id => leecher,
          start => {ep2psharing_leecher, start_link, []},
          shutdown => brutal_kill},
    {ok, {SupFlags, [LeecherSpecs]}}.

start_leecher(DownloadRequest, ExistingPieces, File) ->
    {ok, _} = supervisor:start_child(?MODULE, [DownloadRequest, ExistingPieces, File]),
    ok.
