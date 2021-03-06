-module(xserver).

-export([main/0, client/2]).

-define(not_found,
        <<"HTTP/1.1 404 Not Found\r\nContent-Length: 35\r\n\r\n<html><body>Not "
          "found</body></html>">>).

create_response(Data, Headers) ->
    H = list_to_binary("HTTP/1.1 200 OK\r\nContent-Length: "
                       ++ integer_to_list(byte_size(Data))
                       ++ "\r\n"),
    % O = list_to_binary(lists:join("\r\n", Headers)),
    O = list_to_binary(lists:foldl(fun(E, S) -> S ++ E ++ "\r\n" end, "", Headers)),
    <<H/binary, O/binary, <<"\r\n">>/binary, Data/binary>>.

get_file_content(Fname) ->
    {ok, Data} = file:read_file(Fname),
    Data.

route(<<"/">>) ->
    {200, create_response(get_file_content("static/index.html"), [])};
route(<<"/cat.jpg">>) ->
    {200, create_response(get_file_content("static/cat.jpg"), ["Content-Type: image/jpeg;"])};
route(<<"/info.html">>) ->
    {200, create_response(<<"<html><body>Info page</body></html>">>, [])};
route(_) ->
    {404, ?not_found}.

client(Socket, DbPid) ->
    {ok, Msg} = gen_tcp:recv(Socket, 0),
    [_, Path, _] = re:split(Msg, "(?<=GET )(.*?)(?= HTTP)"),
    
    {ok, {Adr, _}} = inet:peername(Socket),
    AdrString = inet:ntoa(Adr),
    Then = calendar:local_time(),

    {Status, Html} = route(Path),

    gen_tcp:send(Socket, Html),
    gen_tcp:close(Socket),
    io:format("~p ~p ~p ~p ~p~n", [Then, AdrString, "GET", Path, Status]),
    ok = mysql:query(DbPid, "INSERT INTO ws.cons VALUE (?, ?, ?, ?, ?)", [Then, AdrString, "GET", Path, Status]).

server(ServerSocket, DbPid) ->
    {ok, Socket} = gen_tcp:accept(ServerSocket),
    spawn(xserver, client, [Socket, DbPid]),
    server(ServerSocket, DbPid).

main() ->
    {ok, Pid} = mysql:start_link([{host, "127.0.0.1"}, {user, "root"},
                                  {password, "135"}, {database, "ws"}]),
    ok = mysql:query(Pid, "CREATE TABLE IF NOT EXISTS ws.cons (time DATETIME, ip VARCHAR(40), method VARCHAR(8), path TEXT, status INTEGER);"),
    {ok, ServerSocket} = gen_tcp:listen(8080, [binary, {active, false}, {reuseaddr, true}]),
    server(ServerSocket, Pid).
