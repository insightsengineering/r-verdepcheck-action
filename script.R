# Print with a string with new line
catnl <- function(x = "") cat(sprintf("%s\n", x))
# Print a string from a variable (showing variable name before)
catnl_param <- function(x = "") {
  var_name <- tryCatch(rlang::as_name(rlang::enexpr(x)), error = function(err) NULL)
  if (is.null(var_name)) return(catnl(x))
  var_string <- sprintf("%s:", var_name)
  if (length(x) == 0) cat(var_string, "(empty)\n") else cat(var_string, x, "\n")
}

catnl("Install required packages")

install.packages(c("remotes", "cli", "pkgcache", "pkgdepends"), quiet = TRUE, verbose = FALSE, repos = "https://cloud.r-project.org")
remotes::install_github("insightsengineering/verdepcheck", ref = "fix-random-download@main", quiet = TRUE, verbose = FALSE)
remotes::install_github("r-lib/rcmdcheck#196", quiet = TRUE, verbose = FALSE) # TODO: remove when merged / linked issue fixed

args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(file.path(".", args[1]))
build_args <- strsplit(args[2], " ")[[1]]
check_args <- strsplit(args[3], " ")[[1]]
strategy <- strsplit(args[4], " ")[[1]]

cli::cli_h1("Cat script parameters")
catnl_param(path)
catnl_param(build_args)
catnl_param(check_args)
catnl_param(strategy)

cli::cli_h1("Execute verdepcheck...")
fun <- switch(
    strategy,
    "min_cohort" = verdepcheck::min_cohort_deps_check,
    "min_isolated" = verdepcheck::min_isolated_deps_check,
    "release" = verdepcheck::release_deps_check,
    "max" = verdepcheck::max_deps_check,
    stop("Unknown strategy")
)
x <- fun(path, check_args = check_args, build_args = build_args)
saveRDS(x, "res.RDS")

catnl()

stopifnot("pkg dependency resolve failed - please see the above logs for details" = x$ip$get_solution()$status == "OK")
stopifnot("R CMD BUILD resulted in error - please see the above logs for details" = !is.null(x$check))
stopifnot("R CMD CHECK resulted in error - please see the above logs for details" = x$check$status == 0)

catnl("Success!")
