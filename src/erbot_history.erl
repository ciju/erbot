-module(erbot_history).
-behaviour(gen_event).

%% -export([save_msg/4, close_files/1]).
-export([init/1, handle_event/2, handle_call/2, code_change/3, terminate/2,
         handle_info/2]).

-record(state, {client, fds}).

init([Client, []]) ->
    {ok, #state{client=Client, fds=orddict:new()}}.

handle_event({private_msg, _Nick, _Message}, S) ->
    {ok, S};
handle_event({channel_msg, {Nick, Channel}, Message}, S) ->
    {ok, S#state{fds=save_msg(Channel, Nick, Message, S#state.fds)}};
handle_event(_, State) ->
    {ok, State}.

handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, S) ->
    close_files(S#state.fds),
    ok.


file_name_for(Date, Channel) ->
    FPrefix = string:join([integer_to_list(X) || X <- tuple_to_list(Date)], "-"),
    FPrefix ++ "-" ++ Channel ++ ".txt".

two_days_before(Date) ->
    calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Date) - 2).

close_2_days_old_file(Date, Channel, Fds) ->
    FName = file_name_for(two_days_before(Date), Channel),
    case orddict:find(FName, Fds) of
        {ok, FD} ->
            file:close(FD),
            orddict:erase(FName, Fds);
        error -> Fds
    end.

save_msg(Channel, Nick, Message, Fds) ->
    Date = erlang:date(),
    FName = file_name_for(Date, Channel),

    case orddict:find(FName, Fds) of
        {ok, FD} ->
            %% append to the fd
            io:format("existing file ~s", [FName]),
            io:fwrite(FD, "~s: ~s~n", [Nick, Message]),
            Fds;
        error ->
            %% close 2 days old files
            close_2_days_old_file(Date, Channel, Fds),
            %% create/open file for date,channel
            %% put the new file in dictionary
            io:format("opening file - ~s", [FName]),
            {ok, FD} = file:open(FName, [append]),
            io:fwrite(FD, "~s: ~s~n", [Nick, Message]),
            orddict:store(FName, FD, Fds)
    end.

close_files(Fds) ->
    Fn = fun(Key, Val) ->
                 io:format("closing file ~s~n", [Key]),
                 file:close(Val), 
                 Val 
         end,
    orddict:map(Fn, Fds).
