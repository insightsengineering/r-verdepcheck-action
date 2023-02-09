
cat("---\n")
cat("Install required packages\n")
install.packages(c("httr", "pak", "pkgdepends", "pkgcache"))

# get all tags
# @param org (character(1)) GH org name
# @param repo (character(1)) repo name within org
# @return (character(n)) vector with all tags
get_gh_tags <- function(org, repo) {
  url_str <- sprintf("https://api.github.com/repos/%s/%s/git/refs/tags", org, repo)
  resp <- httr::GET(url_str, httr::add_headers(
    "Accept" = "application/vnd.github+json",
    "Authorization" = sprintf("Bearer %s", Sys.getenv("GITHUB_PAT")),
    "X-GitHub-Api-Version" = "2022-11-28"
  ))
  resp_json <- jsonlite::parse_json(resp)
  gsub("^refs/tags/", "", vapply(resp_json, `[[`, character(1), "ref"))
}
# extract version from git tag
# this assumes common practice that pkg version 1.2.3 is usually tagged with "[v]1.2.3"
# @param x (character(n)) vector with tag names
# @return (character(n)) vector with valid package number, NA for non-convertable values
get_ver_from_tag <- function(x) {
  package_version(gsub("^v", "", x), strict = FALSE)
}

# main function
# @param ref (character(1)) package reference, for details please see: `? pkgdepends::pkg_refs`
# @return (pkg_installation_proposal) object created with `pkgdepends::new_pkg_installation_proposal`
new_min_deps_installation_proposal <- function(ref) {
  x <- pak::pkg_download(ref)
  deps <- x$deps[[1]]

  #trim deps
  deps <- subset(deps, !(package %in% c("R", rownames(installed.packages(priority = "base")))))
  deps <- subset(deps, type %in% pkgdepends::pkg_dep_types())

  deps_refs <- vapply(
    seq_len(nrow(deps)),
    function(i) {
      i_ref <- deps[i, "ref"]
      i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
      i_pkg <- deps[i, "package"]
      i_op <- deps[i, "op"]
      i_ver <- deps[i, "version"]

      # check if package from Bioconductor
      if (is(i_ref_parsed, "remote_ref_standard")) {
        i_pkg_cache <- pkgcache::meta_cache_list(i_pkg)
        if (any(vapply(unlist(i_pkg_cache$sources), grepl, logical(1), pattern = paste0(pkgcache::bioc_repos(), collapse = "|")))) {
          i_ref <- sprintf("bioc::%s", i_ref)
          i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
        }
      }

      # resolve minimal version
      if (is(i_ref_parsed, "remote_ref_standard") || is(i_ref_parsed, "remote_ref_cran")) {
        i_pkg_cache <- pkgcache::meta_cache_list(i_pkg)
        i_pkg_cache_archive <- pkgcache::cran_archive_list(package = i_pkg)
        pv_all <- sort(package_version(unique(c(i_pkg_cache$version, i_pkg_cache_archive$version))), decreasing = TRUE)
        pv_valid <- Filter(Negate(is.na), pv_all)
        if (i_op != "") {
          pv_valid <- Filter(function(x) do.call(i_op, list(x, package_version(i_ver))), pv_valid)
        }
        i_ver <- as.character(min(pv_valid))
        i_ref <- sprintf("%s@%s", i_ref, i_ver)
        i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
      } else if (is(i_ref_parsed, "remote_ref_github")) {
        tags <- get_gh_tags(i_ref_parsed$username, i_ref_parsed$repo)
        pv_all <- get_ver_from_tag(tags)
        pv_valid <- Filter(Negate(is.na), pv_all)
        if (i_op != "") {
          pv_valid <- Filter(function(x) do.call(i_op, list(x, package_version(i_ver))), pv_valid)
        }
        tag_min <- tags[which(pv_all == min(pv_valid))]
        i_ref <- sprintf("%s/%s@%s", i_ref_parsed$username, i_ref_parsed$repo, tag_min)
        i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
      }

      # @TODO: wait for https://github.com/r-lib/pak/issues/122
      # as a suggested workaround - use GH mirror of CRAN
      if (is(i_ref_parsed, "remote_ref_standard") || is(i_ref_parsed, "remote_ref_cran")) {
        i_ref <- sprintf("cran/%s", i_ref)
        i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
      }

      return(i_ref)
    },
    character(1)
  )

  pkgdepends::new_pkg_installation_proposal(deps_refs, config = list(library = tempfile()))
}

## tests
args = commandArgs(trailingOnly=TRUE)
ref_path <- file.path(".", args[1])
ref_pak <- paste0("local::", ref_path)

cat("---\n")
cat("Extract minimal versions of package dependencies...\n")
x <- new_min_deps_installation_proposal(ref_pak)

cat("---\n")
cat("Package dependencies using minimal verison strategy:\n")
x$get_refs()

cat("---\n")
cat("Solve package dependencies...\n")
x$solve()
cat("Solution:\n")
x$get_solution()
stopifnot("Dependency solver resulted in error - please see the log for details" = x$get_solution()$status == "OK")
cat("Solution (tree view):\n")
x$draw()
x$create_lockfile("pkg.lock")

cat("---\n")
cat("Download all packages...\n")
x$download()
cat("---\n")
cat("Install all packages...\n")
x$install()

# debug lines
cat("---\n")
sessionInfo()
cat("---\n")
installed.packages()
cat("---\n")
libpath <- x$get_config()$get("library")
installed.packages(lib.loc = libpath)[, c("LibPath", "Version")]
cat("---\n")
list.files(libpath)
cat("---\n")


cat("---\n")
cat("R CMD CHECK...\n")
install.packages("rcmdcheck")
libpath <- x$get_config()$get("library")
res_check <- rcmdcheck::rcmdcheck(ref_path, libpath = libpath)
cat("---\n")
cat("R CMD CHECK sessioninfo:\n")
res_check$session_info$packages[, c("package", "ondiskversion", "source", "library")]
stopifnot("R CMD CHECK resulted in error - please see the log for details" = res_check$status == 0)
