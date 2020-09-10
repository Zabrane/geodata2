-module(geodata2).

-behavior(gen_server).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2]).
%% API
-export([lookup/1, start/0, start_link/1, stop/0, get_env/2, id/1, is_ipv6_mmdb/0]).

-include("geodata2.hrl").

-record(state, {}).

-type state() :: #state{}.

-spec lookup(any()) -> {ok, Result :: list()} | not_found | {error, Reason :: term()}.
lookup(IP) ->
    [{data, Data}] = ets:lookup(?GEODATA2_STATE_TID, data),
    [{meta, Meta}] = ets:lookup(?GEODATA2_STATE_TID, meta),
    case geodata2_ip:make_ip(IP) of
        {ok, Bits, IPV} ->
            geodata2_format:lookup(Meta, Data, Bits, IPV);
        {error, Reason} ->
            {error, Reason}
    end.

start() ->
    application:start(geodata2).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

stop() ->
    application:stop(geodata2).

new(File) ->
    case filelib:is_file(File) of
        true ->
            {ok, RawData} = file:read_file(File),
            Data =
                case is_compressed(File) of
                    true ->
                        zlib:gunzip(RawData);
                    false ->
                        RawData
                end,
            {ok, Meta} = geodata2_format:meta(Data),
            %% @TODO [RTI-8302] This one could be removed after the IPv4+IPv6 MMDB is definitely used
            set_is_ipv6_mmdb(Meta),
            ets:new(?GEODATA2_STATE_TID, [set, protected, named_table, {read_concurrency, true}]),
            ets:insert(?GEODATA2_STATE_TID, {data, Data}),
            ets:insert(?GEODATA2_STATE_TID, {meta, Meta}),
            {ok, #state{}};
        _ ->
            {stop, {geodata2_dbfile_not_found, File}}
    end.

-spec init(_) -> {ok, state()} | {stop, tuple()}.
init(_Args) ->
    case get_env(geodata2, dbfile) of
        {ok, File} ->
            new(File);
        _ ->
            {stop, {geodata2_dbfile_unspecified}}
    end.

handle_call(_What, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_env(App, Key) ->
    {ConfigModule, ConfigFun} =
        case application:get_env(geodata2, config_interp) of
            {ok, {Cm, Cf}} ->
                {Cm, Cf};
            _ ->
                {?MODULE, id}
        end,
    case application:get_env(App, Key) of
        {ok, Value} ->
            {ok, ConfigModule:ConfigFun(Value)};
        Other ->
            Other
    end.

%% this is used to return app env values as-is when config_interp is not set:
id(X) ->
    X.

%% @TODO [RTI-8302] This one could be removed after the IPv4+IPv6 MMDB is definitely used
is_ipv6_mmdb() ->
    application:get_env(geodata2, ipv6, false).

%% @TODO [RTI-8302] This one could be removed after the IPv4+IPv6 MMDB is definitely used
set_is_ipv6_mmdb(Meta) ->
    application:set_env(geodata2, ipv6, geodata2_format:is_ipv6(Meta)).

is_compressed(Filename) ->
    <<".gz">> == iolist_to_binary(filename:extension(Filename)).
