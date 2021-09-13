library(RPostgres)
library(DBI)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)

#' Title create_medevid_table
#' Create the medevid (medical evidence) table. 
#' 1. keep the usrds_ids also present in the patients table
#' 2. deduplicate by only keeping the first medevid entry for each usrds_id
#' To ensure that we are including a patient’s record associated with their
#' first course of dialysis treatment. 
#' WARNING! do NOT reorder the medevid table until after deduplicating as it 
#' uses the order from USRDS.
#' @param source_dir 
#' @param data_dir 
#' @param filename
#' @param table_name_pt 
#' @param medevid_table_name 
#'
#' @return 
#' @export postgres table medevid
#'
#' @examples
create_medevid_table <- function(source_dir,
                                 data_dir,
                                 filename = "medevid.csv",
                                 table_name_pt="patients",
                                 medevid_table_name="medevid") {
   
   source(file.path(source_dir, "S0-connectToPostgres.R"))
   
   print("import medical evidence table (medevid) from CSV into R")
   # set a few column types that will try to import as non-char and throw errors
   raw_medevid = read_csv(file.path(data_dir, filename), col_types = cols(
      CDTYPE = "c",
      masked_UREADT = "c",
      ALGCON = "c",
      PATNOTINFORMEDREASON = "c",
      RACEC = "c",
      RACE_SUB_CODE = "c"))
   
   names(raw_medevid) = tolower(names(raw_medevid))

   print(
      str_glue(
         "{nrow(raw_medevid)} number of rows raw medevid"))
   print(
      str_glue(
         "{length(unique(raw_medevid$usrds_id))} unique usrds_ids in raw 
         medevid table"))

   # read in patients table to filter IDs
   patients_filtered = dbGetQuery(
      con,
      str_glue(
         "
         SELECT *
         FROM {table_name_pt}
         "))
   # remove unused columns
   # filter on ids from the patient table
   medevid_ids_filtered = raw_medevid %>% 
      select(-c(
                  "como_ihd",
                  "como_mi",
                  "como_cararr",
                  "como_dysrhyt",
                  "como_pericar",
                  "como_diabprim",
                  "como_hiv",
                  "como_aids")) %>%
      filter(usrds_id %in% patients_filtered$usrds_id) 
   
   if (length(unique(medevid_ids_filtered$usrds_id)) != 1150195) {
      print("incorrect number of ids, should be 1150195")
      stop()
   } else {
            print(
            str_glue(
               "after filtering on {table_name_pt} table 
               unique usrds_ids = {length(unique(medevid_ids_filtered$usrds_id))} 
               number of rows = {nrow(medevid_ids_filtered)}
               "))
   }
   
   # keep first row of medevid data if a usrds_id has more than one 
   #per the USRDS Researcher's guide for deduplicating the medevid table
   # calculate the dialysis train time in days 
   
   medevid_filtered = medevid_ids_filtered %>%
      distinct(usrds_id, .keep_all = TRUE) %>%
      mutate(
         masked_trnend = as_date(masked_trnend, origin = "1960-01-01"),
         masked_trstdat = as_date(masked_trstdat, origin = "1960-01-01"),
         
         dial_train_time = as.double(difftime(masked_trnend,
                                              masked_trstdat,
                                              units = "days"))
      )
   
   if (nrow(medevid_filtered) != 1150195) {
      print(
         "incorrect number of ids, should be 1150195"
         )
      stop()
   } else {
      print(str_glue("{
         nrow(medevid_filtered)} number of rows and usrds_ids after filtering 
                     and deduplicating medevid
                     "))
   }
   
   print("save to postgres")

   drop_table_function(con, medevid_table_name) 
   dbCreateTable(
      con,
      name = medevid_table_name,
      fields = medevid_filtered,
      row.names = NULL
   )
   dbWriteTable(
      con,
      name = medevid_table_name,
      value = medevid_filtered,
      row.names = FALSE,
      append = TRUE
   )
}
# Execute function --------------------------------------------------------

data_dir = file.path("data", "")
source_dir = file.path("CreateDataSet")
create_medevid_table(
                     source_dir,
                     data_dir,
                     filename = "medevid.csv",
                     table_name_pt = "patients",
                     medevid_table_name = "medevid")