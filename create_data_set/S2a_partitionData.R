library(dplyr)
library(magrittr)
library(tidyr)
library(RPostgres)
library(DBI)
library(stringr)
source_dir = file.path("CreateDataSet")
source(file.path(source_dir, "S0-connectToPostgres.R"))

#Partition on USRDS_ID into 10 non-intersecting subsets, 
#for purposes of managing performance and reproducibility in test/train/val split

partition_data <- function(con,
                           usrds_id,
                           num_partitions, 
                           data_tablename, 
                           seed_value) {

  set.seed(2539)

  randvalue = runif(
    length(usrds_id), 
    min = 0, 
    max = num_partitions
    )
  
  universe = cbind(
    usrds_id, 
    floor(randvalue)) %>% 
    
    as.data.frame()
  
  names(universe) = c("usrds_id", "subset")
  
  tblname = str_glue("partition_{num_partitions}")
  drop_table_function(con, tblname)
  dbWriteTable(
    con,
    tblname,
    universe,
    append = FALSE,
    row.names = FALSE
    )
  rm(universe, randvalue)
}

# Execute function --------------------------------------------------------
data_tbl = "patients_medevid_waitlist"

usrds_id = dbGetQuery(
  con,
  str_glue(
    "
    SELECT usrds_id 
    FROM {data_tbl}
    ORDER BY usrds_id
    "))
usrds_id = usrds_id$usrds_id

partition_data(
                con, 
                usrds_id,
                num_partitions = 10,
                data_tablename = data_tbl
              )