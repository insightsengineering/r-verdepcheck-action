catnl <- function(x = "") cat(sprintf("%s\n", x))

catnl("Install required packages")
install.packages(c("remotes", "cli"))
remotes::install_github("insightsengineering/verdepcheck")
remotes::install_github("r-lib/rcmdcheck#196") # TODO: remove when merged / linked issue fixed

args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(file.path(".", Sys.getenv("VERDEPCHECK_REPOSITORY_PATH")))
build_args <- strsplit(Sys.getenv("VERDEPCHECK_BUILD_ARGS"), " ")[[1]]
if (is.na(build_args) || build_args == "") build_args <- character(0)
check_args <- strsplit(Sys.getenv("VERDEPCHECK_CHECK_ARGS"), " ")[[1]]
if (is.na(check_args) || check_args == "") check_args <- character(0)
strategy <- strsplit(Sys.getenv("VERDEPCHECK_STRATEGY"), " ")[[1]]

cli::cli_h1("Cat script parameters")
catnl("path:")
catnl(path)
catnl("build_args:")
catnl(build_args)
catnl("check_args:")
catnl(check_args)
catnl("strategy:")
catnl(strategy)

cli::cli_h1("Execute verdepcheck...")
fun <- switch(
    strategy,
    "min" = verdepcheck::min_deps_check,
    "release" = verdepcheck::release_deps_check,
    "max" = verdepcheck::max_deps_check,
    stop("Unknown strategy")
)
x <- fun(path, check_args = check_args, build_args = build_args)


cli::cli_h1("Installation proposal:")
x$ip

cli::cli_h2("Package DESCRIPTION file used (see Remotes section):")
catnl(readLines(gsub(".*::", "", x$ip$get_refs())))

cli::cli_h2("Dependency solution:")
x$ip$get_solution()

cli::cli_h2("Dependency resolution:")
print(subset(x$ip$get_resolution(), , c(ref, package, version)), n = Inf)

cli::cli_h2("Dependency resolution (tree):")
try(x$ip$draw())

# TODO: https://github.com/r-lib/pkgdepends/issues/305 - remove when fixed
cli::cli_h2("Supplementary solution (experimental - use only when the above results in empty report):")
xx <- pkgdepends::new_pkg_deps(desc::desc(gsub("deps::", "", x$ip$get_refs()))$get_remotes(), config = list(library = tempfile()))
xx$solve()
xx$get_solution()


cli::cli_h1("Create lockfile...")
try(x$ip$create_lockfile("pkg.lock"))


cli::cli_h1("R CMD CHECK:")
x$check

cli::cli_h2("R CMD CHECK status:")
catnl(x$check$status)

cli::cli_h2("R CMD CHECK install out:")
cat(x$check$install_out)

cli::cli_h2("R CMD CHECK stdout:")
cat(x$check$stdout)

cli::cli_h2("R CMD CHECK stderr:")
cat(x$check$stderr)

cli::cli_h2("R CMD CHECK session info:")
x$check$session_info

cli::cli_h2("R CMD CHECK test output:")
lapply(x$check$test_output, cat)

catnl()
stopifnot("R CMD CHECK resulted in error - please see the above log for details" = x$check$status == 0)
