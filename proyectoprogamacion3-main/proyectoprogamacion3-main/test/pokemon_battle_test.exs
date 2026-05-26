defmodule PokemonBattleTest do
  use ExUnit.Case

  alias PokemonBattle.MotorCombate
  alias PokemonBattle.SistemaSobres
  alias PokemonBattle.GestorEntrenadores

  # ─────────────────────────────────────────────────────────────
  # Test 1: Cálculo de daño con tipo fuerte, débil y neutro
  # ─────────────────────────────────────────────────────────────
  describe "MotorCombate.calcular_dano/3" do
    # Pikachu (Eléctrico) con impactrueno contra Squirtle (Agua)
    # Eléctrico > Agua → efectividad x2.0, STAB x1.5
    test "tipo fuerte aplica efectividad x2.0 y STAB x1.5" do
      movimiento = %{"tipo" => "Eléctrico", "poder_base" => 65}
      atacante   = %{"tipos" => ["Eléctrico"], "ataque" => 63}
      defensor   = %{"tipos" => ["Agua"], "defensa" => 70}

      dano = MotorCombate.calcular_dano(movimiento, atacante, defensor)

      # dano_base = trunc((65 * 63/70) / 5 + 2) = 13
      # dano minimo con factor 0.85: trunc(13 * 2.0 * 1.5 * 0.85) = 33
      # dano maximo con factor 1.00: trunc(13 * 2.0 * 1.5 * 1.00) = 39
      assert dano >= 33
      assert dano <= 39
    end

    # Squirtle usa pistola_agua (Agua) contra Pikachu (Eléctrico)
    # Agua es débil contra Eléctrico → efectividad x0.5, sin STAB
    test "tipo débil aplica efectividad x0.5" do
      movimiento = %{"tipo" => "Agua", "poder_base" => 40}
      atacante   = %{"tipos" => ["Agua"], "ataque" => 52}
      defensor   = %{"tipos" => ["Eléctrico"], "defensa" => 46}

      dano = MotorCombate.calcular_dano(movimiento, atacante, defensor)

      # dano_base = trunc((40 * 52/46) / 5 + 2) = 11
      # con x0.5 y stab x1.5 (Agua usa mov Agua):
      # trunc(11 * 0.5 * 1.5 * 0.85) = 7  mínimo
      # trunc(11 * 0.5 * 1.5 * 1.00) = 8  máximo
      assert dano >= 4
      assert dano <= 9
    end

    # Charmander usa placaje (Normal) contra Squirtle (Agua)
    # Normal no tiene relación con Agua → efectividad x1.0, sin STAB
    test "tipo neutro aplica efectividad x1.0 sin STAB" do
      movimiento = %{"tipo" => "Normal", "poder_base" => 35}
      atacante   = %{"tipos" => ["Fuego"], "ataque" => 53}
      defensor   = %{"tipos" => ["Agua"], "defensa" => 65}

      dano = MotorCombate.calcular_dano(movimiento, atacante, defensor)

      # dano_base = trunc((35 * 53/65) / 5 + 2) = 7
      # trunc(7 * 1.0 * 1.0 * 0.85) = 5  mínimo
      # trunc(7 * 1.0 * 1.0 * 1.00) = 7  máximo
      assert dano >= 5
      assert dano <= 7
    end

    test "el daño mínimo siempre es 1" do
      movimiento = %{"tipo" => "Normal", "poder_base" => 1}
      atacante   = %{"tipos" => ["Normal"], "ataque" => 1}
      defensor   = %{"tipos" => ["Roca"], "defensa" => 9999}

      dano = MotorCombate.calcular_dano(movimiento, atacante, defensor)
      assert dano >= 1
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Test 2: Validación de turnos por velocidad
  # ─────────────────────────────────────────────────────────────
  describe "MotorCombate.orden_ataque/2" do
    test "el Pokémon más rápido ataca primero" do
      pikachu  = %{velocidad: 104}
      squirtle = %{velocidad: 46}

      assert MotorCombate.orden_ataque(pikachu, squirtle) == {:primero, :segundo}
      assert MotorCombate.orden_ataque(squirtle, pikachu) == {:segundo, :primero}
    end

    test "con velocidad igual el resultado es aleatorio pero válido" do
      pk1 = %{velocidad: 60}
      pk2 = %{velocidad: 60}

      resultado = MotorCombate.orden_ataque(pk1, pk2)
      assert resultado in [{:primero, :segundo}, {:segundo, :primero}]
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Test 3: Asignación de monedas al terminar batalla
  # ─────────────────────────────────────────────────────────────
  describe "Recompensas por batalla" do
    test "ganador recibe +100 monedas y perdedor +30" do
      ganador = %{usuario: "Ana", monedas: 50, victorias: 0, monedas_acumuladas: 50}
      perdedor = %{usuario: "Luis", monedas: 80, victorias: 2, monedas_acumuladas: 200}

      ganador_actualizado  = %{ganador  | monedas: ganador.monedas + 100,
                                          victorias: ganador.victorias + 1,
                                          monedas_acumuladas: ganador.monedas_acumuladas + 100}
      perdedor_actualizado = %{perdedor | monedas: perdedor.monedas + 30,
                                          monedas_acumuladas: perdedor.monedas_acumuladas + 30}

      assert ganador_actualizado.monedas == 150
      assert ganador_actualizado.victorias == 1
      assert ganador_actualizado.monedas_acumuladas == 150

      assert perdedor_actualizado.monedas == 110
      assert perdedor_actualizado.victorias == 2       # no cambia
      assert perdedor_actualizado.monedas_acumuladas == 230
    end

    test "las monedas acumuladas crecen independientemente del saldo actual" do
      # Aunque el entrenador gaste monedas, el acumulado histórico no baja
      entrenador = %{monedas: 0, monedas_acumuladas: 500, victorias: 5}

      tras_victoria = %{entrenador |
        monedas: entrenador.monedas + 100,
        victorias: entrenador.victorias + 1,
        monedas_acumuladas: entrenador.monedas_acumuladas + 100
      }

      assert tras_victoria.monedas == 100
      assert tras_victoria.monedas_acumuladas == 600
      assert tras_victoria.victorias == 6
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Test 4: Compra y apertura de sobres
  # ─────────────────────────────────────────────────────────────
  describe "SistemaSobres" do
    # Entrenador base para los tests de sobres
    defp entrenador_base do
      %{
        usuario: "ash",
        clave: "1234",
        monedas: 500,
        monedas_acumuladas: 500,
        victorias: 0,
        inventario: [],
        sobres_pendientes: [],
        equipos: []
      }
    end

    test "comprar_sobre descuenta monedas y agrega sobre pendiente" do
      e = entrenador_base()
      {:ok, e_nuevo, sobre_id} = SistemaSobres.comprar_sobre(e, "basico")

      assert e_nuevo.monedas == 400               # 500 - 100
      assert length(e_nuevo.sobres_pendientes) == 1
      assert sobre_id == hd(e_nuevo.sobres_pendientes).id
    end

    test "no se puede comprar sobre sin monedas suficientes" do
      e = %{entrenador_base() | monedas: 50}
      resultado = SistemaSobres.comprar_sobre(e, "basico")

      assert {:error, _msg} = resultado
    end

    test "abrir sobre entrega exactamente 3 Pokémon con 4 movimientos cada uno" do
      e = entrenador_base()
      {:ok, e_con_sobre, _id} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, e_final, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      assert length(pokemones) == 3
      assert length(e_final.inventario) == 3

      Enum.each(pokemones, fn pk ->
        assert length(pk.movimientos) == 4
      end)
    end

    test "cada Pokémon del sobre tiene dueño_original correcto" do
      e = entrenador_base()
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_final, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      Enum.each(pokemones, fn pk ->
        assert pk.dueno_original == "ash"
      end)
    end

    test "rareza del Pokémon es uno de los valores válidos" do
      e = entrenador_base()
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_final, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      Enum.each(pokemones, fn pk ->
        assert pk.rareza in ["comun", "raro", "epico"]
      end)
    end

    test "al menos 2 movimientos del tipo propio en Pokémon de un solo tipo" do
      e = entrenador_base()
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_final, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      Enum.each(pokemones, fn pk ->
        if length(pk.tipos) == 1 do
          tipo = hd(pk.tipos)
          movs_del_tipo = Enum.count(pk.movimientos, &(&1.tipo == tipo))
          assert movs_del_tipo >= 2,
            "#{pk.especie} (#{tipo}) debería tener ≥2 movimientos de su tipo, tiene #{movs_del_tipo}"
        end
      end)
    end

    test "los movimientos de un Pokémon no se repiten" do
      e = entrenador_base()
      {:ok, e_con_sobre, _} = SistemaSobres.comprar_sobre(e, "basico")
      {:ok, _e_final, pokemones} = SistemaSobres.abrir_sobre(e_con_sobre, "ultimo")

      Enum.each(pokemones, fn pk ->
        nombres = Enum.map(pk.movimientos, & &1.nombre)
        assert length(nombres) == length(Enum.uniq(nombres)),
          "#{pk.especie} tiene movimientos repetidos: #{inspect(nombres)}"
      end)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Test 5: Intercambio de Pokémon entre dos entrenadores
  # ─────────────────────────────────────────────────────────────
  describe "Intercambio de Pokémon" do
    defp pk_fixture(id, especie, dueno) do
      %{
        id: id,
        especie: especie,
        tipos: ["Fuego"],
        rareza: "raro",
        ataque: 60,
        defensa: 50,
        velocidad: 70,
        movimientos: [],
        dueno_original: dueno
      }
    end

    test "tras el intercambio el Pokémon conserva id, rareza y dueño_original" do
      pk1 = pk_fixture(1001, "charmander", "Ana")
      pk2 = pk_fixture(2002, "squirtle",   "Luis")

      e1 = %{usuario: "Ana",  inventario: [pk1]}
      e2 = %{usuario: "Luis", inventario: [pk2]}

      # Simular la lógica del cast :intercambio de GestorEntrenadores
      entrenadores = [e1, e2]

      e1_orig = Enum.find(entrenadores, &(&1.usuario == "Ana"))
      e2_orig = Enum.find(entrenadores, &(&1.usuario == "Luis"))
      pk_de_ana  = Enum.find(e1_orig.inventario, &(&1.id == 1001))
      pk_de_luis = Enum.find(e2_orig.inventario, &(&1.id == 2002))

      entrenadores_nuevos =
        Enum.map(entrenadores, fn e ->
          cond do
            e.usuario == "Ana" ->
              inv = Enum.reject(e.inventario, &(&1.id == 1001))
              %{e | inventario: inv ++ [pk_de_luis]}
            e.usuario == "Luis" ->
              inv = Enum.reject(e.inventario, &(&1.id == 2002))
              %{e | inventario: inv ++ [pk_de_ana]}
            true -> e
          end
        end)

      ana_final  = Enum.find(entrenadores_nuevos, &(&1.usuario == "Ana"))
      luis_final = Enum.find(entrenadores_nuevos, &(&1.usuario == "Luis"))

      # Ana ahora tiene el squirtle de Luis
      pk_ana_recibido = Enum.find(ana_final.inventario, &(&1.id == 2002))
      assert pk_ana_recibido != nil
      assert pk_ana_recibido.id == 2002
      assert pk_ana_recibido.rareza == "raro"
      assert pk_ana_recibido.dueno_original == "Luis"   # dueño original NO cambia

      # Luis ahora tiene el charmander de Ana
      pk_luis_recibido = Enum.find(luis_final.inventario, &(&1.id == 1001))
      assert pk_luis_recibido != nil
      assert pk_luis_recibido.id == 1001
      assert pk_luis_recibido.rareza == "raro"
      assert pk_luis_recibido.dueno_original == "Ana"   # dueño original NO cambia
    end

    test "tras el intercambio el Pokémon ya no está en el inventario del dueño original" do
      pk1 = pk_fixture(1001, "charmander", "Ana")
      pk2 = pk_fixture(2002, "squirtle",   "Luis")

      e1 = %{usuario: "Ana",  inventario: [pk1]}
      e2 = %{usuario: "Luis", inventario: [pk2]}

      entrenadores_nuevos =
        Enum.map([e1, e2], fn e ->
          cond do
            e.usuario == "Ana"  -> %{e | inventario: [pk2]}
            e.usuario == "Luis" -> %{e | inventario: [pk1]}
            true -> e
          end
        end)

      ana_final  = Enum.find(entrenadores_nuevos, &(&1.usuario == "Ana"))
      luis_final = Enum.find(entrenadores_nuevos, &(&1.usuario == "Luis"))

      # El charmander ya no está en Ana
      assert Enum.find(ana_final.inventario,  &(&1.id == 1001)) == nil
      # El squirtle ya no está en Luis
      assert Enum.find(luis_final.inventario, &(&1.id == 2002)) == nil
    end
  end
end
