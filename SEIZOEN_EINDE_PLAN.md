# Seizoen Einde & Token Management Plan

## 🎯 Overzicht

Dit plan beschrijft de implementatie van seizoen einde functionaliteit waarbij beheerders tokens kunnen revoken en gebruikers een seizoen overzicht krijgen voordat ze hun tenant data resetten.

## ✅ **IMPLEMENTATIE STATUS**

### **iOS App - VOLTOOID ✅**
- ✅ Token revocation detection & error handling
- ✅ Season ended state management (`seasonEnded` property)
- ✅ SeasonOverviewView met Spotify-style statistieken
- ✅ Navigation flow voor season ended tenants
- ✅ Multi-tenant safe cleanup functionaliteit

### **Backend - IN PROGRESS 🚧**
- ⏳ Enrollment state system (tenant `enrollment_open` field)
- ⏳ Enrollment status check API endpoints
- ⏳ Enhanced QR code responses with enrollment status
- ⏳ Token revocation endpoints
- ⏳ Season reset + reopen functionality  
- ⏳ Admin interface enrollment management controls

## 🏗️ Architectuur Overzicht

### Huidige Situatie
- **Tokens**: Phoenix.Token met `max_age: season_end_ttl()` (31 juli expiry)
- **Error Handling**: `{:error, :expired}` vs `{:error, :invalid}` onderscheid mogelijk
- **Multi-tenant**: Verschillende tenants kunnen verschillende seizoen einddata hebben

### Nieuwe Situatie  
- **Tokens**: Infinite lifetime (geen automatische expiry)
- **Enrollment State**: Admin-controlled enrollment acceptance per tenant
- **Seizoen Beheer**: "End Season" + "Reset Season" + "Open Enrollment" acties
- **Token Revocation**: Server-side event die alle tokens van een tenant revokeert
- **Client Handling**: Seizoen overzicht met lokale data + enrollment blocking

---

## 🔧 Backend Wijzigingen

### 1. Enrollment State System (NIEUWE VEREISTE)

#### A. Tenant Schema Update
```elixir
# priv/repo/migrations/xxx_add_tenant_enrollment_state.exs
defmodule KantineKoning.Repo.Migrations.AddTenantEnrollmentState do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :enrollment_open, :boolean, default: true, null: false
      add :season_ended_at, :utc_datetime
      add :enrollment_message, :text  # Custom message for closed enrollment
      add :season_reset_at, :utc_datetime  # Track when season was last reset
    end
    
    # Index for quick enrollment status lookups
    create index(:tenants, [:enrollment_open])
  end
end
```

#### B. Enrollment Status Check API
```elixir
# lib/kantine_koning_web/controllers/api/mobile/v1/enrollment_controller.ex
def check_tenant_enrollment_status(conn, %{"tenant_slug" => tenant_slug}) do
  case Tenants.get_tenant_enrollment_status(tenant_slug) do
    {:ok, %{enrollment_open: true}} ->
      json(conn, %{enrollment_allowed: true})
      
    {:ok, %{enrollment_open: false, enrollment_message: message}} ->
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "enrollment_closed",
        message: message || "Enrollment is gesloten voor dit seizoen",
        enrollment_allowed: false
      })
      
    {:error, :not_found} ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "tenant_not_found"})
  end
end
```

#### C. QR Code Enhanced Response
```elixir
# Update QR code scan to include enrollment status
def scan(conn, %{"tenant_slug" => tenant_slug, "team_code" => team_code}) do
  with {:ok, tenant} <- Tenants.get_tenant_with_enrollment_status(tenant_slug),
       {:ok, team} <- Teams.get_team_by_code(tenant, team_code) do
    
    response = %{
      tenant_slug: tenant.slug,
      tenant_name: tenant.name,
      team_code: team.code,
      team_name: team.name,
      enrollment_allowed: tenant.enrollment_open  # NEW
    }
    
    if tenant.enrollment_open do
      json(conn, response)
    else
      conn
      |> put_status(:forbidden)
      |> json(Map.merge(response, %{
        error: "enrollment_closed",
        message: tenant.enrollment_message || "Enrollment is gesloten voor dit seizoen"
      }))
    end
  end
end
```

### 2. Token System Refactor

