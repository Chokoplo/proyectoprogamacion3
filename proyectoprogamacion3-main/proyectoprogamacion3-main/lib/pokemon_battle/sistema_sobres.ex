
defmodule PokemonBattle.SistemaSobres do
  @moduledoc "Gestión de compra y apertura de sobres."

  alias PokemonBattle.Persistencia

  @rareza_rangos %{
    "comun" => {2, 8},
    "raro" => {10, 20},
    "epico" => {25, 40}
  }

  def comprar_sobre(entrenador, tipo_sobre) do
    tienda = Persistencia.cargar_tienda()
    tipo_info = Enum.find(tienda, &(&1["tipo"] == tipo_sobre))

    cond do
      is_nil(tipo_info) ->
        {:error, "Tipo de sobre '#{tipo_sobre}' no existe. Usa: basico, avanzado"}

      entrenador.monedas < tipo_info["precio"] ->
        {:error, "No tienes suficientes monedas. Necesitas #{tipo_info["precio"]}, tienes #{entrenador.monedas}"}

      true ->
        sobre_id = :rand.uniform(999_999)
        sobre = %{id: sobre_id, tipo: tipo_sobre}
        sobres = entrenador.sobres_pendientes ++ [sobre]
        entrenador_actualizado = %{entrenador |
          monedas: entrenador.monedas - tipo_info["precio"],
          sobres_pendientes: sobres
        }
        {:ok, entrenador_actualizado, sobre_id}
    end
  end

  def abrir_sobre(entrenador, identificador) do
    sobre =
      case identificador do
        "ultimo" -> List.last(entrenador.sobres_pendientes)
        id_str ->
          with {id, ""} <- Integer.parse(id_str) do
            Enum.find(entrenador.sobres_pendientes, &(&1.id == id))
          else
            _ -> nil
          end
      end

    if is_nil(sobre) do
      {:error, "No se encontró el sobre. Usa 'inventario' para ver tus sobres."}
    else
      tienda = Persistencia.cargar_tienda()
      tipo_sobre_str = to_string(sobre.tipo)
      tipo_info = Enum.find(tienda, &(&1["tipo"] == tipo_sobre_str))
      probabilidades = tipo_info["probabilidades"]

      catalogo = Persistencia.cargar_pokemon_catalogo()
      todos_movimientos = Persistencia.cargar_movimientos()

      pokemones = Enum.map(1..3, fn _ ->
        especie = Enum.random(catalogo)
        rareza = sortear_rareza(probabilidades)
        {min_r, max_r} = @rareza_rangos[rareza]
        factor_rareza = min_r + :rand.uniform(max_r - min_r + 1) - 1

        ataque = round(especie["ataque_base"] * (1 + factor_rareza / 100))
        defensa = round(especie["defensa_base"] * (1 + factor_rareza / 100))
        velocidad = round(especie["velocidad_base"] * (1 + factor_rareza / 100))

        movimientos = asignar_movimientos(especie["tipos"], todos_movimientos)

        %{
          id: :rand.uniform(999_999),
          especie: especie["especie"],
          tipos: especie["tipos"],
          dueno_original: entrenador.usuario,
          rareza: rareza,
          ataque: ataque,
          defensa: defensa,
          velocidad: velocidad,
          salud_maxima: 100,
          movimientos: movimientos
        }
      end)

      sobres_restantes = Enum.reject(entrenador.sobres_pendientes, &(&1.id == sobre.id))
      nuevo_inventario = entrenador.inventario ++ pokemones

      entrenador_actualizado = %{entrenador |
        sobres_pendientes: sobres_restantes,
        inventario: nuevo_inventario
      }

      {:ok, entrenador_actualizado, pokemones}
    end
  end

  defp sortear_rareza(probabilidades) do
    n = :rand.uniform(100)
    comun = probabilidades["comun"]
    raro = probabilidades["raro"]

    cond do
      n <= comun -> "comun"
      n <= comun + raro -> "raro"
      true -> "epico"
    end
  end

  defp asignar_movimientos(tipos_especie, todos_movimientos) do
    movs_por_tipo = Enum.group_by(todos_movimientos, & &1["tipo"])

    # Al menos 2 del/los tipo(s) de la especie
    movs_tipo =
      case tipos_especie do
        [tipo] ->
          pool = Map.get(movs_por_tipo, tipo, [])
          Enum.take_random(pool, 2)

        [tipo1, tipo2] ->
          pool1 = Map.get(movs_por_tipo, tipo1, [])
          pool2 = Map.get(movs_por_tipo, tipo2, [])
          [Enum.random(pool1), Enum.random(pool2)]

        _ -> []
      end

    nombres_ya = Enum.map(movs_tipo, & &1["nombre"]) |> MapSet.new()

    # 2 movimientos complementarios de cualquier tipo
    pool_global = Enum.reject(todos_movimientos, &MapSet.member?(nombres_ya, &1["nombre"]))
    movs_extra = Enum.take_random(pool_global, 2)

    Enum.map(movs_tipo ++ movs_extra, fn m ->
      %{nombre: m["nombre"], tipo: m["tipo"], poder: m["poder_base"]}
    end)
  end

  def sobre_gratuito(entrenador) do
    sobre = %{id: :rand.uniform(999_999), tipo: "basico"}
    %{entrenador | sobres_pendientes: [sobre]}
  end
end
