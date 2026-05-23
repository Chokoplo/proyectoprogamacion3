defmodule PokemonBattle.GestorSalas do
  use GenServer

  alias PokemonBattle.{SupervisorBatallas, GestorEntrenadores}

  defmodule Sala do
    defstruct [:id, :tiempo_turno, jugadores: [], estado: :esperando, equipo_cargado: %{}]
  end

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, %{salas: %{}, contador: 1000}}

  # ---------- API pública ----------

  def crear_sala(tiempo_turno \\ 20),
    do: GenServer.call(__MODULE__, {:crear_sala, tiempo_turno})

  def listar_salas,
    do: GenServer.call(__MODULE__, :listar_salas)

  def unirse_sala(id_sala, pid_cliente, usuario),
    do: GenServer.call(__MODULE__, {:unirse_sala, id_sala, pid_cliente, usuario})

  def usar_equipo(id_sala, pid_cliente, equipo),
    do: GenServer.call(__MODULE__, {:usar_equipo, id_sala, pid_cliente, equipo})

  def iniciar_batalla(id_sala),
    do: GenServer.call(__MODULE__, {:iniciar_batalla, id_sala})

  def batalla_terminada(id_sala, ganador, perdedor),
    do: GenServer.cast(__MODULE__, {:batalla_terminada, id_sala, ganador, perdedor})

  def get_sala(id_sala),
    do: GenServer.call(__MODULE__, {:get_sala, id_sala})

  # ---------- Callbacks ----------

  @impl true
  def handle_call({:crear_sala, tiempo_turno}, _from, state) do
    id = "S-#{state.contador}"
    sala = %Sala{id: id, tiempo_turno: tiempo_turno}
    salas = Map.put(state.salas, id, sala)
    {:reply, {:ok, id}, %{state | salas: salas, contador: state.contador + 1}}
  end

  @impl true
  def handle_call(:listar_salas, _from, state) do
    lista = Map.values(state.salas)
    {:reply, lista, state}
  end

  @impl true
  def handle_call({:unirse_sala, id_sala, pid, usuario}, _from, state) do
    case Map.get(state.salas, id_sala) do
      nil ->
        {:reply, {:error, "Sala '#{id_sala}' no existe"}, state}

      sala when length(sala.jugadores) >= 2 ->
        {:reply, {:error, "La sala ya tiene 2 jugadores"}, state}

      sala ->
        if Enum.any?(sala.jugadores, &(&1.usuario == usuario)) do
          {:reply, {:error, "Ya estás en esta sala"}, state}
        else
          jugador = %{pid: pid, usuario: usuario}
          sala = %{sala | jugadores: sala.jugadores ++ [jugador]}
          salas = Map.put(state.salas, id_sala, sala)
          {:reply, {:ok, length(sala.jugadores)}, %{state | salas: salas}}
        end
    end
  end

  @impl true
  def handle_call({:usar_equipo, id_sala, pid, equipo}, _from, state) do
    case Map.get(state.salas, id_sala) do
      nil ->
        {:reply, {:error, "Sala no existe"}, state}

      sala ->
        equipo_cargado = Map.put(sala.equipo_cargado, pid, equipo)
        sala = %{sala | equipo_cargado: equipo_cargado}
        salas = Map.put(state.salas, id_sala, sala)
        {:reply, :ok, %{state | salas: salas}}
    end
  end

  @impl true
  def handle_call({:iniciar_batalla, id_sala}, _from, state) do
    case Map.get(state.salas, id_sala) do
      nil ->
        {:reply, {:error, "Sala no existe"}, state}

      sala when length(sala.jugadores) < 2 ->
        {:reply, {:error, "Faltan jugadores"}, state}

      sala ->
        # Verificar que ambos tengan equipo cargado
        pids = Enum.map(sala.jugadores, & &1.pid)
        todos_con_equipo = Enum.all?(pids, &Map.has_key?(sala.equipo_cargado, &1))

        if not todos_con_equipo do
          {:reply, {:error, "Ambos jugadores deben cargar un equipo con 'usar_equipo'"}, state}
        else
          nodo_batalla = elegir_nodo()

          # Iniciar la batalla en el nodo elegido (distribuido si hay otros nodos)
          timeout_ms = sala.tiempo_turno * 1_000
          resultado =
            if nodo_batalla == node() do
              SupervisorBatallas.iniciar_batalla(id_sala, timeout_ms)
            else
              :rpc.call(nodo_batalla, PokemonBattle.SupervisorBatallas, :iniciar_batalla, [id_sala, timeout_ms])
            end

          case resultado do
            {:ok, _pid} ->
              Enum.each(sala.jugadores, fn j ->
                equipo = sala.equipo_cargado[j.pid]
                PokemonBattle.Batalla.unirse(id_sala, j.pid, j.usuario, equipo)
              end)

              PokemonBattle.Batalla.iniciar(id_sala)
              sala = %{sala | estado: :en_curso}
              salas = Map.put(state.salas, id_sala, sala)
              {:reply, {:ok, nodo_batalla}, %{state | salas: salas}}

            {:error, reason} ->
              {:reply, {:error, "No se pudo iniciar la batalla en nodo #{nodo_batalla}: #{inspect(reason)}"}, state}

            {:badrpc, reason} ->
              # Fallback: iniciar localmente si el nodo remoto falla
              {:ok, _pid} = SupervisorBatallas.iniciar_batalla(id_sala, timeout_ms)
              Enum.each(sala.jugadores, fn j ->
                equipo = sala.equipo_cargado[j.pid]
                PokemonBattle.Batalla.unirse(id_sala, j.pid, j.usuario, equipo)
              end)
              PokemonBattle.Batalla.iniciar(id_sala)
              sala = %{sala | estado: :en_curso}
              salas = Map.put(state.salas, id_sala, sala)
              IO.puts("[Aviso] No se pudo conectar al nodo #{nodo_batalla} (#{inspect(reason)}). Batalla iniciada localmente en #{node()}.")
              {:reply, {:ok, node()}, %{state | salas: salas}}
          end
        end
    end
  end

  @impl true
  def handle_call({:get_sala, id_sala}, _from, state) do
    {:reply, Map.get(state.salas, id_sala), state}
  end

  @impl true
  def handle_cast({:batalla_terminada, _id_sala, ganador, perdedor}, state) do
    # Actualizar estadísticas de entrenadores
    entrenadores = PokemonBattle.GestorEntrenadores.listar_clasificacion()

    Enum.each(entrenadores, fn e ->
      cond do
        e.usuario == ganador ->
          actualizado = %{e |
            victorias: e.victorias + 1,
            monedas: e.monedas + 100,
            monedas_acumuladas: e.monedas_acumuladas + 100
          }
          # Buscar pid del ganador y actualizar
          actualizar_entrenador_por_usuario(state, ganador, actualizado)

        e.usuario == perdedor ->
          actualizado = %{e |
            monedas: e.monedas + 30,
            monedas_acumuladas: e.monedas_acumuladas + 30
          }
          actualizar_entrenador_por_usuario(state, perdedor, actualizado)

        true -> :ok
      end
    end)

    {:noreply, state}
  end

  defp actualizar_entrenador_por_usuario(_state, _usuario, entrenador) do
    # Actualizar directamente via gestor
    GenServer.cast(GestorEntrenadores, {:actualizar_por_usuario, entrenador})
  end

  defp elegir_nodo do
    nodos = [node() | Node.list()]
    Enum.random(nodos)
  end
end
