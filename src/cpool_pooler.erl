%%% -------------------------------------------------------------------
%%% Author  : WANGFEI6
%%% Description :
%%%
%%% Created : 2011-1-28
%%% -------------------------------------------------------------------
-module(cpool_pooler).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("cpool.hrl").
%% --------------------------------------------------------------------
%% External exports
%-export([start/0, start_link/0, stop/0, get_socket/0, free_socket/1, status/0]).
-compile(export_all).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(states, {sockets, numbers}).

%% ====================================================================
%% External functions
%% ====================================================================
start(PoolName) ->       
    gen_server:start({local, PoolName}, ?MODULE, [], []).

start_link(PoolName) ->
    gen_server:start_link({local, PoolName}, ?MODULE, [], []).

stop(PoolName) ->
    gen_server:call(PoolName, stop).

get_socket(PoolName) ->
	?dbg2("Get Socket PoolName : ~p ~n",[PoolName]),
	gen_server:call(PoolName, get_socket).

free_socket(PoolName,Socket) ->
	?dbg2("Free Socket PoolName : ~p ~n",[PoolName]),
	gen_server:cast(PoolName, {free_socket, Socket}).

status(PoolName) -> 
	gen_server:call(PoolName, status).
%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([]) ->
	Numbers = ?MIN_POOL_NUMBERS,
	Sockets = connect([], Numbers),
	?dbg2("Creating pool ~p Ok ", [Numbers]),
	%?dbg2("create pool OK,numbers: ~p ,Sockets : ~p ",[Numbers,Sockets]),

    {ok, #states{sockets=Sockets, numbers=Numbers}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call(stop,_From, State) ->
	{stop, shutdown,stoped, State};

handle_call(get_socket, _From, State) ->
	Sockets = State#states.sockets,
	Numbers = State#states.numbers,

	if
		Numbers == 0 ->
			case cpool_connect:connect(cpool_connect:config()) of
				{ok, LastSocket} ->
					?dbg2("Dynamic Create Pool Socket Ok : ~p ", [LastSocket]),
					{reply, LastSocket, #states{sockets=[], numbers=0}};
				{error,LastReason} ->
					?dbg2("Dynamic Create Pool Socket Error : ~p ", [LastReason]),
                    {reply, {error, "Dynamic Create Pool Socket Error"}, #states{sockets=[],numbers=0}}
			end;
		Numbers == 1 ->
			[HSocket|_] = Sockets,
			case cpool_connect:connect(cpool_connect:config()) of
				{ok, SecondSocket} ->
					?dbg2("Dynamic Create Pool Socket Ok : ~p ", [SecondSocket]),
					{reply, HSocket, #states{sockets=[SecondSocket], numbers=1}};
				{error,SecondReason} ->
					?dbg2("Dynamic Create Pool Socket Error : ~p ", [SecondReason]),
                    {reply, HSocket, #states{sockets=[], numbers=0}}
			end;
		Numbers >= ?MAX_POOL_NUMBERS ->
			[HSocket1, HSocket2|TSocket] = Sockets,
			%%send a close signal to  memcache Server is necessary
			gen_tcp:close(HSocket2),
			?dbg2("close Socket: ~p",[HSocket2]),
			{reply, HSocket1, #states{sockets=TSocket, numbers=Numbers-2}};
		true -> 
			[HSocket | TSocket] = Sockets,
			{reply, HSocket, #states{sockets=TSocket, numbers=Numbers-1}}
	end;

handle_call(status, _From, State) ->
	Socket_list = State#states.sockets,
	Socket_nums = State#states.numbers,
	{ reply, {Socket_nums, Socket_list} , State};


handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

handle_cast({free_socket, Socket}, State) ->
	Sockets = State#states.sockets,
	Numbers = State#states.numbers,
	?dbg2("Free Socket:~p ", [Socket]),
	case Socket of 
		{error,_} ->
			{noreply, #states{ sockets=Sockets, numbers=Numbers } };
		_ ->
			{noreply, #states{ sockets=[Socket|Sockets], numbers=Numbers+1 }} 
	end;

handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

connect(Socket_lists, 0) ->
    Socket_lists;

connect(Socket_lists, Pool_numbers) ->
    case cpool_connect:connect(cpool_connect:config()) of
        {ok,Socket} ->
            connect([Socket|Socket_lists], Pool_numbers-1);
        {error, Reason} ->
            ?dbg2("Connect Error: ~p, Pool_number: ~p ", [Reason, Pool_numbers]),
            connect(Socket_lists, Pool_numbers)
    end.
