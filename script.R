catnl <- function(x = "") cat(sprintf("%s\n", x))

catnl("Install required packages")
install.packages(c("remotes", "cli"), quiet = TRUE, verbose = FALSE, repos = "http://cran.us.r-project.org")
remotes::install_github("insightsengineering/verdepcheck", quiet = TRUE, verbose = FALSE)
remotes::install_github("r-lib/rcmdcheck#196", quiet = TRUE, verbose = FALSE) # TODO: remove when merged / linked issue fixed

args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(file.path(".", args[1]))
build_args <- strsplit(args[2], " ")[[1]]
check_args <- strsplit(args[3], " ")[[1]]
strategy <- strsplit(args[4], " ")[[1]]

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
saveRDS(x, "res.RDS")

cli::cli_h1("Debug output:")

cli::cli_h2("Installation proposal:")
x$ip

cli::cli_h2("Installation proposal config:")
x$ip$get_config()

cli::cli_h2("Package DESCRIPTION file used (see Remotes section):")
catnl(readLines(gsub(".*::", "", x$ip$get_refs())))

cli::cli_h2("Dependency solution:")
x$ip$get_solution()

cli::cli_h2("Dependency resolution:")
x_res <- subset(x$ip$get_resolution(), , c(ref, package, version))
if ("tibble" %in% rownames(installed.packages())) {
    print(x_res, n = Inf)
} else {
    print(as.data.frame(x_res))
}

cli::cli_h2("Dependency resolution (tree):")
try(x$ip$draw())

# TODO: https://github.com/r-lib/pkgdepends/issues/305 - remove when fixed
# this provides additional debug info in case of empty error report
if (inherits(x$ip, "pkg_installation_proposal") &&
    inherits(x$ip$get_solution(), "pkg_solution_result") &&
    x$ip$get_solution()$status == "FAILED" &&
    inherits(x$ip$get_solution()$failures, "pkg_solution_failures") &&
    grepl("*.dependency conflict$", format(x$ip$get_solution()$failures)[[1]])
) {
    cli::cli_h2("Supplementary solution (experimental):")
    xx <- pkgdepends::new_pkg_deps(desc::desc(gsub("deps::", "", x$ip$get_refs()))$get_remotes(), config = list(library = tempfile()))
    verdepcheck:::solve_ip(xx)
    xx$get_solution()
}

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

stopifnot("pkg dependency resolve failed - please see the above logs for details" = x$ip$get_solution()$status == "OK")
stopifnot("R CMD BUILD resulted in error - please see the above logs for details" = !is.null(x$check))
stopifnot("R CMD CHECK resulted in error - please see the above logs for details" = x$check$status == 0)

catnl("Success!")
