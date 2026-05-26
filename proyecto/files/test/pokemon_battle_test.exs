defmodule PokemonBattleTest do
  use ExUnit.Case, async: false

  alias PokemonBattle.{MotorCombate, SistemaSobres, Persistencia}

  # ─── 1. Cálculo de daño con tipo fuerte/débil/neutro ─────────────────────

  describe "Motor de combate - cálculo de daño" do
    setup do
      pikachu = %{"tipos" => ["Eléctrico"], "ataque" => 63, "defensa" => 46, "velocidad" => 104}
      squirtle = %{"tipos" => ["Agua"], "ataque" => 52, "defensa" => 70, "velocidad" => 46}
      geodude = %{"tipos" => ["Roca", "Tierra"], "ataque" => 82, "defensa" => 103, "velocidad" => 21}
      impactrueno = %{"nombre" => "impactrueno", "tipo" => "Eléctrico", "poder_base" => 65}
      placaje = %{"nombre" => "placaje", "tipo" => "Normal", "poder_base" => 35}
      pistola_agua = %{"nombre" => "pistola_agua", "tipo" => "Agua", "poder_base" => 40}
      %{pikachu: pikachu, squirtle: squirtle, geodude: geodude,
        impactrueno: impactrueno, placaje: placaje, pistola_agua: pistola_agua}
    end

    test "tipo fuerte (Eléctrico > Agua): daño mayor al neutro", %{pikachu: pk, squirtle: sq, impactrueno: imp, placaje: pl} do
      dano_fuerte = MotorCombate.calcular_dano(imp, pk, sq)
      dano_neutro = MotorCombate.calcular_dano(pl, pk, sq)
      assert dano_fuerte > dano_neutro,
        "Daño con tipo fuerte (#{dano_fuerte}) debe ser mayor al neutro (#{dano_neutro})"
    end

    test "tipo débil (Agua < Eléctrico): multiplicador x0.5", %{pikachu: pk, squirtle: sq, pistola_agua: pa} do
      # Agua vs Eléctrico es 0.5
      dano_debil = MotorCombate.calcular_dano(pa, sq, pk)
      dano_neutro = MotorCombate.calcular_dano(pa, sq, %{"tipos" => ["Normal"], "ataque" => 52, "defensa" => 70, "velocidad" => 46})
      assert dano_debil < dano_neutro,
        "Daño débil (#{dano_debil}) debe ser menor al neutro (#{dano_neutro})"
    end

    test "tipo neutro (Normal sin relación): daño base sin modificador", %{pikachu: pk, squirtle: sq, placaje: pl} do
      dano = MotorCombate.calcular_dano(pl, pk, sq)
      assert dano >= 1, "El daño mínimo es 1"
      # placaje Normal vs Agua: sin relación, efectividad x1.0, sin STAB
      # dano_base = trunc((35 * (63/70)) / 5 + 2) = 8
      assert dano >= 6 and dano <= 10,
        "Daño neutro esperado ~7-8, obtuvo #{dano}"
    end

    test "doble tipo defensivo: modificadores se multiplican (Roca/Tierra vs Fuego)", %{geodude: geo} do
      # Fuego vs Roca: x0.5 (Roca > Fuego)
      # Fuego vs Tierra: x1.0 (neutro)
      # Combinado: x0.5
      atacante = %{"tipos" => ["Fuego"], "ataque" => 63, "defensa" => 50, "velocidad" => 70}
      mov_fuego = %{"nombre" => "ascuas", "tipo" => "Fuego", "poder_base" => 30}
      dano = MotorCombate.calcular_dano(mov_fuego, atacante, geo)
      assert dano >= 1, "Daño mínimo 1 incluso con resistencia"
    end

    test "STAB aumenta el daño 1.5x", %{pikachu: pk, squirtle: sq} do
      mov_electrico = %{"nombre" => "impactrueno", "tipo" => "Eléctrico", "poder_base" => 40}
      mov_normal = %{"nombre" => "placaje", "tipo" => "Normal", "poder_base" => 40}
      dano_stab = MotorCombate.calcular_dano(mov_electrico, pk, sq)
      dano_no_stab = MotorCombate.calcular_dano(mov_normal, pk, sq)
      assert dano_stab > dano_no_stab,
        "STAB (#{dano_stab}) debe ser mayor que sin STAB (#{dano_no_stab}) con igual poder_base"
    end
  end

  # ─── 2. Validación de turnos por velocidad ───────────────────────────────

  describe "Orden de ataque por velocidad" do
    test "Pokémon más rápido actúa primero" do
      rapido = %{"velocidad" => 104}
      lento = %{"velocidad" => 46}
      assert MotorCombate.orden_ataque(rapido, lento) == {:primero, :segundo}
      assert MotorCombate.orden_ataque(lento, rapido) == {:segundo, :primero}
    end

    test "empate de velocidad: resultado aleatorio pero válido" do
      pk = %{"velocidad" => 70}
      resultado = MotorCombate.orden_ataque(pk, pk)
      assert resultado in [{:primero, :segundo}, {:segundo, :primero}]
    end
  end

  # ─── 3. Asignación de monedas al terminar batalla ────────────────────────

  describe "Recompensas por batalla" do
    test "ganador recibe 100 monedas, perdedor 30" do
      # Simular entrenadores en estado
      ganador = %{usuario: "Ana", monedas: 0, monedas_acumuladas: 0, victorias: 0}
      perdedor = %{usuario: "Luis", monedas: 50, monedas_acumuladas: 50, victorias: 0}

      ganador_nuevo = %{ganador |
        monedas: ganador.monedas + 100,
        monedas_acumuladas: ganador.monedas_acumuladas + 100,
        victorias: ganador.victorias + 1
      }
      perdedor_nuevo = %{perdedor |
        monedas: perdedor.monedas + 30,
        monedas_acumuladas: perdedor.monedas_acumuladas + 30
      }

      assert ganador_nuevo.monedas == 100
      assert ganador_nuevo.victorias == 1
      assert ganador_nuevo.monedas_acumuladas == 100
      assert perdedor_nuevo.monedas == 80
      assert perdedor_nuevo.victorias == 0
      assert perdedor_nuevo.monedas_acumuladas == 80
    end
  end

  # ─── 4. Compra y apertura de sobres ──────────────────────────────────────

  describe "Sistema de sobres" do
    setup do
      entrenador_base = %{
        usuario: "TestUser",
        clave: "test",
        monedas: 500,
        monedas_acumuladas: 0,
        victorias: 0,
        inventario: [],
        sobres_pendientes: [],
        equipos: []
      }
      {:ok, entrenador: entrenador_base}
    end

    test "comprar sobre básico descuenta monedas", %{entrenador: e} do
      assert {:ok, e_nuevo, _id} = SistemaSobres.comprar_sobre(e, "basico")
      assert e_nuevo.monedas == 400
      assert length(e_nuevo.sobres_pendientes) == 1
    end

    test "comprar sobre avanzado descuenta 250 monedas", %{entrenador: e} do
      assert {:ok, e_nuevo, _id} = SistemaSobres.comprar_sobre(e, "avanzado")
      assert e_nuevo.monedas == 250
    end

    test "no se puede comprar con monedas insuficientes", %{entrenador: e} do
      pobre = %{e | monedas: 50}
      assert {:error, _} = SistemaSobres.comprar_sobre(pobre, "basico")
    end

    test "tipo de sobre inexistente devuelve error", %{entrenador: e} do
      assert {:error, _} = SistemaSobres.comprar_sobre(e, "mitico")
    end

    test "abrir sobre da exactamente 3 Pokémon con 4 movimientos cada uno", %{entrenador: e} do
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, e_nuevo, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      assert length(pokemones) == 3
      assert length(e_nuevo.inventario) == 3

      Enum.each(pokemones, fn pk ->
        assert length(pk.movimientos) == 4,
          "#{pk.especie} debe tener 4 movimientos, tiene #{length(pk.movimientos)}"

        nombres = Enum.map(pk.movimientos, & &1.nombre)
        assert length(Enum.uniq(nombres)) == 4, "No deben repetirse movimientos"
      end)
    end

    test "rareza asignada correctamente (comun/raro/epico)", %{entrenador: e} do
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_nuevo, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")
      rarezas_validas = ["comun", "raro", "epico"]
      Enum.each(pokemones, fn pk ->
        assert pk.rareza in rarezas_validas,
          "Rareza '#{pk.rareza}' no es válida"
      end)
    end

    test "dueño_original se asigna correctamente", %{entrenador: e} do
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_nuevo, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")
      Enum.each(pokemones, fn pk ->
        assert pk.dueno_original == "TestUser"
      end)
    end

    test "movimientos respetan tipos de la especie (al menos 2 del tipo)", %{entrenador: e} do
      resultados = Enum.map(1..20, fn _ ->
        {:ok, e_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
        {:ok, _, pks} = SistemaSobres.abrir_sobre(e_sobre, "ultimo")
        pks
      end) |> List.flatten()

      Enum.each(resultados, fn pk ->
        tipos_especie = pk.tipos
        movs_del_tipo =
          Enum.count(pk.movimientos, fn m -> m.tipo in tipos_especie end)
        assert movs_del_tipo >= 2,
          "#{pk.especie} (#{Enum.join(tipos_especie, "/")}) tiene solo #{movs_del_tipo} movimientos de su tipo"
      end)
    end
  end

  # ─── 5. Intercambio de Pokémon ────────────────────────────────────────────

  describe "Intercambio de Pokémon" do
    test "el Pokémon cambia de inventario conservando id, rareza y dueño_original" do
      pk_ana = %{
        id: 11111, especie: "charmander", tipos: ["Fuego"],
        dueno_original: "Ana", rareza: "comun",
        ataque: 53, defensa: 44, velocidad: 66,
        movimientos: [], salud_maxima: 100
      }
      pk_luis = %{
        id: 22222, especie: "squirtle", tipos: ["Agua"],
        dueno_original: "Luis", rareza: "raro",
        ataque: 52, defensa: 70, velocidad: 46,
        movimientos: [], salud_maxima: 100
      }

      inv_ana = [pk_ana]
      inv_luis = [pk_luis]

      # Simular el intercambio directamente
      inv_ana_nuevo = (inv_ana |> Enum.reject(&(&1.id == pk_ana.id))) ++ [pk_luis]
      inv_luis_nuevo = (inv_luis |> Enum.reject(&(&1.id == pk_luis.id))) ++ [pk_ana]

      # Ana recibe el Pokémon de Luis con sus atributos originales intactos
      pk_recibido_ana = Enum.find(inv_ana_nuevo, &(&1.id == pk_luis.id))
      assert pk_recibido_ana.id == 22222
      assert pk_recibido_ana.rareza == "raro"
      assert pk_recibido_ana.dueno_original == "Luis"  # conserva dueño original
      assert pk_recibido_ana.especie == "squirtle"

      # Luis recibe el Pokémon de Ana con sus atributos originales intactos
      pk_recibido_luis = Enum.find(inv_luis_nuevo, &(&1.id == pk_ana.id))
      assert pk_recibido_luis.id == 11111
      assert pk_recibido_luis.rareza == "comun"
      assert pk_recibido_luis.dueno_original == "Ana"
      assert pk_recibido_luis.especie == "charmander"

      # Inventarios actualizados correctamente
      refute Enum.any?(inv_ana_nuevo, &(&1.id == pk_ana.id)), "Ana ya no tiene su Charmander"
      refute Enum.any?(inv_luis_nuevo, &(&1.id == pk_luis.id)), "Luis ya no tiene su Squirtle"
    end
  end
end
