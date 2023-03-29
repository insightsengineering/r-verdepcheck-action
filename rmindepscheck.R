catnl <- function(x) cat(sprintf("%s\n", x))
catbr <- function() catnl("---")

catbr()
catnl("Install required packages")
install.packages("remotes")
remotes::install_github("insightsengineering/verdepcheck@*release")

args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(file.path(".", args[1]))
build_args <- strsplit(args[2], " ")[[1]]
if (is.na(build_args) || build_args == "") build_args <- character(0)
check_args <- strsplit(args[3], " ")[[1]]
if (is.na(check_args) || check_args == "") check_args <- character(0)

# @TODO: wait for https://github.com/r-lib/rcmdcheck/issues/195
# as a workaround - skip vignettes
check_args <- unique(c(check_args, "--ignore-vignettes"))
build_args <- unique(c(build_args, "--no-build-vignettes"))

catbr()
catnl("Cat script parameters")
catnl("path:")
catnl(path)
catnl("\n")
catnl("build_args:")
catnl(build_args)
catnl("\n")
catnl("check_args:")
catnl(check_args)
catnl("\n")

catbr()
catnl("Execute verdepcheck...")
x <- verdepcheck::min_deps_check(path, check_args = check_args, build_args = build_args)


catbr()
catnl("Installation proposal:")
x$ip

catbr()
catnl("Package DESCRIPTION file used:")
catnl(readLines(gsub(".*::", "", x$ip$get_refs())))

catbr()
catnl("Dependency solution:")
x$ip$get_solution()

catbr()
catnl("Dependency resolution:")
subset(x$ip$get_resolution(), , c(ref, package, version))

catbr()
catnl("Dependency resolution (tree):")
try(x$ip$draw())

catbr()
catnl("Create lockfile:")
try(x$ip$create_lockfile("pkg.lock"))


catbr()
catnl("R CMD CHECK:")
x$check

catbr()
catnl("R CMD CHECK status:")
catnl(x$check$status)

catbr()
catnl("R CMD CHECK install out:")
cat(x$check$install_out)

catbr()
catnl("R CMD CHECK stdout:")
cat(x$check$stdout)

catbr()
catnl("R CMD CHECK stderr:")
cat(x$check$stderr)

catbr()
catnl("R CMD CHECK session info:")
x$check$session_info

catbr()
catnl("R CMD CHECK test output:")
lapply(x$check$test_output, cat)

catbr()
stopifnot("R CMD CHECK resulted in error - please see the above log for details" = x$check$status == 0)
