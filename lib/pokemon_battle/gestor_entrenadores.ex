defmodule PokemonBattle.GestorEntrenadores do
  use GenServer

  alias PokemonBattle.{Persistencia, SistemaSobres}

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
def init(:ok) do
  entrenadores =
    case Persistencia.cargar_entrenadores() do
      [] -> []
      lista -> Enum.map(lista, &atomizar/1)
    end
  {:ok, %{entrenadores: entrenadores, sesiones: %{}}}
end

  # ---------- API pública ----------

  def iniciar_sesion(pid_cliente, usuario, clave),
    do: GenServer.call(__MODULE__, {:iniciar_sesion, pid_cliente, usuario, clave})

  def cerrar_sesion(pid_cliente),
    do: GenServer.call(__MODULE__, {:cerrar_sesion, pid_cliente})

  def get_entrenador(pid_cliente),
    do: GenServer.call(__MODULE__, {:get_entrenador, pid_cliente})

  def actualizar_entrenador(pid_cliente, entrenador),
    do: GenServer.call(__MODULE__, {:actualizar_entrenador, pid_cliente, entrenador})

  def listar_clasificacion,
    do: GenServer.call(__MODULE__, :clasificacion)

  # ---------- Callbacks ----------

  @impl true
  def handle_call({:iniciar_sesion, pid, usuario, clave}, _from, state) do
    existing = Enum.find(state.entrenadores, &(&1.usuario == usuario))

    {entrenador, state} =
      cond do
        existing && existing.clave == clave ->
          {existing, state}

        existing ->
          {nil, state}

        true ->
          nuevo = nuevo_entrenador(usuario, clave)
          entrenadores = state.entrenadores ++ [nuevo]
          Persistencia.guardar_entrenadores(entrenadores)
          {nuevo, %{state | entrenadores: entrenadores}}
      end

    if entrenador do
      sesiones = Map.put(state.sesiones, pid, entrenador.usuario)
      {:reply, {:ok, entrenador}, %{state | sesiones: sesiones}}
    else
      {:reply, {:error, "Clave incorrecta"}, state}
    end
  end

  @impl true
  def handle_call({:cerrar_sesion, pid}, _from, state) do
    sesiones = Map.delete(state.sesiones, pid)
    {:reply, :ok, %{state | sesiones: sesiones}}
  end

  @impl true
  def handle_call({:get_entrenador, pid}, _from, state) do
    case Map.get(state.sesiones, pid) do
      nil -> {:reply, {:error, "No estás en sesión"}, state}
      usuario ->
        e = Enum.find(state.entrenadores, &(&1.usuario == usuario))
        {:reply, {:ok, e}, state}
    end
  end

  @impl true
  def handle_call({:actualizar_entrenador, pid, entrenador}, _from, state) do
    entrenadores =
      Enum.map(state.entrenadores, fn e ->
        if e.usuario == entrenador.usuario, do: entrenador, else: e
      end)
    Persistencia.guardar_entrenadores(entrenadores)
    sesiones = Map.put(state.sesiones, pid, entrenador.usuario)
    {:reply, :ok, %{state | entrenadores: entrenadores, sesiones: sesiones}}
  end

  @impl true
  def handle_call(:clasificacion, _from, state) do
    clasificacion =
      state.entrenadores
      |> Enum.sort_by(&{-&1.victorias, -&1.monedas_acumuladas})
    {:reply, clasificacion, state}
  end

  @impl true
  def handle_cast({:actualizar_por_usuario, entrenador}, state) do
    entrenadores =
      Enum.map(state.entrenadores, fn e ->
        if e.usuario == entrenador.usuario, do: entrenador, else: e
      end)
    Persistencia.guardar_entrenadores(entrenadores)
    {:noreply, %{state | entrenadores: entrenadores}}
  end

  @impl true
  def handle_cast({:intercambio, usuario1, id_pk1, usuario2, id_pk2}, state) do
    # Mover pk1 de usuario1 a usuario2 y pk2 de usuario2 a usuario1
    entrenadores =
      Enum.map(state.entrenadores, fn e ->
        cond do
          e.usuario == usuario1 ->
            pk1 = Enum.find(e.inventario, &(&1.id == id_pk1))
            if pk1 do
              inventario = Enum.reject(e.inventario, &(&1.id == id_pk1))
              %{e | inventario: inventario, pk_pendiente_recibir: id_pk2}
            else
              e
            end
          e.usuario == usuario2 ->
            pk2 = Enum.find(e.inventario, &(&1.id == id_pk2))
            if pk2 do
              inventario = Enum.reject(e.inventario, &(&1.id == id_pk2))
              %{e | inventario: inventario, pk_pendiente_recibir: id_pk1}
            else
              e
            end
          true -> e
        end
      end)

    # Segunda pasada: agregar los Pokémon recibidos
    # Obtener los pks desde el estado original
    e1_original = Enum.find(state.entrenadores, &(&1.usuario == usuario1))
    e2_original = Enum.find(state.entrenadores, &(&1.usuario == usuario2))
    pk1 = Enum.find(e1_original.inventario, &(&1.id == id_pk1))
    pk2 = Enum.find(e2_original.inventario, &(&1.id == id_pk2))

    entrenadores =
      Enum.map(entrenadores, fn e ->
        cond do
          e.usuario == usuario1 ->
            %{e | inventario: e.inventario ++ [pk2]}
          e.usuario == usuario2 ->
            %{e | inventario: e.inventario ++ [pk1]}
          true -> e
        end
      end)

    Persistencia.guardar_entrenadores(entrenadores)
    {:noreply, %{state | entrenadores: entrenadores}}
  end

  # ---------- Privado ----------

  defp nuevo_entrenador(usuario, clave) do
    base = %{
      usuario: usuario,
      clave: clave,
      victorias: 0,
      monedas: 0,
      monedas_acumuladas: 0,
      inventario: [],
      sobres_pendientes: [],
      equipos: []
    }
    SistemaSobres.sobre_gratuito(base)
  end

  defp atomizar(map) when is_map(map) do
    map
    |> Map.new(fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, atomizar(v)}
    end)
  end
  defp atomizar(list) when is_list(list), do: Enum.map(list, &atomizar/1)
  defp atomizar(v), do: v
end
