#' County latitude and longitude designations
#'
#' A dataframe containing latitude, longitude, FIPS code, name, and region code
#' for each US county. This dataset put together using a dataframe from the US
#' Census Bureau, which was pulled from the website listed in "Sources."
#'
#' @format A dataframe with 3,143 rows and 5 variables:
#' \describe{
#'    \item{latitude}{A numeric vector giving the latutude at the center of each
#'                    county}
#'    \item{longitude}{A numeric vector giving the longitude at the center of
#'                     each county}
#'    \item{fips}{A numeric vector giving the county's five-digit Federal
#'                Information Processing Standard (FIPS) code}
#'    \item{name}{A character vector giving the name and state for each county}
#'    \item{region}{A numeric vector giving the four-digit or five-digit Federal
#'                  Information Processing Standard (FIPS) code (values in this
#'                  column are identical to those in the "fips" column, but do
#'                  not include leading zeros)}
#' }
#'
#' @source
#'
#' \url{http://www2.census.gov/geo/docs/reference/cenpop2010/county/CenPop2010_Mean_CO.txt}
"county_centers"