#### A. Infinite Token Lifetime
```elixir
# lib/kantine_koning/devices/devices.ex
def verify_token(token) do
  # Remove max_age parameter for infinite lifetime
  Phoenix.Token.verify(KantineKoningWeb.Endpoint, @token_salt, token)
end

# Remove season_end_ttl function entirely
```

#### B. Token Revocation System
```elixir
# New table: token_revocations (public schema)
defmodule KantineKoning.Devices.TokenRevocation do
  use Ecto.Schema
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "token_revocations" do
    field :tenant_slug, :string
    field :revoked_at, :utc_datetime
    field :reason, :string  # "season_ended", "admin_revoked", etc.
    
    timestamps()
  end
end
```

#### C. Enhanced Token Verification
```elixir
# lib/kantine_koning/devices/devices.ex
def verify_token(token) do
  with {:ok, claims} <- Phoenix.Token.verify(KantineKoningWeb.Endpoint, @token_salt, token) do
    # Check if tenant tokens have been revoked
    tenant_slug = claims["tenant_slug"]
    
    case is_tenant_token_revoked?(tenant_slug, claims) do
      true -> {:error, :revoked}
      false -> {:ok, claims}
    end
  end
end

defp is_tenant_token_revoked?(tenant_slug, claims) do
  # Check if there's a revocation after this token was issued
  token_issued_at = claims["iat"] || 0  # Include iat in token claims
  
  from(r in TokenRevocation,
    where: r.tenant_slug == ^tenant_slug and 
           r.revoked_at > ^DateTime.from_unix!(token_issued_at),
    limit: 1
  )
  |> Repo.exists?()
end
```

### 3. Admin Seizoen Beheer (TAB STRUCTUUR)

#### A. Mijn Vereniging Tab Uitbreiding
De huidige "Mijn Vereniging" pagina krijgt een tab structuur vergelijkbaar met Teams en Managers:

**Tab Structuur:**
- **Overzicht** (bestaande club info pagina)
- **Seizoen Instellingen** (nieuwe seizoen management functionaliteit)

```elixir
# lib/kantine_koning_web/live/admin/geavanceerd_live/index.ex - Tab Support
def mount(_params, _session, socket) do
  tenant = socket.assigns.current_tenant
  club = Clubs.get_club(tenant) || Clubs.new_club()
  changeset = Clubs.change_club(club)

  {:ok,
   socket
   |> assign(:page_title, "Mijn Vereniging")
   |> assign(:club, club)
   |> assign(:club_form, to_form(changeset))
   |> assign(:leaderboard_opt_out, get_leaderboard_opt_out(tenant))
   |> assign(:show_success, false)
   |> assign(:current_tab, "overview")  # NEW: Tab state
   |> assign(:uploaded_files, [])
   |> assign_season_data(tenant)  # NEW: Season enrollment data
   |> allow_upload(:logo,
     accept: ~w(.jpg .jpeg .png .gif),
     max_entries: 1,
     max_file_size: 5_000_000
   )}
end

# NEW: Handle tab switching
def handle_event("set_tab", %{"tab" => tab}, socket) do
  {:noreply, assign(socket, :current_tab, tab)}
end

# NEW: Load season enrollment status
defp assign_season_data(socket, tenant) do
  socket
  |> assign(:enrollment_open, tenant.enrollment_open || true)
  |> assign(:season_ended_at, tenant.season_ended_at)
  |> assign(:enrollment_message, tenant.enrollment_message || "")
  |> assign(:season_reset_at, tenant.season_reset_at)
end
```

