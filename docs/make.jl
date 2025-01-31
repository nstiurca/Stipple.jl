using Documenter

push!(LOAD_PATH,  "../../src")

using Stipple, Stipple.Elements, Stipple.Layout, Stipple.Typography

makedocs(
    sitename = "Stipple - data dashboards and reactive UIs for Julia",
    format = Documenter.HTML(prettyurls = false),
    pages = [
        "Home" => "index.md",
        "Tutorials" => [
          "Stipple LifeCycle" => "guides/Stipple_LifeCycle.md",
        ],
        "Stipple API" => [
          "Elements" => "API/elements.md",
          "Layout" => "API/layout.md",
          "NamedTuples" => "API/namedtuples.md",
          "Stipple" => "API/stipple.md",
          "Typography" => "API/typography.md",
        ]
    ],
)

deploydocs(
  repo = "github.com/GenieFramework/Stipple.jl.git",
)
