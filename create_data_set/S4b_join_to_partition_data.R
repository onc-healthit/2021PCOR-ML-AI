library(tidyr)
library(RPostgres)
library(DBI)
library(stringr)
source_dir = file.path("CreateDataSet")
source(file.path(source_dir, "S0-connectToPostgres.R"))

#Join the `preesrdfeatures` table to our partitioned IDs. 
#Adds a column **subset** to the input dataframe.

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
data_tbl = "preesrdfeatures"

join_data_partitions(
  con,
  data_tablename = data_tbl,
  num_partitions = 10
)