% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/r3d_utils.R
\name{mclapply.hack}
\alias{mclapply.hack}
\title{Cross-Platform Parallel Lapply Helper}
\usage{
mclapply.hack(X, FUN, mc.cores = 1, ...)
}
\arguments{
\item{X}{A list (or vector) over which to iterate.}

\item{FUN}{The function to apply to each element of \code{X}.}

\item{mc.cores}{Number of CPU cores requested. Defaults to 1.}

\item{...}{Additional arguments passed to \code{FUN}.}
}
\value{
A list of the same length as \code{X}, containing the results of \code{FUN}.
}
\description{
\strong{Internal function.} A wrapper around \code{\link[parallel]{mclapply}} that
uses \code{\link[parallel]{parLapply}} on Windows (where \code{mclapply} is not supported),
and falls back to \code{\link{lapply}} if \code{cores=1} or the \pkg{parallel} package
is unavailable.
}
\keyword{internal}
