defmodule PokemonBattle.Cluster do
  @moduledoc "Gestión de nodos distribuidos."

  def conectar(nodo_str) do
    nodo = String.to_atom(nodo_str)
    case Node.connect(nodo) do
      true -> {:ok, "Conectado a #{nodo}"}
      false -> {:error, "No se pudo conectar a #{nodo}"}
      :ignored -> {:error, "Nodo ignorado (¿cookie diferente?)"}
    end
  end

  def nodos_conectados do
    [node() | Node.list()]
  end

  def elegir_nodo do
    Enum.random(nodos_conectados())
  end

  def estado_cluster do
    nodos = nodos_conectados()
    IO.puts("Nodos en el cluster: #{Enum.join(nodos, ", ")}")
  end
end
