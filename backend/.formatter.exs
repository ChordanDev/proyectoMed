[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,test,e2e_support}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
