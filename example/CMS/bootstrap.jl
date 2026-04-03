using Pkg

const INOCHI_URL = "https://github.com/tepel-chen/Inochi.jl"
const IWAIENGINE_URL = "https://github.com/tepel-chen/IwaiEngine.jl"
const MANIFEST_PATH = joinpath(@__DIR__, "Manifest.toml")

function bootstrap(; do_precompile::Bool = true)
    isfile(MANIFEST_PATH) && rm(MANIFEST_PATH; force = true)
    Pkg.activate(@__DIR__)
    Pkg.add([
        Pkg.PackageSpec(url = INOCHI_URL),
        Pkg.PackageSpec(url = IWAIENGINE_URL),
    ])
    Pkg.add("LibPQ")
    Pkg.add("PostgresORM")
    Pkg.add("Tables")
    Pkg.instantiate()
    do_precompile && Pkg.precompile()
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    bootstrap()
end
