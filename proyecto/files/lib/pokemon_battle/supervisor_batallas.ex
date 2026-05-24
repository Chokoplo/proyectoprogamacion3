defmodule PokemonBattle.SupervisorBatallas do
  use Supervisor

  def start_link(_), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: PokemonBattle.RegistrySalas},
      {DynamicSupervisor, name: PokemonBattle.DynSupervisor, strategy: :one_for_one}
    ]
    Supervisor.init(children, strategy: :one_for_all)
  end

  def iniciar_batalla(id_sala) do
    spec = {PokemonBattle.Batalla, id_sala}
    DynamicSupervisor.start_child(PokemonBattle.DynSupervisor, spec)
  end

  def iniciar_intercambio(codigo) do
    spec = {PokemonBattle.Intercambio, codigo}
    DynamicSupervisor.start_child(PokemonBattle.DynSupervisor, spec)
  end
end
