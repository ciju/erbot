-module(erbot_irc).
-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 code_change/3, terminate/2]).

-export([start/0, stop/1, start_link/0]).

-compile(export_all).

-record(state, {socket, nick, publisher}).

start() ->
    gen_server:start(?MODULE, [], []).
start_link() ->
    gen_server:start_link(?MODULE, [], []).

stop(Pid) ->
    gen_server:call(Pid, quit).

init([]) ->
    BotName = "erbot",
    {ok, Socket} = gen_tcp:connect("irc.foonetic.net", 6667, [{packet, line}]),
    register(erbot, self()),
    register(BotName),
    {ok, Publisher} = gen_event:start_link(),
    gen_event:add_handler(Publisher, erbot_echo, self()),
    {ok, #state{socket=Socket, nick=BotName, publisher=Publisher}}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call(quit, _From, S = #state{socket=Socket}) ->
    ok = gen_tcp:close(Socket),
    io:format("Going down"),
    {stop, normal, ok, S}.

handle_cast({send, Reply}, S = #state{socket=Socket}) ->
    gen_tcp:send(Socket, Reply),
    io:format(">>>> ~p~n", [Reply]),
    {noreply, S};
handle_cast(try_new_nick, S = #state{nick=Nick}) ->
    NewNick = Nick ++ "_",
    register(NewNick),
    {noreply, S#state{nick=NewNick}}.


handle_info({tcp, _Socket, Message}, State) ->
    io:format("<<<< ~p~n", [Message]),
    message(erbot_protocol:parse(strip_crlf(Message)), State),
    {noreply, State};
handle_info(Unknown, State) ->
    io:format("got unknown message ~p~n", [Unknown]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

strip_crlf(Str) ->
    string:substr(Str, 1, length(Str) - 2).

%% irc stuffs
reply(Message) ->
    reply(self(), Message).
reply(Pid, Message) ->
    Reply = Message ++ "\r\n",
    gen_server:cast(Pid, {send, Reply}).

register(Name) ->
    reply("NICK " ++ Name),
    reply("USER " ++ Name ++ " 0 * :" ++ Name).

join(Pid, Channel) ->
    reply(Pid, "JOIN " ++ Channel).

send_message(Pid, Target, Message) ->
    reply(Pid, string:join(["PRIVMSG", Target, Message], " ")).

to_us(Target, #state{nick=Nick}) ->
    Target =:= Nick.

message({"PING", ServerName}, _S) ->
    reply("PONG " ++ ServerName);
message({From, "PRIVMSG", Rest}, S = #state{publisher=Publisher}) ->
    {Target, Message} = erbot_protocol:split_space(Rest),
    case to_us(Target, S) of
	true ->
	    {Nick, _Name, _Host} = erbot_protocol:user(From),
	    gen_event:notify(Publisher, {private_msg, Nick, Message});
	false -> ok
    end;
message({_Prefix, "433", _NicknameInUse}, _S) ->
    gen_server:cast(self(), try_new_nick);
message({Prefix, Command, Params}, _S) ->
    io:format("prefix ~p~n command ~p~n params ~p~n", [Prefix, Command, Params]),
    ok.
