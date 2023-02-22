%%%-------------------------------------------------------------------
%% @doc ep2psharing top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(ep2psharing_peer_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(MAIN_SUP, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?MAIN_SUP}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags =
        #{strategy => one_for_one,
          intensity => 5,
          period => 10},
    Peer =
        #{id => peer,
          start => {ep2psharing_peer, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    WorkerSup =
        #{id => worker_sup,
          start => {ep2psharing_worker_sup, start_link, []},
          restart => permanent,
          shutdown => infinity,
          type => supervisor},
    {ok, {SupFlags, [Peer, WorkerSup]}}.

%% internal functions
