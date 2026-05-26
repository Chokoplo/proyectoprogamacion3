defmodule PokemonBattle.MotorCombate do
  @moduledoc "Cálculo de daño, efectividad de tipos y STAB."

  # Tabla de efectividades: {tipo_movimiento, tipo_defensor} => multiplicador
  @efectividades %{
    {"Fuego", "Planta"} => 2.0,
    {"Fuego", "Hielo"} => 2.0,
    {"Fuego", "Bicho"} => 2.0,
    {"Agua", "Fuego"} => 2.0,
    {"Agua", "Roca"} => 2.0,
    {"Agua", "Tierra"} => 2.0,
    {"Planta", "Agua"} => 2.0,
    {"Planta", "Roca"} => 2.0,
    {"Planta", "Tierra"} => 2.0,
    {"Eléctrico", "Agua"} => 2.0,
    {"Eléctrico", "Volador"} => 2.0,
    {"Roca", "Fuego"} => 2.0,
    {"Roca", "Hielo"} => 2.0,
    {"Roca", "Volador"} => 2.0,
    {"Roca", "Bicho"} => 2.0,
    # Inversas (debilidades)
    {"Planta", "Fuego"} => 0.5,
    {"Hielo", "Fuego"} => 0.5,
    {"Bicho", "Fuego"} => 0.5,
    {"Fuego", "Agua"} => 0.5,
    {"Roca", "Agua"} => 0.5,
    {"Tierra", "Agua"} => 0.5,
    {"Agua", "Planta"} => 0.5,
    {"Roca", "Planta"} => 0.5,
    {"Tierra", "Planta"} => 0.5,
    {"Agua", "Eléctrico"} => 0.5,
    {"Volador", "Eléctrico"} => 0.5,
    {"Fuego", "Roca"} => 0.5,
    {"Hielo", "Roca"} => 0.5,
    {"Volador", "Roca"} => 0.5,
    {"Bicho", "Roca"} => 0.5,
  }

  @doc "Calcula el daño de un ataque."
  def calcular_dano(movimiento, atacante, defensor) do
    poder = movimiento["poder_base"]
    tipo_mov = movimiento["tipo"]
    tipos_atacante = atacante["tipos"]
    tipos_defensor = defensor["tipos"]

    atk = atacante["ataque"]
    def_ = defensor["defensa"]

    efectividad = calcular_efectividad(tipo_mov, tipos_defensor)
    stab = if tipo_mov in tipos_atacante, do: 1.5, else: 1.0
    factor_aleatorio = 0.85 + :rand.uniform() * 0.15

    dano_base = trunc((poder * (atk / def_)) / 5 + 2)
    dano_final = trunc(dano_base * efectividad * stab * factor_aleatorio)

    max(dano_final, 1)
  end

  defp calcular_efectividad(tipo_mov, tipos_defensor) do
    Enum.reduce(tipos_defensor, 1.0, fn tipo_def, acc ->
      mult = Map.get(@efectividades, {tipo_mov, tipo_def}, 1.0)
      acc * mult
    end)
  end

  def mensaje_efectividad(tipo_mov, tipos_defensor) do
    ef = calcular_efectividad(tipo_mov, tipos_defensor)
    cond do
      ef >= 2.0 -> "¡Es muy efectivo!"
      ef <= 0.5 -> "No es muy efectivo..."
      true -> ""
    end
  end

  @doc "Devuelve {:primero, :segundo} según velocidad; desempate aleatorio."
  def orden_ataque(pk1, pk2) do
    v1 = Map.get(pk1, :velocidad) || Map.get(pk1, "velocidad")
    v2 = Map.get(pk2, :velocidad) || Map.get(pk2, "velocidad")
    cond do
      v1 > v2 -> {:primero, :segundo}
      v2 > v1 -> {:segundo, :primero}
      true ->
        if :rand.uniform(2) == 1, do: {:primero, :segundo}, else: {:segundo, :primero}
    end
  end
end
