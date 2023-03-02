-module(test_ep2psharing).

-include_lib("eunit/include/eunit.hrl").

start_peer_and_send_download_request() ->
  % Создаем новые ноды
  net_kernel:start([tracker, shortnames]),
  net_kernel:start([node, shortnames]),
  net_kernel:start([node1, shortnames]),

  % Считываем информацию о торрент-файле
  TorrentFile = ep2psharing_read_torrent_file:read_torrent_file("./example/big.txt.torrent"),
  % Формируем запрос на скачивание файла
  DownloadRequest = {download_request, TorrentFile,  "./example/big.txt"},
  DownloadRequestDownload = {download_request, TorrentFile,  "./example/bigtest.txt"},
  Pid = self(),
  spawn(tracker, fun() ->
    ep2psharing_tracker_sup:start_link()
                 end),

  spawn(node, fun() ->
    ep2psharing_peer_sup:start_link(),
    peer ! {torrent, Pid, DownloadRequest}
                      end),
  spawn(node1, fun() ->
    ep2psharing_peer_sup:start_link(),
    peer ! {torrent, Pid, DownloadRequestDownload}
                      end).

% Тест
simple_test() ->
  start_peer_and_send_download_request().
