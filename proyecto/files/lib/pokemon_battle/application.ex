defmodule PokemonBattle.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Crear carpeta data si no existe
    File.mkdir_p!("data")
    unless File.exists?("data/battles.log"), do: File.write!("data/battles.log", "")

    children = [
      {PokemonBattle.GestorEntrenadores, []},
      {PokemonBattle.SupervisorBatallas, []},
      {PokemonBattle.GestorSalas, []},
    ]

    opts = [strategy: :one_for_one, name: PokemonBattle.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
