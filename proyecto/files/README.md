# ⚡ Pokémon Battle Platform — Elixir

Plataforma de batallas Pokémon por turnos, implementada en Elixir con concurrencia, distribución y persistencia.

## Requisitos

- Elixir 1.14+
- Erlang/OTP 25+

## Instalación

```bash
cd pokemon_battle
mix deps.get
mix compile
```

## Ejecutar las pruebas

```bash
mix test
```

## Iniciar la aplicación (modo interactivo)

```bash
iex --sname nodo1@localhost -S mix run --no-halt
```

En la consola IEx, escribe:
```elixir
PokemonBattle.Servidor.iniciar()
```

## Modo distribuido (2 nodos)

**Terminal 1 (Nodo arena):**
```bash
iex --sname arena@localhost --cookie pokemon -S mix run --no-halt
```

**Terminal 2 (Nodo sala):**
```bash
iex --sname sala@localhost --cookie pokemon -S mix run --no-halt
```

Dentro de cada consola IEx:
```elixir
PokemonBattle.Servidor.iniciar()
```

Para conectar los nodos, usa el comando:
```
conectar_nodo arena@localhost
```

## Flujo de ejemplo completo

```
iniciar ana 1234
abrir_sobre ultimo
inventario
crear_sala_intercambio        # Ana crea sala IC-xxx
# Compartir código con Luis

# Luis en otra consola:
iniciar luis 1234
abrir_sobre ultimo
unirse_sala_intercambio xxx

# Ofrecer e intercambiar
ofrecer_pokemon <id>
confirmar_intercambio

# Batalla
crear_equipo rapido <id1>,<id2>
crear_sala
# Luis:
unirse_sala S-1001
crear_equipo tanque <id3>,<id4>
usar_equipo rapido / usar_equipo tanque
iniciar_batalla S-1001

# En turnos:
ataque impactrueno
cambiar <id_pokemon>
rendirse
```

## Arquitectura

```
lib/pokemon_battle/
├── application.ex         # Supervisor raíz
├── servidor.ex            # CLI + enrutamiento de comandos
├── gestor_entrenadores.ex # Sesión, perfil, inventario, monedas, equipos
├── sistema_sobres.ex      # Compra/apertura de sobres + movimientos
├── intercambio.ex         # GenServer de sala de intercambio
├── gestor_salas.ex        # Creación/gestión de salas de batalla
├── batalla.ex             # GenServer de batalla (turnos, daño)
├── supervisor_batallas.ex # DynamicSupervisor de batallas e intercambios
├── motor_combate.ex       # Cálculo de daño, tipos, STAB
├── persistencia.ex        # Lectura/escritura de archivos
└── cluster.ex             # Gestión de nodos distribuidos

data/
├── trainers.json          # Entrenadores, inventarios, equipos (persiste)
├── pokemon.json           # Catálogo de especies (editable sin código)
├── moves.json             # Pool de movimientos por tipo (editable)
├── tienda.json            # Tipos de sobre y precios
└── battles.log            # Registro de batallas
```

## Comandos disponibles

| Comando | Descripción |
|---------|-------------|
| `iniciar <user> <pass>` | Iniciar sesión / registrarse |
| `perfil` | Ver monedas y estadísticas |
| `inventario` | Ver todos los Pokémon con IDs |
| `clasificacion` | Ranking global |
| `tienda` | Ver sobres disponibles |
| `comprar_sobre <tipo>` | Comprar sobre (basico/avanzado) |
| `abrir_sobre <id\|ultimo>` | Abrir sobre |
| `crear_equipo <nombre> <ids>` | Crear equipo de batalla |
| `listar_equipos` | Ver equipos guardados |
| `usar_equipo <nombre>` | Cargar equipo para batalla |
| `crear_sala` | Crear sala de batalla |
| `unirse_sala <id>` | Unirse a sala |
| `iniciar_batalla <id>` | Iniciar batalla |
| `ataque <movimiento>` | Atacar en turno |
| `cambiar <id>` | Cambiar Pokémon activo |
| `rendirse` | Rendirse |
| `crear_sala_intercambio` | Crear sala de intercambio |
| `unirse_sala_intercambio <cod>` | Unirse a intercambio |
| `ofrecer_pokemon <id>` | Ofrecer Pokémon |
| `confirmar_intercambio` | Confirmar intercambio |
| `conectar_nodo <nodo@host>` | Conectar nodo distribuido |
