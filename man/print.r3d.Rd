% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/r3d_methods.R
\name{print.r3d}
\alias{print.r3d}
\title{Print Method for r3d Objects}
\usage{
\method{print}{r3d}(x, ...)
}
\arguments{
\item{x}{An \code{r3d} object returned by \code{\link{r3d}}.}

\item{...}{Additional arguments (not used).}
}
\value{
Returns the \code{x} object invisibly.
}
\description{
Gives a concise overview of an \code{r3d} object's main properties, including the design type
(sharp or fuzzy), local polynomial order, sample size, and bandwidth choice. It also shows
a numeric summary (min, median, max) of the estimated distributional RD effect \eqn{\tau(q)}.
}
\details{
This function is invoked automatically when an \code{r3d} object is printed on the console,
e.g., simply by typing its name. For a more detailed summary, use \code{\link{summary.r3d}}.
}
\examples{
\dontrun{
  fit <- r3d(X, Y_list, boot=TRUE)
  print(fit)
}

}
