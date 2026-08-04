defmodule PNS.Auth.Actor do
  @moduledoc "Kto wykonuje operację. Zrekonstruowany z tokenu, nigdy z bazy silnika."
  defstruct [:subject, :company_id, roles: []]
end

defmodule PNS.Auth.Verifier do
  @moduledoc """
  Szew tożsamości. **Jedyna reguła:** silnik dostaje token, sprawdza podpis i
  nie trzyma ani credentiali, ani zdolności do wystawiania tokenów.

  Ten behaviour jest całym zobowiązaniem architektonicznym i jest celowo
  milczący co do tego, co stoi po drugiej stronie. Dziś lokalny HMAC, bo
  stawianie Zitadela dla prototypu to koszt bez sygnału. Jutro `oidcc` przeciw
  kupionemu providerowi — i wtedy zmienia się jedna linia konfiguracji, nie kod
  domenowy.
  """

  @callback verify(token :: String.t()) :: {:ok, PNS.Auth.Actor.t()} | {:error, term()}
end

defmodule PNS.Auth.LocalToken do
  @moduledoc """
  Weryfikator dev-only: HMAC nad payloadem JSON.

  Czego tu celowo **nie** ma i nie będzie: tabeli z hasłami, rejestracji,
  resetu hasła, sesji. Gdyby się pojawiły, szew jest złamany i silnik ma drugie
  źródło prawdy o tym, kto pracuje w firmie.

  `sign/1` istnieje tylko po to, żeby dev i testy miały skąd wziąć token.
  Prawdziwy provider nie oddaje sekretu do podpisu, więc ta funkcja jest
  pierwszą rzeczą, która znika przy podmianie — i dlatego żaden moduł domenowy
  nie ma prawa jej wołać.
  """

  @behaviour PNS.Auth.Verifier

  alias PNS.Auth.Actor

  @impl true
  def verify(token) when is_binary(token) do
    with [body64, mac64] <- String.split(token, ".", parts: 2),
         {:ok, body} <- Base.url_decode64(body64, padding: false),
         {:ok, mac} <- Base.url_decode64(mac64, padding: false),
         true <- secure_compare(mac, mac(body)),
         {:ok, claims} <- Jason.decode(body) do
      {:ok,
       %Actor{
         subject: claims["sub"],
         company_id: claims["company_id"],
         # Role zostają stringami. `String.to_atom` na danych z tokenu byłoby
         # wektorem na wyczerpanie tablicy atomów — atomy nie są zwalniane.
         roles: claims["roles"] || []
       }}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :missing_token}

  @doc "Dev i testy. Znika przy podmianie na prawdziwego providera."
  def sign(claims) do
    body = Jason.encode!(claims)
    Base.url_encode64(body, padding: false) <> "." <> Base.url_encode64(mac(body), padding: false)
  end

  defp mac(body), do: :crypto.mac(:hmac, :sha256, secret(), body)

  # Porównanie w stałym czasie. `==` na binariach kończy się na pierwszym
  # różnym bajcie, co wycieka informację o tym, ile znaków się zgadza.
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.exor(left, right) |> :binary.bin_to_list() |> Enum.reduce(0, &Bitwise.bor(&1, &2)) == 0
  end

  defp secure_compare(_, _), do: false

  defp secret do
    Application.get_env(:pns_prototype, __MODULE__)[:secret] ||
      raise "brak sekretu dla #{inspect(__MODULE__)}"
  end
end

defmodule PNS.Auth do
  @moduledoc """
  Trzy poziomy, trzech różnych właścicieli (dokument o tożsamości, 4 sierpnia).

  | Poziom | Pytanie | Właściciel |
  |---|---|---|
  | Uwierzytelnienie | kto to jest | kupione — tu: `Verifier` |
  | Entitlement | czy ta osoba w ogóle dosięga tego API | kupione — grant roli jako claim |
  | Reguła domenowa | czy może wykonać **tę** operację na **tych** danych | nasze — reguła w kontrakcie |

  Drugi poziom przychodzi darmo z każdym providerem: nadaj rolę, przeczytaj
  jeden claim. Nie buduje się do tego silnika. Trzeci poziom jest tam, gdzie
  jest wartość, i dlatego siedzi w kontrakcie jako `rule` z przykładami — a nie
  w konfiguracji providera, która o naszej domenie nie wie nic.
  """

  @verifier Application.compile_env!(:pns_prototype, :auth_verifier)

  @doc "Poziom 1: kto to jest."
  def verify(token), do: verifier().verify(token)

  @doc """
  Poziom 2: entitlement. Jeden claim z tokenu, zero sieci, świeżość w
  granicach czasu życia tokenu.

  Dwie inne ścieżki propagacji, świadomie nieużyte: własna replika
  aktualizowana eventem przy zmianie grantu (właściwa dla reguł, spójna z
  kierunkiem event-driven) oraz pytanie do wspólnego serwisu autoryzacji przy
  każdym żądaniu — ta trzecia jest odrzucona, bo robi z kilku API rozproszony
  monolit, w którym jedna awaria kładzie wszystkie.
  """
  def entitled?(%PNS.Auth.Actor{roles: roles}, role), do: to_string(role) in roles

  defp verifier, do: @verifier
end
