#' NOAA NCDC station IDs per county.
#'
#' Returns a dataframe with NOAA NCDC station IDs for
#' a single U.S. county. This function has options to filter stations based on
#' maximum and minimum dates, as well as percent data coverage.
#'
#' @note Because this function uses the NOAA API to identify the weather
#'    monitors within a U.S. county, you will need to get an access token from
#'    NOAA to use this function. Visit NOAA's token request page
#'    (\url{http://www.ncdc.noaa.gov/cdo-web/token}) to request a token by
#'    email. You then need to set that API code in your R session (e.g., using
#'    \code{options(noaakey = "your key")}, replacing "your key" with the API
#'    key you've requested from NOAA). See the package vignette for more details.
#'
#' @param fips A string with the five-digit U.S. FIPS code of a county
#'    in numeric, character, or factor format.
#' @param date_min A string with the desired starting date in character, ISO
#'    format ("yyyy-mm-dd"). The dataframe returned will include only stations
#'    that have data for dates including and after the specified date.
#' @param date_max A string with the desired ending date in character, ISO
#'    format ("yyyy-mm-dd"). The dataframe returned will include only stations
#'    that have data for dates up to and including the specified date.
#'
#' @return A dataframe with NOAA NCDC station IDs for a single U.S. county.
#'
#' @examples
#' \dontrun{
#' stations_36005 <- daily_stations("36005")
#' stations_36005
#'
#' miami_stations <- daily_stations("12086", date_min = "1999-01-01",
#'                                  date_max = "2012-12-31")
#' miami_stations
#' }
#'
#' @importFrom dplyr %>%
#' @export
daily_stations <- function(fips, date_min = NULL, date_max = NULL) {

  FIPS <- paste0('FIPS:', fips)
  station_ids <- rnoaa::ncdc_stations(datasetid = 'GHCND', locationid = FIPS,
                                      limit = 10)

  station_df <- station_ids$data
  if (station_ids$meta$totalCount > 10) {
    how_many_more <- station_ids$meta$totalCount - 10
    more_stations <- rnoaa::ncdc_stations(datasetid = 'GHCND',
                                          locationid = FIPS,
                                          limit = how_many_more,
                                          offset = 10 + 1)
    station_df <- rbind(station_df, more_stations$data)
  }

  # If either `min_date` or `max_date` option was null, set to a date that
  # will keep all monitors in the filtering.
  if (is.null(date_max)) {
    date_max <- min(station_df$maxdate)
  }
  if (is.null(date_min)) {
    date_min <- max(station_df$mindate)
  }

  date_max <- lubridate::ymd(date_max)
  date_min <- lubridate::ymd(date_min)

  tot_df <- dplyr::mutate_(station_df,
                           mindate = ~ lubridate::ymd(mindate),
                           maxdate = ~ lubridate::ymd(maxdate)) %>%
    dplyr::filter_(~ maxdate >= date_min & mindate <= date_max) %>%
    dplyr::select_(.dots = c("id", "latitude", "longitude", "name")) %>%
    dplyr::mutate_(id = ~ gsub("GHCND:", "", id))

  return(tot_df)
}

#' Average daily weather data across multiple stations.
#'
#' Returns a dataframe with daily weather averaged across
#' stations, as well as columns showing the number of stations contributing
#' to the average for each variable and each day.
#'
#' @param weather_data A dataframe with daily weather observations. This
#'    dataframe is returned from the \code{rnoaa} function
#'    \code{meteo_pull_monitors}.
#'
#' @importFrom dplyr %>%
ave_daily <- function(weather_data) {

  all_cols <- colnames(weather_data)
  not_vars <- c("id", "date")
  g_cols <- all_cols[!all_cols %in% not_vars]

  #not sure about -id -date cols - how to do NSE here
  averaged_data <- tidyr::gather_(weather_data, key_col = "key",
                                  value_col = "value",
                                  gather_cols = g_cols) %>%
    dplyr::group_by_(.dots = c("date", "key")) %>%
    dplyr::summarize_(mean = ~ mean(value, na.rm = TRUE)) %>%
    tidyr::spread_(key_col = "key", value_col = "mean") %>%
    dplyr::ungroup()

  n_reporting <- tidyr::gather_(weather_data, key_col = "key",
                                value_col = "value",
                                gather_cols = g_cols) %>%
    dplyr::group_by_(.dots = c("date", "key")) %>%
    dplyr::summarize_(n_reporting = ~ sum(!is.na(value))) %>%
    dplyr::mutate_(key = ~ paste(key, "reporting", sep = "_")) %>%
    tidyr::spread_(key_col = "key", value_col = "n_reporting")

  averaged_data <- dplyr::left_join(averaged_data, n_reporting,
                                    by = "date")
  return(averaged_data)
}

