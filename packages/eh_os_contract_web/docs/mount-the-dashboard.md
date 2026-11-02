# Mount the dashboard

This page tells you how to add the dashboard to the router of a Phoenix application. It is for a
developer of an application built on `eh_os_contract`. At the end, the dashboard shows the
conformance and the graphs of your contracts at a path that you choose.

## Before you start

- Your application uses `eh_os_contract`, from git, with `git:` and `sparse:`.
- Your router has a browser pipeline.
- You have a resolver: a module that says who can see the dashboard.
  [Decide who can see the dashboard](who-can-see-it.md) tells you how to write it.

## Steps

1. Add the package from git, beside the engine, with the same `git:` and `sparse:` form:

   ```elixir
   def deps do
     [
       {:eh_os_contract,
        git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
        sparse: "packages/eh_os_contract"},
       {:eh_os_contract_web,
        git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
        sparse: "packages/eh_os_contract_web"}
     ]
   end
   ```

   When you fetch the package on its own, it declares the engine in the same form. The two
   declarations then agree, and Mix does not report that they diverged. The package brings the
   graph renderer, `eh_os_contract_graph`, in the same form.

2. Mount the dashboard in a scope with your browser pipeline:

   ```elixir
   scope "/" do
     pipe_through :browser
     import EhOsContract.Web.Router

     eh_os_contract_dashboard "/dashboard", resolver: MyApp.EhOsContractResolver
   end
   ```

3. Serve the assets of the dashboard at your endpoint, before the router. Use exactly this `at:`,
   because the pages of the dashboard load their script and stylesheet from it:

   ```elixir
   plug Plug.Static,
     at: "/eh_os_contract_web/assets",
     from: {:eh_os_contract_web, "priv/static/assets"},
     gzip: false
   ```

   The macro does not serve them. A route behind `protect_from_forgery` refuses to serve
   JavaScript, so the assets need a route outside the router. The test host of this package has
   the same line, so its tests check this step.

**Result:** open `/dashboard`. It sends you to `/dashboard/contract`, the conformance screen, and
keeps the query string. The graph screen is `/dashboard/graph`.

## Options of the macro

| Option | Required | What it does |
| --- | --- | --- |
| `:resolver` | yes | A module that implements `EhOsContract.Web.Resolver`. The dashboard asks it who the caller is on each full page load, and what the caller can see on each mount. |
| `:on_mount` | no | Your own `on_mount` hooks. They run after the access check, so no hook gets a socket that the resolver refused. |

If you mount the dashboard in a scope with a path, such as `scope "/admin"`, the dashboard is at
`/admin/dashboard`. Its redirect, its links and the `base_path` of the resolver include the
prefix. The dashboard does not use the alias of a scope, such as `scope "/admin", MyAppWeb`. A
router can mount the dashboard more than one time. The mounts share the names of their route
helpers, so link to the second mount by its path.

## What does the dashboard look like?

The dashboard uses the EmpoweredHouse design system. It is dark by default, and light when the
system of the reader prefers light.

- **You cannot change its look yet.** The layout of the dashboard replaces the layout of your
  application on its routes, and loads only the stylesheet of this package. Your stylesheet and a
  `data-theme` attribute do not get to the page. The custom properties `--eh-os-contract-*` are
  the names that such a change would set.
- **It loads nothing from outside the application.** The fonts are beside the stylesheet, in
  `priv/static/assets/fonts/`, and step 3 serves them too. The dashboard loads no Google Fonts
  and uses no CDN, so it works without internet.
- **It works under a strict Content-Security-Policy**, `default-src 'self'`. No page has an
  inline style, and the graph renderer sets none. The development host of this repository
  serves the dashboard under this policy.

## What can go wrong

- **The page has no style, and the graphs are not drawn.** The endpoint does not serve the assets
  at `/eh_os_contract_web/assets`. Do step 3 again, with exactly that `at:`.
- **The script and the graphs stop working after an update.** The script of the dashboard reads
  the markup that the graph renderer renders. Update the two packages together:

  ```bash
  mix deps.update eh_os_contract_web eh_os_contract_graph
  ```

- **The compile fails on the router.** The macro needs `:resolver`.

## Next steps

- [Decide who can see the dashboard](who-can-see-it.md): write the resolver.
- [The JSON API](api.md): mount the same data as JSON.
- `EhOsContract.Web.Router`: the reference of the macros.
