# Print with a string with new line
catnl <- function(x = "") cat(sprintf("%s\n", x))
# Print a string from a variable (showing variable name before)
catnl_param <- function(x = "") {
  var_name <- tryCatch(rlang::as_name(rlang::enexpr(x)), error = function(err) NULL)
  if (is.null(var_name)) return(catnl(x))
  var_string <- sprintf("%s:", var_name)
  if (length(x) == 0) cat(var_string, "(empty)\n") else cat(var_string, x, "\n")
}

catnl("\n── \033[1mInstall required packages\033[22m ────────────")

install.packages(c("pak"), quiet = TRUE, verbose = FALSE)
pak::pak(c("cli", "rlang", "pkgdepends", "desc"))
pak::pak("insightsengineering/verdepcheck")
pak::pak("r-lib/rcmdcheck")
library(withr)

args <- trimws(commandArgs(trailingOnly = TRUE))
path <- normalizePath(file.path(".", args[1]))
extra_deps <- args[2]
build_args <- strsplit(args[3], " ")[[1]]
check_args <- strsplit(args[4], " ")[[1]]
strategy <- args[5]
additional_repositories <- strsplit(args[6], ";")[[1]]

cli::cli_h1("Cat script parameters")
catnl_param(path)
catnl_param(extra_deps)
catnl_param(build_args)
catnl_param(check_args)
catnl_param(strategy)
catnl_param(additional_repositories)

rlang::local_options(repos = c(getOption("repos"), additional_repositories))

cli::cli_h1("Execute verdepcheck...")
fun <- switch(
    strategy,
    "min_cohort" = verdepcheck::min_cohort_deps_check,
    "min_isolated" = verdepcheck::min_isolated_deps_check,
    "release" = verdepcheck::release_deps_check,
    "max" = verdepcheck::max_deps_check,
    stop("Unknown strategy")
)
x <- fun(path, extra_deps = extra_deps, check_args = check_args, build_args = build_args)
saveRDS(x, "res.RDS")

cli::cli_h1("Debug output:")

cli::cli_h2("Installation proposal:")
x$ip

cli::cli_h2("Installation proposal config:")
x$ip$get_config()

cli::cli_h2("Package DESCRIPTION file used (see Remotes section):")
catnl(readLines(file.path(gsub(".*::", "", x$ip$get_refs()), "DESCRIPTION")))


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
if (inherits(x$ip, "pkg_installation_proposal") && # nolint: cyclocomp.
    inherits(x$ip$get_solution(), "pkg_solution_result") &&
    x$ip$get_solution()$status == "FAILED" &&
    inherits(x$ip$get_solution()$failures, "pkg_solution_failures") &&
    grepl("*.dependency conflict$", format(x$ip$get_solution()$failures)[[1]])
) {
    cli::cli_h2("Supplementary solution (experimental):")
    xx <- pkgdepends::new_pkg_installation_proposal(
        trimws(strsplit(
            desc::desc(
                file.path(gsub("deps::", "", x$ip$get_refs()), "DESCRIPTION")
            )$get_field("Config/Needs/verdepcheck")
        , ",")[[1]]),
        config = list(library = tempfile())
    )
    class(xx) <- class(x$ip)
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
