%% @author jstypka <jasieek@student.agh.edu.pl>
%% @version 1.0
%% @doc Modul odpowiedzialny za logike pojedynczej wyspy.

-module(island).
-export([run/3]).

%% ====================================================================
%% API functions
%% ====================================================================

%% @spec run(Pid) -> ok
%% @doc Funkcja uruchamiajaca supervisora dla wyspy. Argumentem jest pid
%% tzw. krola, czyli procesu spawnujacego wyspy i czekajacego na wynik (zwykle shell).
%% Funkcja spawnuje areny i agentow, czeka na wiadomosci oraz odsyla
%% koncowy wynik do krola. Na koniec nastepuje zamkniecie aren i sprzatanie.
run(King,N,Instance) ->
  Ring = spawn(ring,start,[self()]),
  Port = spawn(port,start,[self(),King]),
  Bar = spawn(bar,start,[self(),Ring,Port]),
  Arenas = [Ring,Bar,Port],
  King ! {arenas,self(),Arenas}, % wysylamy adresy aren do krola, zeby mogl odeslac je portom
  [spawn(agent,start,Arenas) || _ <- lists:seq(1,config:populationSize())],
  FDs = emas_util:prepareWriting(Instance ++ "\\" ++ integer_to_list(N)),
  receiver(0,-99999,FDs), % obliczanie wyniku
  Bar ! Ring ! Port ! {finish,self()},
  emas_util:closeFiles(FDs),
  allDead = cleaner(Arenas).

%% ====================================================================
%% Internal functions
%% ====================================================================

%% @spec receiver(int) -> float()
%% @doc Funkcja odbierajaca wiadomosci. Moga to byc meldunki o wyniku
%% od baru lub rozkaz zamkniecia wyspy od krola. Argumentem jest licznik
%% odliczajacy kroki do wypisywania, a zwracany jest koncowy wynik.
receiver(Counter,Best,FDs) ->
  receive
    {result,Result} ->
      Step = config:printStep(),
      if Counter == Step ->
        io:format("Fitness: ~p~n",[Result]),
        NewCounter = 0;
      Counter /= Step ->
        NewCounter = Counter + 1
      end,
      if Best > Result ->
        receiver(NewCounter,Best,FDs);
      Best =< Result ->
        emas_util:write(dict:fetch(fitness,FDs),Result),
        receiver(NewCounter,Result,FDs)
      end;
    close ->
      forcedShutdown
  after config:supervisorTimeout() ->
    io:format("Timeout na wyspie ~p~n",[self()]),
    timeout
  end.

%% @spec cleaner(List1) -> allDead | notAllDead
%% @doc Funkcja upewnia sie, ze wszystkie areny z listy przeslanej
%% w argumencie koncza poprawnie swoje dzialanie.
cleaner([]) ->
  allDead;
cleaner(Arenas) ->
  receive
    {finished,Pid} ->
      true = lists:member(Pid,Arenas), %debug
      cleaner(lists:delete(Pid,Arenas));
    {result,_} ->
      cleaner(Arenas)
  after config:supervisorTimeout() ->
    notAllDead
  end.