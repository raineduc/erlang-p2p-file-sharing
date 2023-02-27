-module(ep2psharing_client).

-behaviour(gen_server).

-export([start_link/0, download/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {torrents = dict:new()}).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

download(TorrentInfoHash) ->
  gen_server:call(?MODULE, {download, TorrentInfoHash}).

init([]) ->
  {ok, #state{}}.

handle_call({download, TorrentInfoHash}, _From, State) ->
  case dict:find(TorrentInfoHash, State#state.torrents) of
    {error, _} ->
      {reply, {error, "Torrent not found"}, State};
    {ok, {Torrent, TorrentPid}} ->
      case ep2psharing:download_status(TorrentPid) of
        {downloaded, FilePath} ->
          {reply, {ok, FilePath}, State};
        {downloading, _} ->
          {reply, {error, "Torrent is already being downloaded"}, State};
        {not_started, _} ->
          _TorrentPid = ep2psharing:start(Torrent),
          NewState = State#state{torrents = dict:store(TorrentInfoHash, {Torrent, _TorrentPid}, State#state.torrents)},
          {reply, ok, NewState}
      end
  end.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.