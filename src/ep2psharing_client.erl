-module(ep2psharing_client).

-behaviour(gen_server).

-export([start_link/0, download/1, start_console/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

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
      case ep2psharing_torrent:download_status(TorrentPid) of
        {downloaded, FilePath} ->
          {reply, {ok, FilePath}, State};
        {downloading, _} ->
          {reply, {error, "Torrent is already being downloaded"}, State};
        {not_started, _} ->
          _TorrentPid = ep2psharing_torrent:start(Torrent),
          NewState = State#state{torrents = dict:store(TorrentInfoHash, {Torrent, _TorrentPid}, State#state.torrents)},
          {reply, ok, NewState}
      end
  end.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

start_console() ->
  io:format("Ep2psharing Client console~n"),
  io:format("Commands:~n"),
  io:format("    download TorrentInfoHash - Download a torrent~n"),
  io:format("    exit - Exit console~n"),
  loop().

loop() ->
  case io:get_line("> ") of
    {error, _} ->
      exit(normal);
    Input ->
      case string:tokens(Input, " \t\n\r") of
        ["download", TorrentInfoHash] ->
          case download(TorrentInfoHash) of
            {ok, FilePath} ->
              io:format("Torrent downloaded to: ~s~n", [FilePath]);
            {error, Error} ->
              io:format("Error: ~s~n", [Error])
          end;
        ["exit"] ->
          exit(normal);
        _ ->
          io:format("Invalid command~n")
      end,
      loop()
  end.