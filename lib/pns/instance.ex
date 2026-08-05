defmodule PNS.Instance do
  @moduledoc """
  Tożsamość **jednego przebiegu** procesu.

  `identity` odpowiada na pytanie „co czyni dwa wystąpienia **tym samym
  faktem**". `instance` odpowiada na inne: „co czyni dwa zdarzenia częścią
  **tego samego przebiegu**". Pierwsze siedzi na zdarzeniu, drugie na procesie,
  bo przebieg jest własnością procesu, a nie pojedynczego faktu.

  Powód jest techniczny, nie sprawozdawczy. Assercja `trace` mówi „po X
  ostatecznie Y"; bez tożsamości przebiegu Y znalezione dla innej firmy i innego
  miesiąca zalicza się jako spełnienie. Ta sama dziura jest w licznikach:
  krawędź przejechana 49 razy przez jedną firmę wygląda identycznie jak
  przejechana raz przez 49 — a różnica między nimi to cisza, po którą ten
  produkt istnieje.

  Klucz jest liczony z payloadu **po zastosowaniu `retain`**, więc jest
  odtwarzalny z samego logu. Nazwa procesu jest jego pierwszym segmentem: dwa
  procesy mogą mieć zbieżne wartości pól i bez prefiksu ich przebiegi
  zlewałyby się w jeden.
  """

  @separator "|"
  @escaped "%7C"

  @doc """
  Zwraca `{nazwa_procesu, instance_id}` dla zdarzenia, albo `{nil, nil}`, kiedy
  zdarzenie nie należy do żadnego procesu.
  """
  def key(contract, event_name, payload) do
    case contract.process_of(event_name) do
      nil -> {nil, nil}
      process -> {to_string(process.name), encode(process, event_name, payload)}
    end
  end

  defp encode(process, event_name, payload) do
    values =
      Enum.map(process.instance, fn field ->
        case fetch(payload, field) do
          {:ok, value} ->
            value |> to_string() |> String.replace(@separator, @escaped)

          :error ->
            # Brama kompilacyjna gwarantuje, że pole jest **zadeklarowane** w
            # payloadzie. Że zostało faktycznie podane, gwarantuje dopiero to
            # sprawdzenie — a bez niego zdarzenie wpadałoby do logu z pustym
            # segmentem klucza i cicho zlewało się z przebiegiem innej firmy.
            raise ArgumentError,
                  "zdarzenie #{inspect(event_name)} nie niesie pola instancji #{inspect(field)}, " <>
                    "a proces #{inspect(process.name)} deklaruje `instance: #{inspect(process.instance)}`. " <>
                    "Bez tego pola nie da się powiedzieć, do którego przebiegu należy to zdarzenie."
        end
      end)

    Enum.join([to_string(process.name) | values], @separator)
  end

  defp fetch(payload, field) do
    case Map.get(payload, field, Map.get(payload, to_string(field))) do
      nil -> :error
      value -> {:ok, value}
    end
  end
end
