catnl <- function(x = "") cat(sprintf("%s\n", x))

catnl("Install required packages")
install.packages(c("remotes", "cli"))
remotes::install_github("insightsengineering/verdepcheck")
remotes::install_github("r-lib/rcmdcheck#196") # TODO: remove when merged / linked issue fixed

args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(file.path(".", args[1]))
build_args <- strsplit(args[2], " ")[[1]]
if (is.na(build_args) || build_args == "") build_args <- character(0)
check_args <- strsplit(args[3], " ")[[1]]
if (is.na(check_args) || check_args == "") check_args <- character(0)

cli::cli_h1("Cat script parameters")
catnl("path:")
catnl(path)
catnl("build_args:")
catnl(build_args)
catnl("check_args:")
catnl(check_args)

cli::cli_h1("Execute verdepcheck...")
x <- verdepcheck::min_deps_check(path, check_args = check_args, build_args = build_args)


cli::cli_h1("Installation proposal:")
x$ip

cli::cli_h2("Package DESCRIPTION file used:")
catnl(readLines(gsub(".*::", "", x$ip$get_refs())))

cli::cli_h2("Dependency solution:")
x$ip$get_solution()

cli::cli_h2("Dependency resolution:")
print(subset(x$ip$get_resolution(), , c(ref, package, version)), n = Inf)

cli::cli_h2("Dependency resolution (tree):")
try(x$ip$draw())


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
