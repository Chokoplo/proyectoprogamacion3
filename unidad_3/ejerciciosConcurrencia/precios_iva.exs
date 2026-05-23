defmodule Producto do
  defstruct nombre: "", stock: 0, precio_sin_iva: 0.0, iva: 0.0
end

defmodule Precios do
  # Cálculo del precio final con IVA
  def precio_final(%Producto{precio_sin_iva: sin, iva: iva}) do
    sin * (1 + iva)
  end

  # Procesamiento secuencial
  def calcular_secuencial(productos) do
    Enum.map(productos, fn p ->
      {p.nombre, p.precio_sin_iva, Float.round(precio_final(p), 2)}
    end)
  end

  # Procesamiento concurrente
  def calcular_concurrente(productos) do
    productos
    |> Task.async_stream(fn p ->
      {p.nombre, p.precio_sin_iva, Float.round(precio_final(p), 2)}
    end, max_concurrency: System.schedulers_online())
    |> Enum.to_list()
  end
end

defmodule TestPrecios do
  def generar_productos(n \\ 10) do
    for i <- 1..n do
      %Producto{
        nombre: "Producto #{i}",
        stock: Enum.random(1..100),
        precio_sin_iva: Enum.random(100..1000) * 1.0,
        iva: 0.19
      }
    end
  end

  def ejecutar_comparacion do
    productos = generar_productos(10)


    tiempo_secuencial = Benchmark.determinar_tiempo_ejecucion({Precios, :calcular_secuencial, [productos]})
    tiempo_concurrente = Benchmark.determinar_tiempo_ejecucion({Precios, :calcular_concurrente, [productos]})

    IO.puts("\n Precio final por producto:")
    IO.puts(String.pad_trailing("Nombre", 15) <>
            String.pad_trailing("Precio sin IVA", 20) <>
            "Precio final")
    IO.puts(String.duplicate("-", 50))

    Precios.calcular_secuencial(productos)
    |> Enum.each(fn {nombre, sin_iva, final} ->
      IO.puts(
        String.pad_trailing(nombre, 15) <>
        String.pad_trailing("$#{Float.round(sin_iva, 2)}", 20) <>
        "$#{Float.round(final, 2)}"
      )
    end)

    IO.puts("\n RESULTADOS DE RENDIMIENTO")
    IO.puts("Tiempo secuencial: #{tiempo_secuencial} microsegundos")
    IO.puts("Tiempo concurrente: #{tiempo_concurrente} microsegundos")

    speedup = Benchmark.calcular_speedup(tiempo_concurrente, tiempo_secuencial) |> Float.round(2)
    IO.puts("Speedup: #{speedup}x")
  end
end


TestPrecios.ejecutar_comparacion()
