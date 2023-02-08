# resolve & install minimal dependencies for a given package + execute R CMD CHECK with min deps installed
# The aim is to check correctness of a DESCRIPTION file, i.e. min deps specification
# This covers only _direct_ deps, i.e. it does not resolve recursively dependencies of dependencies.
# Example: A -imports-> B -imports-> C
# When executed for A, script would read A's DESCRIPTION file, determine minimal version of B and install it using latest version of C (i.e. base package installation)
# Initial assessment of recursive functionality oftentimes lead to install compilation error of very old pkgs, errors in historical package releases that are not valid anymore or install requests of archived and not maintained pkgs. It's hard to decide what to do with it.
# The functionality relies heavily on pkgdepends::new_pkg_installation_proposal and its dependency resolving mechanism.


install.packages(c("httr", "pak", "pkgdepends", "pkgcache"))

# get all tags
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
# this assumes common practice of version 1.2.3 is tagged with "[v]1.2.3"
get_ver_from_tag <- function(x) {
  package_version(gsub("^v", "", tags), strict = FALSE)
}

# main function
# for ref description please see https://r-lib.github.io/pkgdepends/reference/pkg_refs.html
# ref could point to a local dir (with R package) or GH repo
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

      # check if bioconductor package #@TODO: would be good to pre-set it somehow in DESCRIPTION file to avoid this check
      if (is(i_ref_parsed, "remote_ref_standard")) {
        if (any(vapply(i_pkg_cache$sources, grepl, logical(1), pattern = paste0(pkgcache::bioc_repos(), collapse = "|")))) {
          i_ref <- sprintf("bioc::%s", i_ref)
          i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
        }
      }

      # resolve minimal version
      if (is(i_ref_parsed, "remote_ref_standard") || is(i_ref_parsed, "remote_ref_cran")) {
        i_pkg_cache <- pkgcache::meta_cache_list(i_pkg)
        i_pkg_cache_archive <- pkgcache::cran_archive_list(package = i_pkg)
        pv_valid <- pv_all <- sort(package_version(unique(c(i_pkg_cache$version, i_pkg_cache_archive$version))), decreasing = TRUE)
        if (i_op != "") {
          pv_valid <- Filter(function(x) !is.na(x) && do.call(i_op, list(x, package_version(i_ver))), pv_all)
        }
        i_ver <- as.character(min(pv_valid))
        i_ref <- sprintf("%s@%s", i_ref, i_ver)
        i_ref_parsed <- pkgdepends::parse_pkg_ref(i_ref)
      } else if (is(i_ref_parsed, "remote_ref_github")) {
        tags <- get_gh_tags(i_ref_parsed$username, i_ref_parsed$repo)
        pv_all <- get_ver_from_tag(tags)
        if (i_op != "") {
          pv_valid <- Filter(function(x) !is.na(x) && do.call(i_op, list(x, package_version(i_ver))), pv_all)
        } else {
          pv_valid <- Filter(Negate(is.na), pv_all)
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

  cat("---\n")
  cat("Package dependencies using minimal verison strategy:\n")
  for (i in deps_refs) cat(sprintf("%s\n", i))
  cat("---\n")

  res <- pkgdepends::new_pkg_installation_proposal(deps_refs, config = list(library = tempfile()))
  res
}

## tests
ref <- "local::./repository"

x <- new_min_deps_installation_proposal(ref)
x$solve()
x$get_solution()
stopifnot(x$get_solution()$status == "OK")
x$download()
x$install()

# x$create_lockfile("pkg.lock") # if needed as an output artifact
# x$draw() # for debugging

# R CMD CHECK with min deps installed
install.packages("rcmdcheck")
libpath <- x$get_config()$get("library")
rcmdcheck::rcmdcheck(ref, libpath = libpath)
