library(tidyr)
library(RPostgres)
library(DBI)
library(stringr)
source_dir = file.path("CreateDataSet")
source(file.path(source_dir, "S0-connectToPostgres.R"))

#Join any table (in our case we do this for both the `patients_medevid_waitlist`
# and the `preesrdfeatures`) to our partitioned IDs. 
# Adds a column **subset** (the partition index) to the input dataframe.
join_data_partitions <- function(con, 
                                 data_tablename="patients_medevid_waitlist", 
                                 num_partitions=10){
  
  dbSendStatement(con, str_glue(
    "
     ALTER TABLE {data_tablename} 
     ADD subset integer
     "), n = -1)
  
  dbSendStatement(
    con, 
    str_glue(
      "
        UPDATE {data_tablename} d
        SET subset = p.subset
        FROM partition_{num_partitions} p
        WHERE d.usrds_id = p.usrds_id
        "), n = -1)
}

# execute function --------------------------------------------------------
#data_tbl = "patients_medevid_waitlist"
data_tbl = "preesrdfeatures"

join_data_partitions(
  con,
  data_tablename = data_tbl,
  num_partitions = 10
)