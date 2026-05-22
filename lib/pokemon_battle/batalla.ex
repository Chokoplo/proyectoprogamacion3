defmodule PokemonBattle.Batalla do
  use GenServer, restart: :temporary

  alias PokemonBattle.{MotorCombate, Persistencia}

  @timeout_turno 20_000
  @timeout_reconexion 15_000

  defmodule Estado do
    defstruct [
      :id_sala,
      :nodo,
      jugadores: %{},       # %{pid => %{usuario, equipo, activo_idx, pids_cliente}}
      turno: 1,
      acciones: %{},        # %{pid => accion}
      estado: :esperando,   # :esperando | :en_curso | :terminada
      timer_ref: nil
    ]
  end

  # ---------- API pública ----------

  def start_link(id_sala),
    do: GenServer.start_link(__MODULE__, id_sala, name: via(id_sala))

  def unirse(id_sala, pid_cliente, usuario, equipo),
    do: GenServer.call(via(id_sala), {:unirse, pid_cliente, usuario, equipo})

  def iniciar(id_sala),
    do: GenServer.call(via(id_sala), :iniciar)

  def enviar_accion(id_sala, pid_cliente, accion),
    do: GenServer.call(via(id_sala), {:accion, pid_cliente, accion})

  def estado(id_sala),
    do: GenServer.call(via(id_sala), :estado)

  defp via(id), do: {:via, Registry, {PokemonBattle.RegistrySalas, id}}

  # ---------- Callbacks ----------

  @impl true
  def init(id_sala) do
    {:ok, %Estado{id_sala: id_sala, nodo: node()}}
  end

  @impl true
  def handle_call({:unirse, pid, usuario, equipo}, _from, state) do
    cond do
      map_size(state.jugadores) >= 2 ->
        {:reply, {:error, "La sala ya tiene 2 jugadores"}, state}

      state.estado != :esperando ->
        {:reply, {:error, "La batalla ya está en curso"}, state}

      true ->
        equipo_con_salud = inicializar_equipo(equipo)
        jugador = %{
          usuario: usuario,
          equipo: equipo_con_salud,
          activo_idx: 0,
          pid_cliente: pid
        }
        jugadores = Map.put(state.jugadores, pid, jugador)
        Process.monitor(pid)
        {:reply, {:ok, map_size(jugadores)}, %{state | jugadores: jugadores}}
    end
  end

  @impl true
  def handle_call(:iniciar, _from, state) do
    if map_size(state.jugadores) == 2 do
      state = %{state | estado: :en_curso}
      state = iniciar_turno(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, "Faltan jugadores"}, state}
    end
  end

  @impl true
  def handle_call({:accion, pid, accion}, _from, state) do
    if state.estado != :en_curso do
      {:reply, {:error, "La batalla no está en curso"}, state}
    else
      jugador = Map.get(state.jugadores, pid)
      if is_nil(jugador) do
        {:reply, {:error, "No estás en esta sala"}, state}
      else
        # Validar acción
        case validar_accion(accion, jugador) do
          {:ok, accion_valida} ->
            acciones = Map.put(state.acciones, pid, accion_valida)
            state = %{state | acciones: acciones}
            if map_size(acciones) == 2 do
              state = resolver_turno(state)
              {:reply, :ok, state}
            else
              {:reply, :ok, state}
            end

          {:error, msg} ->
            {:reply, {:error, msg}, state}
        end
      end
    end
  end

  @impl true
  def handle_call(:estado, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:timeout_turno, state) do
    # Jugadores sin acción → pasar
    pids = Map.keys(state.jugadores)
    acciones =
      Enum.reduce(pids, state.acciones, fn pid, acc ->
        if Map.has_key?(acc, pid), do: acc, else: Map.put(acc, pid, :pasar)
      end)
    state = resolver_turno(%{state | acciones: acciones})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    if Map.has_key?(state.jugadores, pid) do
      jugador = state.jugadores[pid]
      IO.puts("[Sala #{state.id_sala}] #{jugador.usuario} se desconectó. Esperando #{@timeout_reconexion / 1000}s...")
      Process.send_after(self(), {:verificar_reconexion, pid}, @timeout_reconexion)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:verificar_reconexion, pid}, state) do
    if Map.has_key?(state.jugadores, pid) do
      jugador = state.jugadores[pid]
      IO.puts("[Sala #{state.id_sala}] #{jugador.usuario} perdió por abandono.")
      oponente_pid = Map.keys(state.jugadores) |> Enum.find(&(&1 != pid))
      if oponente_pid do
        oponente = state.jugadores[oponente_pid]
        terminar_batalla(state, oponente.usuario, jugador.usuario)
      end
    end
    {:noreply, state}
  end

  # ---------- Lógica interna ----------

  defp inicializar_equipo(equipo) do
    Enum.map(equipo, fn pk ->
      Map.put_new(pk, :salud, 100)
      |> Map.put(:salud, 100)
    end)
  end

  defp iniciar_turno(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    tiempo = @timeout_turno
    ref = Process.send_after(self(), :timeout_turno, tiempo)

    # Mostrar estado a cada jugador
    [pid1, pid2] = Map.keys(state.jugadores)
    j1 = state.jugadores[pid1]
    j2 = state.jugadores[pid2]

    mostrar_estado_turno(pid1, j1, j2, state.turno)
    mostrar_estado_turno(pid2, j2, j1, state.turno)

    %{state | acciones: %{}, timer_ref: ref}
  end

defp mostrar_estado_turno(pid_cliente, jugador, rival, turno) do
  activo = Enum.at(jugador.equipo, jugador.activo_idx)
  activo_rival = Enum.at(rival.equipo, rival.activo_idx)

  equipo_str = jugador.equipo
    |> Enum.with_index()
    |> Enum.map(fn {pk, i} ->
      status = cond do
        i == jugador.activo_idx -> "activo"
        pk.salud <= 0 -> "debilitado"
        true -> "vivo"
      end
      "[##{pk.id}] #{pk.especie} (#{status})"
    end)
    |> Enum.join(" | ")

  equipo_rival_str = rival.equipo
    |> Enum.with_index()
    |> Enum.map(fn {pk, i} ->
      status = cond do
        i == rival.activo_idx -> "activo"
        pk.salud <= 0 -> "debilitado"
        true -> "vivo"
      end
      "#{pk.especie} (#{status})"
    end)
    |> Enum.join(" | ")

  movimientos_str = activo.movimientos
    |> Enum.with_index(1)
    |> Enum.map(fn {m, idx} ->
      "  #{idx}. #{m.nombre} (#{m.tipo}, poder #{m.poder})"
    end)
    |> Enum.join("\n")

  msg = "\n=== Turno #{turno} ===\n" <>
    "Rival: #{activo_rival.especie} (#{Enum.join(activo_rival.tipos, "/")}) | Salud: #{activo_rival.salud}/100\n" <>
    "Equipo rival: #{equipo_rival_str}\n" <>
    "Tu Pokemon: [##{activo.id}] #{activo.especie} (#{Enum.join(activo.tipos, "/")}) | Dueno original: #{activo.dueno_original} | Salud: #{activo.salud}/100 | Vel: #{activo.velocidad}\n" <>
    "Tu equipo: #{equipo_str}\n" <>
    "Movimientos:\n#{movimientos_str}\n" <>
    "Acciones: ataque <nombre> | cambiar <id> | rendirse\n" <>
    "Accion > "

  send(pid_cliente, {:mostrar, msg})
end

  defp validar_accion({:ataque, nombre_mov}, jugador) do
    activo = Enum.at(jugador.equipo, jugador.activo_idx)
    mov = Enum.find(activo.movimientos, &(&1.nombre == nombre_mov))
    if mov do
      {:ok, {:ataque, nombre_mov}}
    else
      {:error, "El movimiento '#{nombre_mov}' no pertenece a #{activo.especie}. Elige uno de sus movimientos."}
    end
  end

  defp validar_accion({:cambiar, id_str}, jugador) do
    with {id, ""} <- Integer.parse(id_str),
         idx when not is_nil(idx) <- Enum.find_index(jugador.equipo, &(&1.id == id)),
         pk when pk.salud > 0 <- Enum.at(jugador.equipo, idx),
         true <- idx != jugador.activo_idx do
      {:ok, {:cambiar, idx}}
    else
      _ -> {:error, "No puedes cambiar a ese Pokémon (no existe, está debilitado o ya es el activo)."}
    end
  end

  defp validar_accion(:rendirse, _), do: {:ok, :rendirse}
  defp validar_accion(:pasar, _), do: {:ok, :pasar}
  defp validar_accion(_, _), do: {:error, "Acción no reconocida."}

  defp resolver_turno(state) do
    [pid1, pid2] = Map.keys(state.jugadores)
    j1 = state.jugadores[pid1]
    j2 = state.jugadores[pid2]
    a1 = state.acciones[pid1]
    a2 = state.acciones[pid2]

    # Rendición inmediata
    cond do
      a1 == :rendirse ->
        terminar_batalla(state, j2.usuario, j1.usuario)
        state

      a2 == :rendirse ->
        terminar_batalla(state, j1.usuario, j2.usuario)
        state

      true ->
        pk1 = Enum.at(j1.equipo, j1.activo_idx)
        pk2 = Enum.at(j2.equipo, j2.activo_idx)

        {orden_pid1, _} = MotorCombate.orden_ataque(pk1, pk2)

        {primer_pid, primer_accion, segundo_pid, segunda_accion} =
          if orden_pid1 == :primero,
            do: {pid1, a1, pid2, a2},
            else: {pid2, a2, pid1, a1}

        state = ejecutar_accion(state, primer_pid, primer_accion)

        # Verificar si segundo Pokémon sigue vivo
        j_segundo = state.jugadores[segundo_pid]
        pk_segundo = Enum.at(j_segundo.equipo, j_segundo.activo_idx)

        state =
          if pk_segundo.salud > 0 do
            ejecutar_accion(state, segundo_pid, segunda_accion)
          else
            state
          end

        # Verificar fin de batalla
        state = verificar_fin(state)

        if state.estado == :en_curso do
          state = %{state | turno: state.turno + 1}
          iniciar_turno(state)
        else
          state
        end
    end
  end

  defp ejecutar_accion(state, pid, {:ataque, nombre_mov}) do
    jugador = state.jugadores[pid]
    oponente_pid = Map.keys(state.jugadores) |> Enum.find(&(&1 != pid))
    oponente = state.jugadores[oponente_pid]

    atacante = Enum.at(jugador.equipo, jugador.activo_idx)
    defensor = Enum.at(oponente.equipo, oponente.activo_idx)

    movimiento = Enum.find(atacante.movimientos, &(&1.nombre == nombre_mov))
    mov_map = %{"poder_base" => movimiento.poder, "tipo" => movimiento.tipo}
    atacante_map = %{"ataque" => atacante.ataque, "tipos" => atacante.tipos}
    defensor_map = %{"defensa" => defensor.defensa, "tipos" => defensor.tipos}

    dano = MotorCombate.calcular_dano(mov_map, atacante_map, defensor_map)
    ef_msg = MotorCombate.mensaje_efectividad(movimiento.tipo, defensor.tipos)

    nueva_salud = max(defensor.salud - dano, 0)

    msg = "[Turno #{state.turno}] #{jugador.usuario}: #{atacante.especie} usa #{nombre_mov} → #{dano} daño a #{defensor.especie} (Salud: #{nueva_salud}/100). #{ef_msg}"
    broadcast(state, msg)

    equipo_oponente =
      List.update_at(oponente.equipo, oponente.activo_idx, &Map.put(&1, :salud, nueva_salud))

    oponente_actualizado = %{oponente | equipo: equipo_oponente}

    # Verificar si debilitado
    oponente_actualizado =
      if nueva_salud <= 0 do
        broadcast(state, "¡#{defensor.especie} se ha debilitado!")
        oponente_actualizado
      else
        oponente_actualizado
      end

    jugadores = Map.put(state.jugadores, oponente_pid, oponente_actualizado)
    %{state | jugadores: jugadores}
  end

  defp ejecutar_accion(state, pid, {:cambiar, nuevo_idx}) do
    jugador = state.jugadores[pid]
    nuevo_pk = Enum.at(jugador.equipo, nuevo_idx)
    broadcast(state, "[Turno #{state.turno}] #{jugador.usuario} cambia a #{nuevo_pk.especie}!")
    jugadores = Map.put(state.jugadores, pid, %{jugador | activo_idx: nuevo_idx})
    %{state | jugadores: jugadores}
  end

  defp ejecutar_accion(state, _pid, :pasar), do: state
  defp ejecutar_accion(state, _pid, _), do: state

  defp verificar_fin(state) do
    Enum.reduce(state.jugadores, state, fn {pid, jugador}, acc ->
      if acc.estado == :terminada, do: acc,
      else: do_verificar_jugador(acc, pid, jugador)
    end)
  end

  defp do_verificar_jugador(state, pid, jugador) do
    todos_debilitados = Enum.all?(jugador.equipo, &(&1.salud <= 0))
    if todos_debilitados do
      oponente_pid = Map.keys(state.jugadores) |> Enum.find(&(&1 != pid))
      oponente = state.jugadores[oponente_pid]
      terminar_batalla(state, oponente.usuario, jugador.usuario)
      %{state | estado: :terminada}
    else
      # Verificar si activo debilitado → auto cambio
      activo = Enum.at(jugador.equipo, jugador.activo_idx)
      if activo.salud <= 0 do
        siguiente_idx = Enum.find_index(jugador.equipo, &(&1.salud > 0))
        if siguiente_idx do
          nuevo_pk = Enum.at(jugador.equipo, siguiente_idx)
          send(jugador.pid_cliente, {:mostrar, "Tu Pokémon se debilitó. Cambiando automáticamente a #{nuevo_pk.especie}..."})
          jugadores = Map.put(state.jugadores, pid, %{jugador | activo_idx: siguiente_idx})
          %{state | jugadores: jugadores}
        else
          state
        end
      else
        state
      end
    end
  end

  defp terminar_batalla(state, ganador, perdedor) do
    turno_final = state.turno
    nodo = state.nodo
    jugadores_str = state.jugadores |> Map.values() |> Enum.map(& &1.usuario) |> Enum.join(" vs ")

    broadcast(state, """

    ═══════════════════════════════════
    ¡BATALLA TERMINADA!
    Ganador: #{ganador} 🏆
    Perdedor: #{perdedor}
    Turnos: #{turno_final} | Nodo: #{nodo}
    #{ganador} recibe +100 monedas | #{perdedor} recibe +30 monedas
    ═══════════════════════════════════
    """)

    Persistencia.registrar_batalla(%{
      fecha: DateTime.utc_now() |> DateTime.to_string(),
      sala: state.id_sala,
      jugadores: jugadores_str,
      ganador: ganador,
      perdedor: perdedor,
      turnos: turno_final,
      nodo: to_string(nodo)
    })

    # Notificar al gestor de entrenadores para actualizar monedas y victorias
    PokemonBattle.GestorSalas.batalla_terminada(state.id_sala, ganador, perdedor)
  end

  defp broadcast(state, msg) do
    Enum.each(state.jugadores, fn {_pid, j} ->
      send(j.pid_cliente, {:mostrar, msg})
    end)
  end
end