#' Filter stations based on "coverage" requirements.
#'
#' Filters available weather stations based on a specified required minimum
#' coverage (i.e., percent non-missing daily observations). Weather stations
#' with non-missing data for fewer days than specified by \code{coverage} will
#' be excluded from the county average.
#'
#' @param coverage_df A dataframe as returned by the \code{meteo_coverage}
#'    function in the \code{rnoaa} package
#' @param coverage A numeric value in the range of 0 to 1 that specifies
#'    the desired percentage coverage for the weather variable (i.e., what
#'    percent of each weather variable must be non-missing to include data from
#'    a monitor when calculating daily values averaged across monitors).
#'
#' @return A dataframe with stations that meet the specified coverage
#'    requirements for weather variables included in the \code{coverage_df}
#'    dataframe passed to the function.
#'
#' @importFrom dplyr %>%
filter_coverage <- function(coverage_df, coverage = 0) {

  if (is.null(coverage)) {
    coverage <- 0
    }

  all_cols <- colnames(coverage_df)
  not_vars <- c("id", "start_date", "end_date", "total_obs")
  g_cols <- all_cols[!all_cols %in% not_vars]

  filtered <- dplyr::select_(coverage_df,
                             .dots = list("-start_date", "-end_date",
                                          "-total_obs")) %>%
    tidyr::gather_(key_col = "key", value_col = "covered",
                   gather_cols = g_cols)  %>%
    dplyr::filter_(~ covered >= coverage) %>%
    dplyr::mutate_(covered_n = ~ 1) %>%
    dplyr::group_by_(.dots = list("id")) %>%
    dplyr::mutate_(good_monitor = ~ sum(!is.na(covered_n)) > 0) %>%
    dplyr::ungroup() %>%
    dplyr::filter_(~ good_monitor) %>%
    dplyr::select_(.dots = list("-good_monitor", "-covered_n"))

  colnames(filtered)[3] <- "calc_coverage"

  return(filtered)
}

