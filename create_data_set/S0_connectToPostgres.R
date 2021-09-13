library(RPostgres)
library(DBI)
## --able to run
#' Creates a connection to a postgresql database.
#' @param Name of the database database port, user name, and user password
#'
#' @return An object called con that can be used in database queries.
#' @examples \code{con = getConnection()}
#' dbname for master is postgres, for testing it is test_code_usrds
#'
#'
getConnection = function() {
  con = dbConnect(
    RPostgres::Postgres(),
    dbname =  'my_database_name_in_postgres',
    host = 'my_connection_for_postgres',
    port = '5432',
    user = 'my_username_for_postgres',
    password = 'my_password_for_postgres'
  )
  
  return(con)
}

# drop table Function definition -----------------------------------------------------
#' Title drop_table_funcion
#' Checks to see if the table exists, if it does, it is dropped.
#' @param tablename
#' @export a dropped table from postgres database
#'
#' @examples \code{drop_table_function(con, "patients")}
#'
drop_table_function <- function(con, tablename) {
  if (isTRUE(dbExistsTable(con, tablename)))   {
    print(str_glue("existing {tablename} table dropped"))
    dbRemoveTable(con, tablename)
  }
  else {
    print(str_glue("{tablename} table does not exist"))
  }
}

# Execute function --------------------------------------------------------
con = getConnection()