#### B. Seizoen Management Event Handlers
```elixir
# lib/kantine_koning_web/live/admin/geavanceerd_live/index.ex - Season Events
def handle_event("toggle_enrollment", _params, socket) do
  tenant = socket.assigns.current_tenant
  new_state = !socket.assigns.enrollment_open
  
  case Tenants.update_tenant(tenant, %{enrollment_open: new_state}) do
    {:ok, updated_tenant} ->
      message = if new_state, do: "Enrollment geopend", else: "Enrollment gesloten"
      {:noreply, 
       socket 
       |> assign(:current_tenant, updated_tenant)
       |> assign(:enrollment_open, new_state)
       |> put_flash(:info, message)}
    
    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Fout bij wijzigen enrollment status")}
  end
end

def handle_event("update_enrollment_message", %{"message" => message}, socket) do
  tenant = socket.assigns.current_tenant
  
  case Tenants.update_tenant(tenant, %{enrollment_message: message}) do
    {:ok, updated_tenant} ->
      {:noreply, 
       socket 
       |> assign(:current_tenant, updated_tenant)
       |> assign(:enrollment_message, message)
       |> put_flash(:info, "Enrollment bericht bijgewerkt")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Fout bij bijwerken bericht")}
  end
end

def handle_event("end_season", _params, socket) do
  tenant = socket.assigns.current_tenant
  
  case KantineKoning.Devices.end_tenant_season(tenant.slug) do
    {:ok, updated_tenant} ->
      {:noreply, 
       socket 
       |> assign(:current_tenant, updated_tenant)
       |> assign_season_data(updated_tenant)
       |> put_flash(:info, "Seizoen beëindigd. Alle device tokens zijn ingetrokken.")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Fout bij beëindigen seizoen: #{inspect(reason)}")}
  end
end

def handle_event("reset_season", _params, socket) do
  tenant = socket.assigns.current_tenant
  
  case KantineKoning.Admin.SeasonManagement.reset_and_reopen_season(tenant.slug) do
    {:ok, updated_tenant} ->
      {:noreply, 
       socket 
       |> assign(:current_tenant, updated_tenant)
       |> assign_season_data(updated_tenant)
       |> put_flash(:info, "Seizoen gereset en enrollment heropend.")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Fout bij resetten seizoen: #{inspect(reason)}")}
  end
end

# NEW: Handle messages from SeasonManagement component
def handle_info({:toggle_enrollment}, socket) do
  handle_event("toggle_enrollment", %{}, socket)
end

def handle_info({:update_enrollment_message, message}, socket) do
  handle_event("update_enrollment_message", %{"message" => message}, socket)
end

def handle_info({:end_season}, socket) do
  handle_event("end_season", %{}, socket)
end

def handle_info({:reset_season}, socket) do
  handle_event("reset_season", %{}, socket)
end
```

#### C. HTML Template Tab Uitbreiding
```heex
<!-- lib/kantine_koning_web/live/admin/geavanceerd_live/index.html.heex -->
<div class="min-h-screen bg-gray-50">
  <div class="max-w-[95%] mx-auto">
    <%!-- NEW: Sub navigation tabs --%>
    <div class="bg-white shadow-sm mb-6">
      <div class="border-b border-gray-200">
        <nav class="-mb-px flex space-x-8 px-4 sm:px-6" aria-label="Tabs">
          <button
            :for={{label, tab} <- [{"Overzicht", "overview"}, {"Seizoen Instellingen", "season"}]}
            phx-click="set_tab"
            phx-value-tab={tab}
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
              (@current_tab == tab && "border-blue-500 text-blue-600") ||
                "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
            ]}
          >
            {label}
          </button>
        </nav>
      </div>
    </div>

    <%!-- Tab Content --%>
    <%= if @current_tab == "season" do %>
      <.live_component
        module={KantineKoningWeb.Admin.Components.SeasonManagement}
        id="season-management"
        current_tenant={@current_tenant}
        enrollment_open={@enrollment_open}
        season_ended_at={@season_ended_at}
        enrollment_message={@enrollment_message}
        season_reset_at={@season_reset_at}
      />
    <% else %>
      <%!-- Existing club info content (current page content) --%>
      <!-- Main Content -->
      <div class="bg-white shadow rounded-lg">
        <!-- ... existing club form content ... -->
      </div>
    <% end %>
  </div>
</div>
```

