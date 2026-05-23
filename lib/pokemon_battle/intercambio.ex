defmodule PokemonBattle.Intercambio do
  use GenServer, restart: :temporary

  def start_link(codigo),
    do: GenServer.start_link(__MODULE__, codigo, name: via(codigo))

  defp via(codigo), do: {:via, Registry, {PokemonBattle.RegistrySalas, "IC-#{codigo}"}}

  defmodule Estado do
    defstruct [
      :codigo,
      participantes: [],   # [%{pid, usuario, inventario, oferta_id}]
      estado: :esperando
    ]
  end

  # ---------- API pública ----------

  def unirse(codigo, pid, usuario, inventario),
    do: GenServer.call(via_codigo(codigo), {:unirse, pid, usuario, inventario})

  def ofrecer(codigo, pid, id_pokemon),
    do: GenServer.call(via_codigo(codigo), {:ofrecer, pid, id_pokemon})

  def confirmar(codigo, pid),
    do: GenServer.call(via_codigo(codigo), {:confirmar, pid})

  def cancelar(codigo, pid),
    do: GenServer.call(via_codigo(codigo), {:cancelar, pid})

  def estado(codigo),
    do: GenServer.call(via_codigo(codigo), :estado)

  defp via_codigo(codigo), do: {:via, Registry, {PokemonBattle.RegistrySalas, "IC-#{codigo}"}}

  # ---------- Callbacks ----------

  @impl true
  def init(codigo), do: {:ok, %Estado{codigo: codigo}}

  @impl true
  def handle_call({:unirse, pid, usuario, inventario}, _from, state) do
    cond do
      length(state.participantes) >= 2 ->
        {:reply, {:error, "La sala ya tiene 2 participantes"}, state}

      Enum.any?(state.participantes, &(&1.usuario == usuario)) ->
        {:reply, {:error, "No puedes unirte a tu propia sala"}, state}

      true ->
        p = %{pid: pid, usuario: usuario, inventario: inventario, oferta_id: nil, confirmado: false}
        participantes = state.participantes ++ [p]
        Process.monitor(pid)
        broadcast(%{state | participantes: participantes},
          "[Sala IC-#{state.codigo}] #{usuario} se ha unido. Ya pueden intercambiar.")
        {:reply, :ok, %{state | participantes: participantes}}
    end
  end

  @impl true
  def handle_call({:ofrecer, pid, id_pokemon}, _from, state) do
    case Enum.find_index(state.participantes, &(&1.pid == pid)) do
      nil ->
        {:reply, {:error, "No estás en esta sala"}, state}

      idx ->
        p = Enum.at(state.participantes, idx)
        with {id, ""} <- Integer.parse(id_pokemon),
             pk when not is_nil(pk) <- Enum.find(p.inventario, &(&1.id == id)) do

          participantes = List.update_at(state.participantes, idx, &%{&1 | oferta_id: id, confirmado: false})
          state = %{state | participantes: participantes}
          broadcast(state, "[Sala IC-#{state.codigo}] #{p.usuario} ofrece [##{id}] #{pk.especie} (#{Enum.join(pk.tipos, "/")}, #{pk.rareza}, Dueño original: #{pk.dueno_original})")
          mostrar_estado_sala(state)
          {:reply, :ok, state}
        else
          _ -> {:reply, {:error, "No tienes ese Pokémon en tu inventario."}, state}
        end
    end
  end

  @impl true
  def handle_call({:confirmar, pid}, _from, state) do
    case Enum.find_index(state.participantes, &(&1.pid == pid)) do
      nil ->
        {:reply, {:error, "No estás en esta sala"}, state}

      idx ->
        p = Enum.at(state.participantes, idx)
        if is_nil(p.oferta_id) do
          {:reply, {:error, "Primero debes ofrecer un Pokémon con 'ofrecer_pokemon <id>'"}, state}
        else
          participantes = List.update_at(state.participantes, idx, &%{&1 | confirmado: true})
          state = %{state | participantes: participantes}

          if Enum.all?(state.participantes, & &1.confirmado) and length(state.participantes) == 2 do
            realizar_intercambio(state)
            {:reply, :ok, %{state | estado: :terminado}}
          else
            broadcast(state, "[Sala IC-#{state.codigo}] #{p.usuario} ha confirmado. Esperando al otro participante...")
            {:reply, :ok, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:cancelar, pid}, _from, state) do
    usuario = case Enum.find(state.participantes, &(&1.pid == pid)) do
      nil -> "Alguien"
      p -> p.usuario
    end
    broadcast(state, "[Sala IC-#{state.codigo}] #{usuario} canceló el intercambio. La sala se ha cerrado.")
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:estado, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    usuario = case Enum.find(state.participantes, &(&1.pid == pid)) do
      nil -> "Alguien"
      p -> p.usuario
    end
    broadcast(state, "[Sala IC-#{state.codigo}] #{usuario} se desconectó. Intercambio cancelado.")
    {:stop, :normal, state}
  end

  defp realizar_intercambio(state) do
    [p1, p2] = state.participantes
    pk1 = Enum.find(p1.inventario, &(&1.id == p1.oferta_id))
    pk2 = Enum.find(p2.inventario, &(&1.id == p2.oferta_id))

    # Notificar al gestor de entrenadores para actualizar inventarios
    GenServer.cast(PokemonBattle.GestorEntrenadores,
      {:intercambio, p1.usuario, p1.oferta_id, p2.usuario, p2.oferta_id})

    send(p1.pid, {:mostrar, "[Intercambio completado] Recibiste [##{pk2.id}] #{pk2.especie}. #{p2.usuario} recibió [##{pk1.id}] #{pk1.especie}."})
    send(p2.pid, {:mostrar, "[Intercambio completado] Recibiste [##{pk1.id}] #{pk1.especie}. #{p1.usuario} recibió [##{pk2.id}] #{pk2.especie}."})
  end

  defp mostrar_estado_sala(state) do
    lineas = Enum.map(state.participantes, fn p ->
      oferta = if p.oferta_id, do: "[##{p.oferta_id}] ✓", else: "(sin oferta)"
      "  #{p.usuario} → #{oferta}"
    end) |> Enum.join("\n")

    ambos = Enum.all?(state.participantes, & &1.oferta_id)
    footer = if ambos, do: "\n  Ambos han ofrecido. Confirma con: confirmar_intercambio", else: ""

    msg = "[Sala IC-#{state.codigo}]\n#{lineas}#{footer}"
    broadcast(state, msg)
  end

  defp broadcast(state, msg) do
    Enum.each(state.participantes, fn p -> send(p.pid, {:mostrar, msg}) end)
  end
end