#' Plot daily weather stations for a particular county.
#'
#' Produces a map with points indicating stations that contribute
#' to the weather data in the \code{daily_data} data frame output by
#' \code{daily_fips}.
#'
#' @param fips A five-digit FIPS county code.
#' @param daily_data A list returned from the function \code{daily_df} (see
#'    helpfile for \code{daily_df}).
#' @param point_color Character string with color for points
#'    mapping the locations of weather stations (passes to \code{ggplot}).
#' @param point_size Character string with size for for points
#'    mapping the locations of weather stations (passes to \code{ggplot}).
#' @param station_label TRUE / FALSE Whether to include labels for
#'    each weather station.
#'
#' @return A \code{ggplot} object mapping all weather stations for a particular
#'    county satisfying the conditions present in \code{daily_df}'s
#'    arguments (date range, coverage, and/or weather variables). 2011 U.S.
#'    Census cartographic boundary shapefiles are used to provide county
#'    outlines.
#'
#' @examples
#' \dontrun{
#' miami_stations <- daily_stations(fips = "12086", date_min = "1992-08-01",
#'                           date_max = "1992-08-31")
#' daily_data <- daily_df(stations = miami_stations, coverage = 0.90,
#'                       var = c("tmax", "tmin", "prcp"),
#'                       date_min = "1992-08-01", date_max = "1992-08-31")
#' daily_stationmap(fips = "12086", daily_data = daily_data)
#' }
#'
#' @importFrom dplyr %>%
daily_stationmap <- function(fips, daily_data, point_color = "firebrick",
                             point_size = 2, station_label = FALSE) {

  # for plot title
  census_data <- countyweather::county_centers
  row_num <- which(grepl(fips, census_data$fips))
  title <- as.character(census_data[row_num, "name"])

  # for ggmap lat/lon
  loc_fips <- which(census_data$fips == fips)
  lat_fips <- as.numeric(census_data[loc_fips, "latitude"])
  lon_fips <- as.numeric(census_data[loc_fips, "longitude"])

  state <- stringi::stri_sub(fips, 1, 2)
  county <- stringi::stri_sub(fips, 3)

  shp <- tigris::counties(state, cb = TRUE)
  county_shp <- shp[shp$COUNTYFP == county, ]

  # convert to raster so that we can add geom_raster() (which gets rid of the
  # geom_polygons island problem)
  r <- raster::raster(raster::extent(county_shp))
  raster::res(r) <- 0.001
  raster::projection(r) <- sp::proj4string(county_shp)
  r <- raster::rasterize(county_shp, r)
  rdf <- data.frame(raster::rasterToPoints(r))

  # use range of raster object to figure out what zoom to use in ggmap
  x_range <- r@extent[2] - r@extent[1]
  y_range <- r@extent[4] - r@extent[3]

  # limits were calculated by finding out the x and y limits of a ggmap at each
  # zoom, then accounting for the extra space we want to add around county
  # shapes.

  if (x_range > y_range) {
    if (x_range <= 0.1997) {

      zoom <- 12

      xmin <- r@extent[1] - 0.01
      xmax <- r@extent[2] + 0.01
      ymin <- r@extent[3] - 0.01
      ymax <- r@extent[4] + 0.01
    }

    if (x_range <= 0.3894 & x_range > 0.1997) {

      zoom <- 11

      xmin <- r@extent[1] - 0.025
      xmax <- r@extent[2] + 0.025
      ymin <- r@extent[3] - 0.025
      ymax <- r@extent[4] + 0.025
    }

    if(x_range <= 0.7989 & x_range > 0.3894) {

      zoom <- 10

      xmin <- r@extent[1] - 0.04
      xmax <- r@extent[2] + 0.04
      ymin <- r@extent[3] - 0.04
      ymax <- r@extent[4] + 0.04
    }

    if (x_range <= 1.6378 & x_range > 0.7989) {

      zoom <- 9

      xmin <- r@extent[1] - 0.06
      xmax <- r@extent[2] + 0.06
      ymin <- r@extent[3] - 0.06
      ymax <- r@extent[4] + 0.06
    }

    if (x_range <= 3.3556 & x_range > 1.6378) {

      zoom <- 8

      xmin <- r@extent[1] - 0.08
      xmax <- r@extent[2] + 0.08
      ymin <- r@extent[3] - 0.08
      ymax <- r@extent[4] + 0.08
    }

    if (x_range <= 6.8313 & x_range > 3.3556) {

      zoom <- 7

      xmin <- r@extent[1] - 0.1
      xmax <- r@extent[2] + 0.1
      ymin <- r@extent[3] - 0.1
      ymax <- r@extent[4] + 0.1
    }

  } else {
    if(y_range <= 0.1616) {

      zoom <- 12

      xmin <- r@extent[1] - 0.01
      xmax <- r@extent[2] + 0.01
      ymin <- r@extent[3] - 0.01
      ymax <- r@extent[4] + 0.01
    }

    if (y_range <= 0.3135 & y_range > 0.1616) {

      zoom <- 11

      xmin <- r@extent[1] - 0.025
      xmax <- r@extent[2] + 0.025
      ymin <- r@extent[3] - 0.025
      ymax <- r@extent[4] + 0.025
    }

    if (y_range <= 0.647 & y_range > 0.3135) {

      zoom <- 10

      xmin <- r@extent[1] - 0.04
      xmax <- r@extent[2] + 0.04
      ymin <- r@extent[3] - 0.04
      ymax <- r@extent[4] + 0.04
    }

    if (y_range <= 1.3302 & y_range > 0.647) {

      zoom <- 9

      xmin <- r@extent[1] - 0.06
      xmax <- r@extent[2] + 0.06
      ymin <- r@extent[3] - 0.06
      ymax <- r@extent[4] + 0.06
    }

    if (y_range <= 2.7478 & y_range > 1.3302) {

      zoom <- 8

      xmin <- r@extent[1] - 0.08
      xmax <- r@extent[2] + 0.08
      ymin <- r@extent[3] - 0.08
      ymax <- r@extent[4] + 0.08
    }

    if (y_range <= 2.8313 & y_range > 2.7478) {

      zoom <- 7

      xmin <- r@extent[1] - 0.1
      xmax <- r@extent[2] + 0.1
      ymin <- r@extent[3] - 0.1
      ymax <- r@extent[4] + 0.1
    }
  }

  county <- suppressMessages(ggmap::get_map(c(lon_fips,
                                              lat_fips), zoom = zoom,
                                            color = "bw"))

  gg_map <- ggmap::ggmap(county)

  # limits of a ggmap depend on your center lat/lon (this means the limits
  # above won't work exactly for every county)
  map_ymin <- gg_map$data$lat[1]
  map_ymax <- gg_map$data$lat[3]
  map_xmin <- gg_map$data$lon[1]
  map_xmax <- gg_map$data$lon[2]

  if ((ymin < map_ymin) | (ymax > map_ymax) | (xmin < map_xmin) |
     (xmax > map_xmax)) {
    zoom <- zoom - 1
    county <- suppressMessages(ggmap::get_map(c(lon_fips, lat_fips),
                                              zoom = zoom, color = "bw"))
    gg_map <- ggmap::ggmap(county)
  }

  map <- gg_map +
    ggplot2::coord_fixed(xlim = c(xmin, xmax),
                         ylim = c(ymin, ymax)) +
    ggplot2::geom_raster(mapping = ggplot2::aes_(~x, ~y),
                         data = rdf, fill = "yellow",
                         alpha = 0.2,
                         inherit.aes = FALSE,
                         na.rm = TRUE)

  station_df <- daily_data$station_df %>%
    dplyr::tbl_df() %>%
    dplyr::filter_(~ !duplicated(id)) %>%
    dplyr::arrange_(~ dplyr::desc(latitude)) %>%
    dplyr::mutate_(name = ~ factor(name, levels = name))

  if (station_label == TRUE) {
    map_out <- map +
      ggplot2::geom_point(data = station_df,
                          ggplot2::aes_(~ longitude, ~ latitude,
                                        fill = ~ name),
                          colour = "black",
                          size = point_size,
                          shape = 21) +
      ggplot2::ggtitle(title) +
      ggplot2::theme_void()
  } else {
    map_out <- map +
      ggplot2::geom_point(data = station_df,
                          ggplot2::aes_(~ longitude, ~ latitude),
                          colour = point_color,
                          size = point_size) +
      ggplot2::theme_void() +
      ggplot2::ggtitle(title)
  }

  return(map_out)

}