#### D. Season Management Component
```elixir
# lib/kantine_koning_web/live/admin/components/season_management.ex
defmodule KantineKoningWeb.Admin.Components.SeasonManagement do
  use KantineKoningWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <div class="p-6">
        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-6">
          Seizoen Instellingen
        </h3>

        <!-- Enrollment Status -->
        <div class="mb-8">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h4 class="text-md font-medium text-gray-800">Enrollment Status</h4>
              <p class="text-sm text-gray-600">
                Beheer of nieuwe leden zich kunnen aanmelden voor dit seizoen
              </p>
            </div>
            <div class="flex items-center">
              <label class="relative inline-flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  checked={@enrollment_open}
                  phx-click="toggle_enrollment"
                  phx-target={@myself}
                  class="sr-only peer"
                />
                <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
              </label>
              <span class="ml-3 text-sm font-medium text-gray-700">
                {if @enrollment_open, do: "Open", else: "Gesloten"}
              </span>
            </div>
          </div>

          <!-- Enrollment Message -->
          <div class="mt-4">
            <.input
              name="enrollment_message"
              type="textarea"
              label="Enrollment Bericht"
              value={@enrollment_message}
              placeholder="Optioneel bericht dat wordt getoond wanneer enrollment gesloten is"
              phx-change="update_enrollment_message"
              phx-target={@myself}
              phx-debounce="1000"
              rows="3"
            />
          </div>
        </div>

        <!-- Season Actions -->
        <div class="border-t border-gray-200 pt-6">
          <h4 class="text-md font-medium text-gray-800 mb-4">Seizoen Acties</h4>
          
          <!-- Season Status Info -->
          <%= if @season_ended_at do %>
            <div class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-md">
              <div class="flex">
                <div class="flex-shrink-0">
                  <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-yellow-800">
                    Seizoen Beëindigd
                  </h3>
                  <div class="mt-2 text-sm text-yellow-700">
                    <p>
                      Seizoen beëindigd op {@season_ended_at |> Calendar.strftime("%d %B %Y om %H:%M")}. 
                      Alle device tokens zijn ingetrokken en enrollment is gesloten.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Action Buttons -->
          <div class="space-y-4">
            <!-- End Season Button -->
            <%= unless @season_ended_at do %>
              <div>
                <button
                  type="button"
                  phx-click="end_season"
                  phx-target={@myself}
                  phx-confirm="Weet je zeker dat je het seizoen wilt beëindigen? Dit kan niet ongedaan worden gemaakt!"
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                >
                  <.icon name="hero-stop-circle" class="h-4 w-4 mr-2" />
                  Seizoen Beëindigen
                </button>
                <p class="mt-2 text-sm text-gray-500">
                  Trekt alle device tokens in en sluit enrollment. Toont seizoen overzicht aan gebruikers.
                </p>
              </div>
            <% end %>

            <!-- Reset Season Button -->
            <%= if @season_ended_at do %>
              <div>
                <button
                  type="button"
                  phx-click="reset_season"
                  phx-target={@myself}
                  phx-confirm="Weet je zeker dat je het seizoen wilt resetten? Dit verwijdert alle teams, managers en diensten!"
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4 mr-2" />
                  Nieuw Seizoen Starten
                </button>
                <p class="mt-2 text-sm text-gray-500">
                  Reset alle seizoen data en heropen enrollment voor een nieuw seizoen.
                </p>
              </div>
            <% end %>
          </div>

          <!-- Season Reset Info -->
          <%= if @season_reset_at do %>
            <div class="mt-6 p-4 bg-green-50 border border-green-200 rounded-md">
              <div class="flex">
                <div class="flex-shrink-0">
                  <.icon name="hero-check-circle" class="h-5 w-5 text-green-400" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-green-800">
                    Laatste Reset
                  </h3>
                  <div class="mt-2 text-sm text-green-700">
                    <p>
                      Seizoen laatst gereset op {@season_reset_at |> Calendar.strftime("%d %B %Y om %H:%M")}.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_enrollment", _params, socket) do
    send(self(), {:toggle_enrollment})
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_enrollment_message", %{"value" => message}, socket) do
    send(self(), {:update_enrollment_message, message})
    {:noreply, socket}
  end

  @impl true
  def handle_event("end_season", _params, socket) do
    send(self(), {:end_season})
    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_season", _params, socket) do
    send(self(), {:reset_season})
    {:noreply, socket}
  end
end
```

