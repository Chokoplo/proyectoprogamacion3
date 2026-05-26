defmodule PokemonBattle.Persistencia do
  @moduledoc "Lectura y escritura de archivos JSON y log de batallas."

  @trainers_file "data/trainers.json"
  @pokemon_file "data/pokemon.json"
  @moves_file "data/moves.json"
  @tienda_file "data/tienda.json"
  @battles_log "data/battles.log"

  # --- Trainers ---
def cargar_entrenadores do
  case File.read(@trainers_file) do
    {:ok, content} ->
      case Jason.decode(content) do
        {:ok, data} -> data
        _ -> []
      end
    _ -> []
  end
end

  def guardar_entrenadores(entrenadores) do
    File.write!(@trainers_file, Jason.encode!(entrenadores, pretty: true))
  end

  # --- Pokemon catalog ---
  def cargar_pokemon_catalogo do
    case File.read(@pokemon_file) do
      {:ok, content} -> Jason.decode!(content)
      _ -> []
    end
  end

  # --- Moves ---
  def cargar_movimientos do
    case File.read(@moves_file) do
      {:ok, content} -> Jason.decode!(content)
      _ -> []
    end
  end

  # --- Tienda ---
  def cargar_tienda do
    case File.read(@tienda_file) do
      {:ok, content} -> Jason.decode!(content)
      _ -> []
    end
  end

  # --- Battles log ---
  def registrar_batalla(info) when is_map(info) do
    linea =
      "#{info.fecha} | sala=#{info.sala} | jugadores=#{info.jugadores} | " <>
      "ganador=#{info.ganador} | perdedor=#{info.perdedor} | " <>
      "turnos=#{info.turnos} | duracion=#{Map.get(info, :duracion, "N/A")}s | nodo=#{info.nodo}\n"
    File.write!(@battles_log, linea, [:append])
  end

  def registrar_batalla(info) when is_binary(info) do
    linea = "#{DateTime.utc_now()} | #{info}\n"
    File.write!(@battles_log, linea, [:append])
  end
end
