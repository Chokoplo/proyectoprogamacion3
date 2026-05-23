efmodule PokemonBattle.Servidor do
  alias PokemonBattle.{
    GestorEntrenadores, GestorSalas, SistemaSobres,
    SupervisorBatallas, Intercambio, Persistencia, Cluster
  }

  def iniciar do
    IO.puts("╔══════════════════════════════════════╗")
    IO.puts("║    ⚡ Batallas Pokemon en Elixir ⚡    ║")
    IO.puts("╚══════════════════════════════════════╝")
    IO.puts("Comandos: iniciar <usuario> <clave> | ayuda")
    loop(%{sesion: nil, sala_batalla: nil, sala_intercambio: nil})
  end

  defp loop(ctx) do
    ctx = flush_mensajes(ctx)
    prefijo = if ctx.sesion, do: "(#{ctx.sesion.usuario}) > ", else: "> "
    linea = IO.gets(prefijo) |> String.trim()
    if linea == "" do
      loop(ctx)
    else
      [cmd | args] = String.split(linea)
      ctx = procesar(cmd, args, ctx)
      loop(ctx)
    end
  end

  defp flush_mensajes(ctx) do
    receive do
      {:mostrar, msg} ->
        IO.puts(msg)
        flush_mensajes(ctx)
    after
      0 -> ctx
    end
  end

  defp procesar("ayuda", _, ctx) do
    IO.puts("=== Comandos disponibles ===")
    IO.puts("SESION:")
    IO.puts("  iniciar <usuario> <clave>   - Iniciar/registrar sesion")
    IO.puts("  salir                       - Cerrar sesion")
    IO.puts("  perfil                      - Ver monedas y sobres")
    IO.puts("  inventario                  - Ver todos tus Pokemon con IDs")
    IO.puts("  clasificacion               - Ranking global")
    IO.puts("TIENDA Y SOBRES:")
    IO.puts("  tienda                      - Ver tipos de sobre y precios")
    IO.puts("  comprar_sobre <tipo>        - basico (100) / avanzado (250)")
    IO.puts("  abrir_sobre <id|ultimo>     - Abrir sobre")
    IO.puts("EQUIPOS:")
    IO.puts("  crear_equipo <nombre> <id1[,id2,id3]>")
    IO.puts("  listar_equipos")
    IO.puts("  agregar_pokemon_equipo <equipo> <id>")
    IO.puts("  quitar_pokemon_equipo <equipo> <id>")
    IO.puts("  usar_equipo <nombre>        - Cargar equipo para batalla")
    IO.puts("BATALLAS:")
    IO.puts("  listar_salas")
    IO.puts("  crear_sala [tiempo_turno=20]")
    IO.puts("  unirse_sala <id_sala>")
    IO.puts("  iniciar_batalla <id_sala>")
    IO.puts("  ataque <movimiento>")
    IO.puts("  cambiar <id_pokemon>")
    IO.puts("  rendirse")
    IO.puts("INTERCAMBIO:")
    IO.puts("  crear_sala_intercambio")
    IO.puts("  unirse_sala_intercambio <codigo>")
    IO.puts("  ofrecer_pokemon <id>")
    IO.puts("  confirmar_intercambio")
    IO.puts("  cancelar_intercambio")
    IO.puts("CLUSTER:")
    IO.puts("  conectar_nodo <nodo@host>")
    IO.puts("  nodos")
    ctx
  end

  defp procesar("iniciar", [usuario, clave], ctx) do
    case GestorEntrenadores.iniciar_sesion(self(), usuario, clave) do
      {:ok, entrenador} ->
        IO.puts("Bienvenido, #{usuario}! Monedas: #{entrenador.monedas} | Sobres: #{length(entrenador.sobres_pendientes)}")
        %{ctx | sesion: entrenador}
      {:error, msg} ->
        IO.puts("Error: #{msg}")
        ctx
    end
  end

  defp procesar("iniciar", _, ctx) do
    IO.puts("Uso: iniciar <usuario> <clave>")
    ctx
  end

  defp procesar(cmd, args, ctx) do
    if is_nil(ctx.sesion) do
      IO.puts("Debes iniciar sesion primero. Usa: iniciar <usuario> <clave>")
      ctx
    else
      procesar_autenticado(cmd, args, ctx)
    end
  end

  defp procesar_autenticado("salir", _, ctx) do
    GestorEntrenadores.cerrar_sesion(self())
    IO.puts("Hasta luego, #{ctx.sesion.usuario}!")
    %{ctx | sesion: nil}
  end

  defp procesar_autenticado("perfil", _, ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    IO.puts("=== Perfil de #{e.usuario} ===")
    IO.puts("Monedas: #{e.monedas}")
    IO.puts("Sobres pendientes: #{length(e.sobres_pendientes)}")
    IO.puts("Pokemon en inventario: #{length(e.inventario)}")
    %{ctx | sesion: e}
  end

  defp procesar_autenticado("inventario", _, ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    IO.puts("=== Inventario de #{e.usuario} (#{length(e.inventario)} Pokemon) ===")
    Enum.each(Enum.with_index(e.inventario, 1), fn {pk, i} ->
      tipos = Enum.join(pk.tipos, "/")
      movs = Enum.map(pk.movimientos, &"#{&1.nombre}(#{&1.poder})") |> Enum.join(", ")
      IO.puts("  #{i}. [##{pk.id}] #{String.capitalize(pk.especie)} (#{tipos}) [#{pk.rareza}]")
      IO.puts("     Ataque: #{pk.ataque} | Defensa: #{pk.defensa} | Velocidad: #{pk.velocidad} | Salud max: 100")
      IO.puts("     Dueno original: #{pk.dueno_original}")
      IO.puts("     Movimientos: #{movs}")
    end)
    %{ctx | sesion: e}
  end

  defp procesar_autenticado("clasificacion", _, ctx) do
    lista = GestorEntrenadores.listar_clasificacion()
    IO.puts("=== Clasificacion Global ===")
    IO.puts("# | Entrenador | Victorias | Monedas acumuladas")
    Enum.each(Enum.with_index(lista, 1), fn {e, i} ->
      IO.puts("#{i} | #{e.usuario} | #{e.victorias} | #{e.monedas_acumuladas}")
    end)
    ctx
  end

  defp procesar_autenticado("tienda", _, ctx) do
    tienda = Persistencia.cargar_tienda()
    IO.puts("=== Tienda ===")
    Enum.each(tienda, fn t ->
      p = t["probabilidades"]
      IO.puts("  #{t["tipo"]}: #{t["precio"]} monedas | Comun #{p["comun"]}% | Raro #{p["raro"]}% | Epico #{p["epico"]}%")
    end)
    ctx
  end

  defp procesar_autenticado("comprar_sobre", [tipo], ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    case SistemaSobres.comprar_sobre(e, tipo) do
      {:ok, e_nuevo, sobre_id} ->
        GestorEntrenadores.actualizar_entrenador(self(), e_nuevo)
        IO.puts("Sobre #{tipo} comprado (ID: #{sobre_id}). Monedas restantes: #{e_nuevo.monedas}")
        %{ctx | sesion: e_nuevo}
      {:error, msg} ->
        IO.puts("Error: #{msg}")
        ctx
    end
  end

  defp procesar_autenticado("abrir_sobre", [id_str], ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    case SistemaSobres.abrir_sobre(e, id_str) do
      {:ok, e_nuevo, pokemones} ->
        GestorEntrenadores.actualizar_entrenador(self(), e_nuevo)
        IO.puts("Sobre abierto! Obtuviste:")
        Enum.each(Enum.with_index(pokemones, 1), fn {pk, i} ->
          tipos = Enum.join(pk.tipos, "/")
          movs = Enum.map(pk.movimientos, &"#{&1.nombre} (#{&1.poder})") |> Enum.join(", ")
          IO.puts("  #{i}. [##{pk.id}] #{String.capitalize(pk.especie)} (#{tipos}) [#{pk.rareza}] - Dueno original: #{pk.dueno_original}")
          IO.puts("     Movimientos: #{movs}")
        end)
        %{ctx | sesion: e_nuevo}
      {:error, msg} ->
        IO.puts("Error: #{msg}")
        ctx
    end
  end

  defp procesar_autenticado("crear_equipo", [nombre | ids_args], ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    ids_str = Enum.join(ids_args, " ")
    ids = String.split(ids_str, ",") |> Enum.map(&String.trim/1)
    if Enum.any?(e.equipos, &(&1.nombre == nombre)) do
      IO.puts("Error: Ya tienes un equipo llamado '#{nombre}'.")
      ctx
    else
      pks = Enum.map(ids, fn id_str ->
        with {id, ""} <- Integer.parse(id_str) do
          Enum.find(e.inventario, &(&1.id == id))
        else
          _ -> nil
        end
      end)
      cond do
        Enum.any?(pks, &is_nil/1) ->
          IO.puts("Error: Algun Pokemon no fue encontrado. Usa 'inventario' para ver tus IDs.")
          ctx
        length(pks) < 1 or length(pks) > 3 ->
          IO.puts("Error: Un equipo debe tener entre 1 y 3 Pokemon.")
          ctx
        true ->
          equipo = %{nombre: nombre, ids: Enum.map(pks, & &1.id)}
          e_nuevo = %{e | equipos: e.equipos ++ [equipo]}
          GestorEntrenadores.actualizar_entrenador(self(), e_nuevo)
          nombres_pk = Enum.map(pks, &"#{String.capitalize(&1.especie)} [##{&1.id}]") |> Enum.join(", ")
          IO.puts("Equipo '#{nombre}' creado con: #{nombres_pk}")
          %{ctx | sesion: e_nuevo}
      end
    end
  end

  defp procesar_autenticado("listar_equipos", _, ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    IO.puts("Equipos guardados:")
    Enum.each(e.equipos, fn eq ->
      pks = Enum.map(eq.ids, fn id ->
        pk = Enum.find(e.inventario, &(&1.id == id))
        if pk, do: "[##{pk.id}] #{String.capitalize(pk.especie)}", else: "[##{id}] (no encontrado)"
      end) |> Enum.join(", ")
      IO.puts("  #{eq.nombre} [#{length(eq.ids)}/3]: #{pks}")
    end)
    %{ctx | sesion: e}
  end

  defp procesar_autenticado("agregar_pokemon_equipo", [nombre_equipo, id_str], ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    with {id, ""} <- Integer.parse(id_str),
         eq_idx when not is_nil(eq_idx) <- Enum.find_index(e.equipos, &(&1.nombre == nombre_equipo)),
         equipo <- Enum.at(e.equipos, eq_idx),
         true <- length(equipo.ids) < 3,
         pk when not is_nil(pk) <- Enum.find(e.inventario, &(&1.id == id)) do
      nuevo_equipo = %{equipo | ids: equipo.ids ++ [id]}
      equipos = List.replace_at(e.equipos, eq_idx, nuevo_equipo)
      e_nuevo = %{e | equipos: equipos}
      GestorEntrenadores.actualizar_entrenador(self(), e_nuevo)
      IO.puts("#{String.capitalize(pk.especie)} anadido al equipo '#{nombre_equipo}'.")
      %{ctx | sesion: e_nuevo}
    else
      false -> IO.puts("Error: El equipo ya tiene 3 Pokemon."); ctx
      _ -> IO.puts("Error: Equipo o Pokemon no encontrado."); ctx
    end
  end

  defp procesar_autenticado("quitar_pokemon_equipo", [nombre_equipo, id_str], ctx) do
    {:ok, e} = GestorEntrenadores.get_entrenador(self())
    # Validar que el equipo no esté cargado activamente en una sala de batalla
    equipo_obj = Enum.find(e.equipos, &(&1.nombre == nombre_equipo))
    ids_en_sala =
      if not is_nil(ctx.sala_batalla) and not is_nil(equipo_obj) do
        sala = GestorSalas.get_sala(ctx.sala_batalla)
        if sala && sala.estado == :en_curso && Map.has_key?(sala.equipo_cargado, self()) do
          Enum.map(sala.equipo_cargado[self()], & &1.id)
        else
          []
        end
      else
        []
      end
    equipo_activo = not is_nil(equipo_obj) and equipo_obj.ids == ids_en_sala and ids_en_sala != []
    if equipo_activo do
      IO.puts("Error: No puedes modificar el equipo '#{nombre_equipo}' mientras está activo en una batalla.")
      ctx
    else
      with {id, ""} <- Integer.parse(id_str),
           eq_idx when not is_nil(eq_idx) <- Enum.find_index(e.equipos, &(&1.nombre == nombre_equipo)),
           equipo <- Enum.at(e.equipos, eq_idx),
           true <- length(equipo.ids) > 1,
           true <- id in equipo.ids do
        nuevo_equipo = %{equipo | ids: Enum.reject(equipo.ids, &(&1 == id))}
        equipos = List.replace_at(e.equipos, eq_idx, nuevo_equipo)
        e_nuevo = %{e | equipos: equipos}
        GestorEntrenadores.actualizar_entrenador(self(), e_nuevo)
        IO.puts("Pokemon ##{id} quitado del equipo '#{nombre_equipo}'.")
        %{ctx | sesion: e_nuevo}
      else
        false -> IO.puts("Error: No puedes quitar el unico Pokemon, o no esta en ese equipo."); ctx
        _ -> IO.puts("Error: Equipo o Pokemon no encontrado."); ctx
      end
    end
  end

  defp procesar_autenticado("usar_equipo", [nombre], ctx) do
    if is_nil(ctx.sala_batalla) do
      IO.puts("Error: Primero unete a una sala de batalla.")
      ctx
    else
      {:ok, e} = GestorEntrenadores.get_entrenador(self())
      equipo_guardado = Enum.find(e.equipos, &(&1.nombre == nombre))
      if is_nil(equipo_guardado) do
        IO.puts("Error: No tienes un equipo llamado '#{nombre}'.")
        ctx
      else
        pks = Enum.map(equipo_guardado.ids, fn id ->
          Enum.find(e.inventario, &(&1.id == id))
        end)
        # Verificar que ningún Pokémon esté ofrecido en una sala de intercambio activa
        ids_en_intercambio =
          if not is_nil(ctx.sala_intercambio) do
            case Intercambio.estado(ctx.sala_intercambio) do
              %{participantes: parts} ->
                yo = Enum.find(parts, &(&1.pid == self()))
                if yo && yo.oferta_id, do: [yo.oferta_id], else: []
              _ -> []
            end
          else
            []
          end
        pk_en_intercambio = Enum.find(pks, fn pk ->
          not is_nil(pk) and pk.id in ids_en_intercambio
        end)
        cond do
          Enum.any?(pks, &is_nil/1) ->
            IO.puts("Error: Faltan Pokemon en el inventario (verifica con 'inventario').")
            ctx
          not is_nil(pk_en_intercambio) ->
            IO.puts("Error: #{String.capitalize(pk_en_intercambio.especie)} [##{pk_en_intercambio.id}] está ofrecido en un intercambio activo.")
            ctx
          true ->
            equipo_batalla = Enum.map(pks, fn pk ->
              %{
                id: pk.id, especie: pk.especie, tipos: pk.tipos,
                dueno_original: pk.dueno_original, rareza: pk.rareza,
                ataque: pk.ataque, defensa: pk.defensa, velocidad: pk.velocidad,
                movimientos: pk.movimientos, salud: 100
              }
            end)
            GestorSalas.usar_equipo(ctx.sala_batalla, self(), equipo_batalla)
            IO.puts("Equipo '#{nombre}' cargado con #{length(pks)} Pokemon.")
            ctx
        end
      end
    end
  end

  defp procesar_autenticado("listar_salas", _, ctx) do
    salas = GestorSalas.listar_salas()
    if Enum.empty?(salas) do
      IO.puts("No hay salas disponibles. Crea una con: crear_sala")
    else
      IO.puts("=== Salas disponibles ===")
      Enum.each(salas, fn s ->
        jugadores = Enum.map(s.jugadores, & &1.usuario) |> Enum.join(", ")
        IO.puts("  #{s.id} | #{s.estado} | Jugadores: [#{jugadores}] | Turno: #{s.tiempo_turno}s")
      end)
    end
    ctx
  end

  defp procesar_autenticado("crear_sala", args, ctx) do
    if not is_nil(ctx.sala_batalla) do
      IO.puts("Error: Ya estás en una sala de batalla. Sal primero.")
      ctx
    else
      # Acepta: crear_sala, crear_sala tiempo_turno=30, crear_sala tiempo_turno 30
      arg_str = Enum.join(args, " ")
      tiempo =
        cond do
          Regex.match?(~r/tiempo_turno\s*=\s*(\d+)/, arg_str) ->
            [_, t] = Regex.run(~r/tiempo_turno\s*=\s*(\d+)/, arg_str)
            String.to_integer(t)
          true -> 20
        end
      {:ok, id_sala} = GestorSalas.crear_sala(tiempo)
      GestorSalas.unirse_sala(id_sala, self(), ctx.sesion.usuario)
      IO.puts("Sala #{id_sala} creada. Tiempo de turno: #{tiempo}s.")
      %{ctx | sala_batalla: id_sala}
    end
  end

  defp procesar_autenticado("unirse_sala", [id_sala], ctx) do
    case GestorSalas.unirse_sala(id_sala, self(), ctx.sesion.usuario) do
      {:ok, n} ->
        IO.puts("Te uniste a la sala #{id_sala} (#{n}/2 jugadores).")
        %{ctx | sala_batalla: id_sala}
      {:error, msg} ->
        IO.puts("Error: #{msg}")
        ctx
    end
  end

  defp procesar_autenticado("iniciar_batalla", [id_sala], ctx) do
    case GestorSalas.iniciar_batalla(id_sala) do
      {:ok, nodo} ->
        IO.puts("Batalla iniciada! Nodo: #{nodo}")
        ctx
      {:error, msg} ->
        IO.puts("Error: #{msg}")
        ctx
    end
  end

  defp procesar_autenticado("ataque", [mov | _], ctx) do
    if is_nil(ctx.sala_batalla) do
      IO.puts("No estas en una sala de batalla.")
      ctx
    else
      case PokemonBattle.Batalla.enviar_accion(ctx.sala_batalla, self(), {:ataque, mov}) do
        :ok -> ctx
        {:error, msg} -> IO.puts("Error: #{msg}"); ctx
      end
    end
  end

  defp procesar_autenticado("cambiar", [id_str], ctx) do
    if is_nil(ctx.sala_batalla) do
      IO.puts("No estas en una sala de batalla.")
      ctx
    else
      case PokemonBattle.Batalla.enviar_accion(ctx.sala_batalla, self(), {:cambiar, id_str}) do
        :ok -> ctx
        {:error, msg} -> IO.puts("Error: #{msg}"); ctx
      end
    end
  end

  defp procesar_autenticado("rendirse", _, ctx) do
    if is_nil(ctx.sala_batalla) do
      IO.puts("No estas en una sala de batalla.")
      ctx
    else
      PokemonBattle.Batalla.enviar_accion(ctx.sala_batalla, self(), :rendirse)
      %{ctx | sala_batalla: nil}
    end
  end

  defp procesar_autenticado("crear_sala_intercambio", _, ctx) do
    cond do
      not is_nil(ctx.sala_intercambio) ->
        IO.puts("Error: Ya tienes una sala de intercambio activa. Cancela primero con cancelar_intercambio.")
        ctx
      not is_nil(ctx.sala_batalla) ->
        IO.puts("Error: No puedes crear una sala de intercambio mientras estás en una batalla activa.")
        ctx
      true ->
        codigo = :rand.uniform(999)
        {:ok, _} = SupervisorBatallas.iniciar_intercambio(codigo)
        {:ok, e} = GestorEntrenadores.get_entrenador(self())
        Intercambio.unirse(codigo, self(), e.usuario, e.inventario)
        IO.puts("[Sala IC-#{codigo} creada] Comparte este codigo con el otro entrenador.")
        %{ctx | sala_intercambio: codigo}
    end
  end

  defp procesar_autenticado("unirse_sala_intercambio", [codigo_str], ctx) do
    cond do
      not is_nil(ctx.sala_intercambio) ->
        IO.puts("Error: Ya estás en una sala de intercambio activa.")
        ctx
      not is_nil(ctx.sala_batalla) ->
        IO.puts("Error: No puedes unirte a un intercambio mientras estás en una batalla activa.")
        ctx
      true ->
        # Aceptar tanto "IC-123" como "123"
        codigo_limpio = String.replace(codigo_str, ~r/^IC-/i, "")
        case Integer.parse(codigo_limpio) do
          {codigo, ""} ->
            {:ok, e} = GestorEntrenadores.get_entrenador(self())
            case Intercambio.unirse(codigo, self(), e.usuario, e.inventario) do
              :ok ->
                IO.puts("[Sala IC-#{codigo}] Te uniste correctamente.")
                %{ctx | sala_intercambio: codigo}
              {:error, msg} -> IO.puts("Error: #{msg}"); ctx
            end
          _ ->
            IO.puts("Codigo invalido. Usa el formato: IC-123 o simplemente 123.")
            ctx
        end
    end
  end

  defp procesar_autenticado("ofrecer_pokemon", [id_str], ctx) do
    if is_nil(ctx.sala_intercambio) do
      IO.puts("No estas en una sala de intercambio.")
      ctx
    else
      case Intercambio.ofrecer(ctx.sala_intercambio, self(), id_str) do
        :ok -> ctx
        {:error, msg} -> IO.puts("Error: #{msg}"); ctx
      end
    end
  end

  defp procesar_autenticado("confirmar_intercambio", _, ctx) do
    if is_nil(ctx.sala_intercambio) do
      IO.puts("No estas en una sala de intercambio.")
      ctx
    else
      case Intercambio.confirmar(ctx.sala_intercambio, self()) do
        :ok -> %{ctx | sala_intercambio: nil}
        {:error, msg} -> IO.puts("Error: #{msg}"); ctx
      end
    end
  end

  defp procesar_autenticado("cancelar_intercambio", _, ctx) do
    if ctx.sala_intercambio do
      Intercambio.cancelar(ctx.sala_intercambio, self())
    end
    %{ctx | sala_intercambio: nil}
  end

  defp procesar_autenticado("conectar_nodo", [nodo_str], ctx) do
    case Cluster.conectar(nodo_str) do
      {:ok, msg} -> IO.puts(msg)
      {:error, msg} -> IO.puts("Error: #{msg}")
    end
    ctx
  end

  defp procesar_autenticado("nodos", _, ctx) do
    nodos = Cluster.nodos_conectados()
    IO.puts("Nodos: #{Enum.join(nodos, ", ")}")
    ctx
  end

  defp procesar_autenticado(cmd, _, ctx) do
    IO.puts("Comando desconocido: '#{cmd}'. Escribe 'ayuda' para ver los comandos.")
    ctx
  end
end
 