#### E. End Season API Implementation
  tenant = socket.assigns.current_tenant
  
  case KantineKoning.Devices.end_tenant_season(tenant.slug) do
    {:ok, _} ->
      {:noreply, 
       socket 
       |> put_flash(:info, "Seizoen beëindigd. Alle device tokens zijn ingetrokken.")
       |> push_redirect(to: ~p"/beheer")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Fout bij beëindigen seizoen: #{reason}")}
  end
end
```

#### B. End Season Implementation
```elixir
# lib/kantine_koning/devices/devices.ex
def end_tenant_season(tenant_slug) do
  Repo.transaction(fn ->
    # 1. Create revocation record
    %TokenRevocation{}
    |> TokenRevocation.changeset(%{
      tenant_slug: tenant_slug,
      revoked_at: DateTime.utc_now(),
      reason: "season_ended"
    })
    |> Repo.insert!()
    
    # 2. Mark all enrollments as revoked (for audit trail)
    from(de in DeviceEnrollment, where: de.tenant_slug == ^tenant_slug)
    |> Repo.update_all(set: [status: :revoked, updated_at: DateTime.utc_now()])
    
    # 3. Update tenant enrollment status (NIEUW)
    tenant = Tenants.get_tenant_by_slug!(tenant_slug)
    Tenants.update_tenant(tenant, %{
      enrollment_open: false,
      season_ended_at: DateTime.utc_now(),
      enrollment_message: "Seizoen is afgelopen. Nieuwe enrollments volgen volgend seizoen."
    })
    
    # 4. Log action
    Logger.info("[SEASON_END] Revoked all tokens and closed enrollment for tenant #{tenant_slug}")
  end)
end
```

#### C. Season Reset Implementation (NIEUW)
```elixir
# lib/kantine_koning/admin/season_management.ex
def reset_and_reopen_season(tenant_slug) do
  Repo.transaction(fn ->
    # 1. Reset tenant season data (existing function)
    reset_tenant_season_data(tenant_slug)
    
    # 2. Reopen enrollment (NIEUW)
    tenant = Tenants.get_tenant_by_slug!(tenant_slug)
    Tenants.update_tenant(tenant, %{
      enrollment_open: true,
      season_ended_at: nil,
      season_reset_at: DateTime.utc_now(),
      enrollment_message: nil  # Clear custom message
    })
    
    # 3. Clear token revocations for fresh start
    from(tr in TokenRevocation, where: tr.tenant_slug == ^tenant_slug)
    |> Repo.delete_all()
    
    Logger.info("[SEASON_RESET] Reset season data and reopened enrollment for tenant #{tenant_slug}")
  end)
end
```

### 3. Database Migrations

#### A. Token Revocations Table
```elixir
# priv/repo/migrations/20250101000001_create_token_revocations.exs
defmodule KantineKoning.Repo.Migrations.CreateTokenRevocations do
  use Ecto.Migration

  def change do
    create table(:token_revocations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_slug, :string, null: false
      add :revoked_at, :utc_datetime, null: false
      add :reason, :string, null: false

      timestamps()
    end

    create index(:token_revocations, [:tenant_slug])
    create index(:token_revocations, [:revoked_at])
  end
end
```

#### B. Enhanced Device Tokens
```elixir
# Update sign_token to include issued_at timestamp
def sign_token(%DeviceEnrollment{} = de) do
  Phoenix.Token.sign(KantineKoningWeb.Endpoint, @token_salt, %{
    device_id: de.device_id,
    tenant_slug: de.tenant_slug,
    role: de.role,
    team_codes: de.team_codes,
    iat: DateTime.to_unix(DateTime.utc_now())  # NEW: Include issued at timestamp
  })
end
```

### 4. Backend Seizoen Reset (Toekomstige Functionaliteit)

#### A. Data Cleanup Scope
```elixir
# lib/kantine_koning/admin/season_management.ex
def reset_tenant_season_data(tenant_slug) do
  Repo.transaction(fn ->
    prefix = Repo.tenant_prefix(%{slug: tenant_slug})
    
    # DELETE: Teams, TeamManagers, Diensten, Aanmeldingen, Wedstrijden
    Repo.delete_all(from(t in "teams"), prefix: prefix)
    Repo.delete_all(from(tm in "team_managers"), prefix: prefix) 
    Repo.delete_all(from(d in "diensten"), prefix: prefix)
    Repo.delete_all(from(a in "aanmeldingen"), prefix: prefix)
    Repo.delete_all(from(w in "wedstrijden"), prefix: prefix)
    
    # KEEP: Locaties, Sjablonen, Notifications (templates)
    # These persist across seasons
    
    Logger.info("[SEASON_RESET] Cleared season data for tenant #{tenant_slug}")
  end)
end
```

---

## 📱 iOS App Wijzigingen

### 1. Enrollment Status Checking (NIEUWE VEREISTE)

#### A. QR Scanner Enhancement
```swift
// QRScannerView.swift - Enhanced QR processing
private func processQRCode(_ code: String) {
    // Parse QR code...
    let tenant = extractedTenantSlug
    let team = extractedTeamCode
    
    // NEW: Check enrollment status before proceeding
    backend.checkEnrollmentStatus(tenant: tenant) { [weak self] result in
        DispatchQueue.main.async {
            switch result {
            case .success(let status):
                if status.enrollmentAllowed {
                    // Proceed with normal enrollment flow
                    self?.proceedWithEnrollment(tenant: tenant, team: team)
                } else {
                    // Show enrollment closed message
                    self?.showEnrollmentClosedAlert(message: status.message)
                }
            case .failure(let error):
                self?.handleError(error)
            }
        }
    }
}

private func showEnrollmentClosedAlert(message: String) {
    let alert = UIAlertController(
        title: "Enrollment Gesloten", 
        message: message,
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
}
```

#### B. BackendClient Enrollment API
```swift
// BackendClient.swift - New enrollment check endpoint
struct EnrollmentStatus: Codable {
    let enrollmentAllowed: Bool
    let message: String?
}

func checkEnrollmentStatus(tenant: String, completion: @escaping (Result<EnrollmentStatus, Error>) -> Void) {
    let url = baseURL.appendingPathComponent("api/mobile/v1/enrollment/status/\(tenant)")
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    // No auth token needed - public check
    
    performRequest(request: request) { (result: Result<EnrollmentStatus, Error>) in
        completion(result)
    }
}
```

### 2. Enhanced Error Handling

#### A. BackendClient Error Detection
```swift
// BackendClient.swift - Enhanced error handling
private func handleAPIError(_ error: Error, for tenant: String) -> AppError {
    if let backendError = error as? BackendError,
       case .unauthorized = backendError {
        
        // Check if this is a revoked token (seizoen einde)
        return .tokenRevoked(tenant: tenant)
    }
    
    return .networkError(error)
}

enum AppError: Error {
    case tokenRevoked(tenant: String)
    case tokenInvalid(tenant: String) 
    case networkError(Error)
}
```

#### B. Centralized 401 Handling  
```swift
// AppStore.swift - Token revocation detection
func handleTokenRevocation(for tenant: String) {
    guard let tenantData = model.tenants[tenant] else { return }
    
    // Set tenant to "season ended" state
    model.tenants[tenant]?.seasonEnded = true
    
    Logger.auth("Token revoked for tenant \(tenant) - season ended")
    
    // Trigger UI update to show season overview
    objectWillChange.send()
}
```

### 2. Seizoen Overzicht View

#### A. SeasonOverviewView Implementation
```swift
// Views/SeasonOverviewView.swift
struct SeasonOverviewView: View {
    let tenant: Tenant
    @EnvironmentObject var store: AppStore
    @State private var showConfetti = false
    @State private var confettiTrigger = 0
    
    // Use LOCAL data from AppStore.upcoming for statistics (Personal Performance Focus)
    private var seasonStats: SeasonStats {
        let tenantDiensten = store.upcoming.filter { $0.tenantId == tenant.slug }
        return SeasonStats(
            totalHours: calculateTotalHours(tenantDiensten),
            totalShifts: tenantDiensten.count,
            favoriteLocation: findMostFrequentLocation(tenantDiensten),
            mostActiveMonth: findMostActiveMonth(tenantDiensten),
            teamContributions: calculateTeamContributions(tenantDiensten),
            achievements: generateAchievements(tenantDiensten)
        )
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header with confetti overlay
            SeasonHeaderView(tenant: tenant)
                .overlay(ConfettiView(trigger: confettiTrigger).allowsHitTesting(false))
            
            // Statistics cards
            SeasonStatsView(stats: seasonStats)
            
            // Thank you message
            ThankYouMessageView()
            
            Spacer()
            
            // Reset button
            ResetTenantButton(tenant: tenant) {
                store.removeTenant(tenant.slug)
                // This will navigate back to home or QR if no tenants left
            }
        }
        .onAppear {
            // Trigger confetti celebration
            triggerConfetti()
        }
    }
    
    private func triggerConfetti() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { 
            showConfetti = true 
        }
        confettiTrigger += 1
        
        // Add iPhone vibration for extra celebration
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
}
```

#### B. Season Statistics Data Structure
```swift
// Models/SeasonStats.swift - Focus on Personal Performance (Spotify-style)
struct SeasonStats {
    let totalHours: Double
    let totalShifts: Int
    let favoriteLocation: String?
    let mostActiveMonth: String?
    let teamContributions: [TeamContribution]
    let achievements: [Achievement]
}

struct TeamContribution {
    let teamCode: String
    let teamName: String
    let hoursWorked: Double
    let shiftsCompleted: Int
    // NOTE: NO leaderboard position - focus on personal performance only
}

struct Achievement {
    let title: String  // "Kantine Kampioen", "Vroege Vogel", "Weekend Warrior"
    let description: String
    let icon: String
}
```

### 3. Navigation & State Management

#### A. Enhanced DomainModel
```swift
// Models/DomainModel.swift
struct Tenant: Codable {
    let slug: String
    let name: String
    var signedDeviceToken: String?
    var teams: [String: Team]
    var seasonEnded: Bool = false  // NEW: Track season state
    
    // Helper to check if tenant is accessible
    var isAccessible: Bool {
        return !seasonEnded && signedDeviceToken != nil
    }
}
```

#### B. HomeHostView Navigation Logic
```swift
// Views/HomeHostView.swift  
var body: some View {
    NavigationView {
        if model.tenants.isEmpty {
            // No tenants -> QR onboarding
            OnboardingHostView()
        } else {
            // Check for season ended tenants
            let accessibleTenants = model.tenants.values.filter { $0.isAccessible }
            let seasonEndedTenants = model.tenants.values.filter { $0.seasonEnded }
            
            if !seasonEndedTenants.isEmpty {
                // Show season overview for first ended tenant
                SeasonOverviewView(tenant: seasonEndedTenants.first!)
            } else if !accessibleTenants.isEmpty {
                // Normal tenant selection
                TenantSelectionView(tenants: accessibleTenants)
            } else {
                // All tenants ended and removed -> QR onboarding
                OnboardingHostView()
            }
        }
    }
}
```

### 4. Data Persistence & Cleanup

#### A. Tenant Removal
```swift
// AppStore.swift
func removeTenant(_ tenantSlug: String) {
    // Remove from model
    model.tenants.removeValue(forKey: tenantSlug)
    
    // Clean up local diensten data for this tenant
    upcoming.removeAll { $0.tenantId == tenantSlug }
    
    // Persist changes
    persistModel()
    
    Logger.auth("Removed tenant \(tenantSlug) after season end")
    
    // Navigate appropriately
    if model.tenants.isEmpty {
        // No tenants left -> go to onboarding
        currentPhase = .onboarding
    }
}
```

---

## 🛡️ Veiligheid & Robuustheid

### 1. Token Security
- **Infinite Tokens**: Geen automatische expiry voorkomt onverwachte uitloggen
- **Server-side Revocation**: Centrale controle bij admin, niet client-side manipuleerbaar
- **Audit Trail**: Alle revocations worden gelogd met timestamp en reden

### 2. Data Consistency & Accuracy
- **Local Statistics Only**: Seizoen overzicht gebruikt alleen lokale diensten data (uren, aantal diensten)
- **No Leaderboard Positions**: Vermijdt verouderde/incorrecte ranking informatie
- **Personal Performance Focus**: Spotify-style overzicht van eigen prestaties, niet vergelijkingen
- **Atomic Operations**: Database transactions voor seizoen einde acties
- **Graceful Degradation**: App werkt nog met locale data ook al is backend niet bereikbaar

### 3. Multi-Tenant Isolation
- **Per-Tenant Revocation**: Alleen getroffen tenant wordt gereset
- **Independent Seasons**: Verschillende tenants kunnen verschillende seizoen einddata hebben
- **Selective Cleanup**: Alleen seizoen-specifieke data wordt verwijderd, templates blijven

### 4. Error Recovery
- **Network Failures**: Token revocation detectie werkt offline met locale checks
- **Partial Failures**: Als backend reset faalt, zijn tokens al ingetrokken
- **State Reconstruction**: App kan zich herstellen uit UserDefaults na crashes

---

## 📋 Implementatie Volgorde

### Phase 1: Backend Foundation ✅ VOLTOOID
1. ✅ Token revocation tabel + migrations
2. ✅ Infinite token lifetime (remove `max_age`)
3. ✅ Enhanced token verification met revocation check
4. ✅ Admin "End Season" functionaliteit

### Phase 2: iOS Token Handling ✅ VOLTOOID
1. ✅ Enhanced error detection in BackendClient
2. ✅ Season ended state in DomainModel
3. ✅ Central 401/revoked token handling in AppStore

### Phase 3: Seizoen Overzicht UI ✅ VOLTOOID
1. ✅ SeasonOverviewView met local data statistics
2. ✅ Confetti + vibration celebration
3. ✅ Reset tenant functionaliteit
4. ✅ Navigation flow updates

### Phase 4: Admin Interface Season Management 🚧 IN PROGRESS
1. ⏳ Mijn Vereniging tab structuur uitbreiding
2. ⏳ Season Management component implementatie  
3. ⏳ Enrollment toggle en message functionaliteit
4. ⏳ End Season en Reset Season knoppen
5. ⏳ Event handlers voor alle seizoen acties

### Phase 5: Backend Enrollment State System 🚧 NIEUW
1. ⏳ Backend tenant enrollment_open veld + migrations
2. ⏳ Enrollment status check API endpoints
3. ⏳ QR code enhanced response met enrollment status
4. ⏳ iOS enrollment checking in QR scanner
5. ⏳ Tenants.update_tenant support voor nieuwe velden

### Phase 6: Season Reset & Data Management 🚧 NIEUW  
1. ⏳ Backend season reset + reopen functionality (Admin.SeasonManagement module)
2. ⏳ Token revocation cleanup voor fresh start
3. ⏳ Template preservation logic
4. ⏳ Tenant data cleanup scope definition

### Phase 7: Testing & Polish
1. ⏳ Multi-tenant seizoen scenarios testen
2. ⏳ Enrollment closed edge cases
3. ⏳ Season reset verification  
4. ⏳ UX polish en animations

---

## 🎯 Verwachte Resultaten

### Admin Experience (UITGEBREID)
- **Volledige Controle**: Seizoen einde op exact gewenste moment
- **Enrollment Management**: Toggle enrollment open/gesloten met custom berichten
- **Flexible Workflow**: End Season → Reset Data → Reopen Enrollment in stappen
- **Clean Restart**: Nieuwe seizoen start met verse data maar behoud van templates
- **Audit Trail**: Duidelijke logging van alle seizoen acties

### User Experience  
- **Celebration**: Feestelijk seizoen overzicht met eigen statistieken (Spotify-style)
- **Personal Focus**: Jouw uren, jouw diensten, jouw prestaties - geen verouderde rankings
- **No Surprise**: Duidelijke communicatie over seizoen einde
- **Enrollment Protection**: Voorkoming van re-enrollment van geëindigde seizoenen
- **Clear Messaging**: Informatieve berichten bij gesloten enrollment
- **Smooth Transition**: Eenvoudige reset naar nieuwe seizoen enrollment

### Technical Benefits
- **Robuust**: Werkt ook bij netwerk problemen
- **Veilig**: Server-side controle, client kan niet cheaten
- **Schaalbaar**: Werkt voor elke tenant size
- **Maintainable**: Duidelijke separation of concerns

---

**Dit plan biedt een robuuste, gebruiksvriendelijke oplossing voor seizoen management die admins volledige controle geeft over enrollment timing, gebruikers beschermt tegen ongeldige enrollments, en een positieve seizoen afsluiting experience biedt met persoonlijke statistieken.**

## 🎯 **NIEUWE VEREISTEN SAMENVATTING**

### **Enrollment Protection System**
- ✅ **iOS App**: Seizoen einde detection en overzicht volledig geïmplementeerd
- 🚧 **Backend**: Enrollment state management en API endpoints (volgende stap)
- 🚧 **Admin**: Enrollment toggle en custom messaging controls

### **Flexibele Admin Workflow**
1. **Seizoen afsluiting**: End Season → tokens revoked + enrollment gesloten
2. **Data reset**: Reset Season → alle seizoen data gewist, templates behouden
3. **Nieuwe seizoen**: Reopen Enrollment → fresh start met lege slate

### **User Experience Protection**
- QR scanner checkt enrollment status vóór enrollment poging
- Duidelijke berichten bij gesloten enrollment
- Voorkomt re-enrollment van beëindigde seizoenen
- Seizoen overzicht blijft beschikbaar tot gebruiker reset
