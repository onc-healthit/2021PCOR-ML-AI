library(RPostgres)
library(DBI)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)

#' Title join_patients_medevid
#' this function will join the medevid and patients tables
#' We should have 1,150,195 rows/patients in the dataframe returned, 
#' the same number in filtered patients after selecting the cohort.
#' Duplicate columns are kept from patients, 
#' except missing sex or pdis values in patients are replaced with medevid values
#' @param source_dir 
#' @param table_name_pt
#' @param medevid_table_name
#' @param joined_table_name
#'
#' @return 
#' @export patients_medevid, a dataframe of the merged patients and medevid tables 
#' after they have been pre-processed
#'
#' @examples
join_patients_medevid <- function(source_dir,
                                  table_name_pt = "patients",
                                  medevid_table_name = "medevid",
                                  joined_table_name = "patients_medevid") {
   
   source(file.path(source_dir, "S0-connectToPostgres.R"))
   on.exit({
      dbDisconnect(con)
   })
   
   patients_filtered = dbGetQuery(
      con,
      str_glue(
         "
         SELECT *
         FROM {table_name_pt}
         "))
   
   medevid_filtered = dbGetQuery(
      con,
      str_glue(
              "
              SELECT *
              FROM {medevid_table_name}
              ")) 

   
   
   #sex and pdis from medevid, rename and recode to bring over and 
   # populate missing vals in patients
   medevid_filtered =  medevid_filtered %>% 
      mutate(
         sex_med = ifelse(
            sex == "M", 1, 
               ifelse(sex == "F", 2, 3)),
         pdis_med = pdis
         )

   #Remove cols in medevid that are also in patients, and left join on patients
   # note that we don't keep the cdtype col from patients, as it comes in with all null values
   
   pt_med_merge = left_join(
      patients_filtered %>% select(-c( "cdtype")),
      medevid_filtered %>% select(-c("randomoffsetindays", "disgrpc", "network", "inc_age",
                                     "pdis", "sex", "race", "masked_died")),
      by = "usrds_id"
   )
   
   pt_med_merge = pt_med_merge %>%
         mutate( 
            sex = ifelse(is.na(sex), sex_med, sex),
            pdis = ifelse(is.na(pdis), pdis_med, pdis)
            ) %>%
         select(-c(sex_med, pdis_med))
   
   #save to postgres
   drop_table_function(con, joined_table_name)
   dbCreateTable(
      con,
      name = joined_table_name,
      fields = pt_med_merge,
      row.names = NULL
   )
   dbWriteTable(
      con,
      name = joined_table_name,
      value = pt_med_merge,
      row.names = FALSE,
      append = TRUE
   )
   
   if (nrow(pt_med_merge)!=1150195){
      print(
         str_glue(
            "WARNING! the number of patients {nrow(pt_med_merge)}
            does not equal 1150195"))
      stop()
   } 
   else {
      print(
         str_glue(
            "total patients/rows = {nrow(pt_med_merge)}"))
   }
}

# Execute functions --------------------------------------------------------
data_dir = file.path("data", "")
source_dir = file.path("CreateDataSet")

join_patients_medevid(
   source_dir,
   table_name_pt = "patients",
   medevid_table_name = "medevid",
   joined_table_name = "patients_medevid")