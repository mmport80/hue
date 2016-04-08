defmodule Hue2.Mixfile do
  use Mix.Project

  def project do
    [app: :hue2,
     version: "0.0.1",
     elixir: "~> 1.0",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps,
     dialyzer: [
      flags: ["-Wunmatched_returns","-Werror_handling","-Wrace_conditions","-Wunderspecs","-Wunknown"],
      #plt_apps: ["extwitter", "phoenix", "phoenix_html", "cowboy", "phoenix_ecto", "postgrex", "ecto", "plug","floki"],
      plt_file: "xdialyzer.plt",
      #plt_add_dep: True,
      #paths: [
      #  "_build/dev/lib/phoenix/ebin",
      #  "_build/dev/lib/phoenix_html/ebin",
      #  "_build/dev/lib/cowboy/ebin",
      #  "_build/dev/lib/phoenix_ecto/ebin",
      #  "_build/dev/lib/postgrex/ebin",
      #  "_build/dev/lib/ecto/ebin",
      #  "_build/dev/lib/plug/ebin",
      #  "_build/dev/lib/floki/ebin",
      #  "_build/dev/lib/extwitter/ebin"
      #  ]
      #output_plt: ["dialyzer.plt"]
     ]
   ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {Hue2, []},
     #env: [:number, 10],
     applications: [:phoenix, :phoenix_html, :cowboy, :logger,
                    :phoenix_ecto, :postgrex, :httpoison, :tzdata, :quantum]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [{:phoenix, "~> 1.1.3"},
     {:phoenix_ecto, "~> 1.1"},
     {:postgrex, ">= 0.0.0"},
     {:phoenix_html, "~> 2.1"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:cowboy, "~> 1.0"},

     {:extwitter, "~> 0.6"}  ,
     {:oauth, github: "tim/erlang-oauth"},
     {:extwitter, "~> 0.5"} ,
     {:floki, "~> 0.7"},
     {:httpoison, "~> 0.8"},
     {:timex, "~> 0.19"},
     {:timex_ecto, "~> 0.5"},

     {:quantum, "~> 1.5"},

     {:html_entities, "~> 0.2"},

     {:dialyxir, "~> 0.3", only: [:dev]}
   ]
  end

  # Aliases are shortcut or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"]]
  end
end
