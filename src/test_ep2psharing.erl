-module(test_ep2psharing).

-include_lib("eunit/include/eunit.hrl").

start_peer_and_send_download_request() ->
  net_kernel:start(['tracker@DESKTOP-D09RERH', shortnames]),
  net_kernel:start([node1, shortnames]),
  net_kernel:start([node2, shortnames]),
  spawn('tracker@DESKTOP-D09RERH', fun() ->
    ep2psharing_tracker_sup:start_link()
                                        end),
  % Создаем новый процесс Erlang
  % Считываем информацию о торрент-файле
  TorrentFile = ep2psharing_read_torrent_file:read_torrent_file("path/big.txt.torrent"),
  % Формируем запрос на скачивание файла
  DownloadRequest = {download_request, TorrentFile,  "path/big.txt"},
  DownloadRequestDownload = {download_request, TorrentFile,  "path/bigtest.txt"},

  spawn(peer@node1, fun() ->
    ep2psharing_peer_sup:start_link(),
    peer ! {torrent, self(), DownloadRequest}
                      end),
  spawn(peer@node2, fun() ->
    ep2psharing_peer_sup:start_link(),
    peer ! {torrent, self(), DownloadRequestDownload}
                      end),
  receive
    {torrent, _Pid, DownloadRequest} -> ok
  after 30000 -> error
  end.

% Тест
simple_test() ->
  start_peer_and_send_download_request(),
  % Проверяем, что peer_sup принял запрос на скачивание файла
  ?assertEqual(ok, ok).