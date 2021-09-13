library(RPostgres)
library(DBI)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)

#' Title create_patients_table
#' Creates the table patients in the Postgres database, using the .csv files 
#' created in S1a. The patients in our cohort are selected based on
#' 1. age >= 18 years
#' 2. inc_year between 2008-2017
#' 3. first dialysis date is not missing
#' 3. death date is not prior to first dialysis date (one patient fits this condition)
#'
#' @param source_dir
#' @param table_name_pt 
#' @param data_dir
#'
#' @return a dataframe of the filtered patients table according to our cohort 
#' criteria and the created dependent variable.
#' @export postgres table patients
#'
#' @examples create_patients_medevid_table(my_source_dir, my_data_dir, patient_table_name="patients")
#'

create_patients_table <- function(source_dir,
                                  data_dir,
                                  table_name_pt="patients"
) {
   
   source(file.path(source_dir, "S0-connectToPostgres.R"))
   on.exit({
      dbDisconnect(con)
      assign(
         x = "create_patients_medevid_table", rlang::current_env(), rlang::global_env()
      )
   })
   
   print("import patients table from CSV into R")
   patients = read_csv(file.path(data_dir, "patients.csv"), col_types = cols(
      CDTYPE = "c"))
   
   names(patients) = tolower(names(patients))
   fields = names(patients)
   drop_table_function(con, table_name_pt) 
   print(str_glue("create {table_name_pt} in postgres"))
   dbCreateTable(
      con,
      name = table_name_pt,
      fields = patients,
      row.names = NULL
   )
   dbWriteTable(
      con,
      name = table_name_pt,
      value = patients,
      row.names = FALSE,
      append = TRUE
   )
   
   raw_total_pt = dbGetQuery(
      con,
      str_glue(
         "SELECT COUNT(*)
       FROM {table_name_pt}")
   )
   if (raw_total_pt != nrow(patients)) {
      print ("number of rows not equal")
   }
   
   #Get number of rows in PATIENTS at each stage of limiting the cohort
   print(str_glue("{raw_total_pt %>% format(big.mark = ",")
                   } patients in raw patients table"))
   
   ########### exclude null first dialysis date
   exclude_null_firstdial = str_glue(
                              "DELETE FROM {table_name_pt}
                              WHERE masked_firstdial IS NULL"
   )
   dbSendStatement(con, exclude_null_firstdial)
   
   n_non_null_firstdial = dbGetQuery(
      con,
      str_glue(
         "SELECT COUNT(*)
                 FROM {table_name_pt}")
   )
   print(str_glue("number of patients with non null First Dialysis Date {
                   n_non_null_firstdial %>% format(big.mark = ",")
                   }, should be 3096526"))
   
   ########### exclude patients where death is before first dialysis
   exclude_death_after = str_glue(
                              "DELETE FROM {table_name_pt}
                              WHERE masked_died<masked_firstdial"
   )
   dbSendStatement(con, exclude_death_after)
   n_no_death_after = dbGetQuery(
      con,
      str_glue(
         "SELECT COUNT(*)
                 FROM {table_name_pt}")
   )

  
   print(str_glue("number of patients with valid First Dialysis Date,
                   {n_no_death_after %>% format(big.mark = ",")
                   }"))
   if (n_no_death_after != 3096515){
      print("should have 3096515 rows")
      stop()
   }
   
##########exclude minor patients
   exclude_minors = str_glue(
                              "DELETE FROM {table_name_pt}
                              WHERE inc_age < 18")
   dbSendStatement(con, exclude_minors)
   n_adults = dbGetQuery(
      con,
      str_glue(
               "SELECT COUNT(*)
                FROM {table_name_pt}"))
   
   print(str_glue("number of adult patients with valid First Dialysis Date,
                   {n_adults %>% format(big.mark = ",")
                   }"))
   if (n_adults != 3065026){
      print("should have 3065026 rows")
      stop()
   } 
   
   ########### filter on cohort years 2008-2017
   exclude_years = str_glue(
                              "DELETE FROM {table_name_pt}
                              WHERE incyear>2017
                              OR incyear<2008"
   )
   dbSendStatement(con, exclude_years)

   

   # to do this cohort creation in all one step, run the following sql query
   # exclude_patients = str_glue(
   #                            "DELETE FROM {table_name_pt}
   #                            WHERE inc_age<18
   #                            OR incyear>2017
   #                            OR incyear<2008
   #                            OR masked_firstdial IS NULL
   #                            OR masked_died<masked_firstdial"
   # )
   # dbSendStatement(con, exclude_patients)
   
   patients_filtered = dbGetQuery(
      con,
      str_glue(
         "SELECT *
         FROM {table_name_pt}"))
   
   cohort_total_pt = nrow(patients_filtered)
   
   if (cohort_total_pt!=1150195){
      print(str_glue("WARNING! the number of patients {
                  cohort_total_pt %>% format(big.mark = ",")
                  } does not equal 1150195 which is what the total patients 
                     should be for the cohort"))
      stop()
   }
   print(str_glue("number of adult patients with valid First Dialysis Date 
                  in our cohort of incident year between 2008-2017 (inclusive),
                   {cohort_total_pt %>% format(big.mark = ",")
                   }, should be 1150195"))
   
   patients_dependent_var = create_dependent_var(patients_filtered)

   print(str_glue("patients = {nrow(patients_dependent_var)} at create 
                  dependent variable"))
   if (nrow(patients_dependent_var) != 1150195){
      print("should be 1150195 rows")
      stop() 
   }
   
   drop_table_function(con, table_name_pt) 
   dbCreateTable(
      con,
      name = table_name_pt,
      fields = patients_dependent_var,
      row.names = NULL
   )
   dbWriteTable(
      con,
      name = table_name_pt,
      value = patients_dependent_var,
      row.names = FALSE,
      append = TRUE
   )
}

#' Title create_dependent_var
#'  Create dependent variable died_in_90 of patients who did/not survive 90 days
#'  after the first dialysis date (masked_firstdial). 
#'  Some features are converted to dates to calc the date math for the 
#'  days_on_dial feature and the dependent variable. 
#' @param patients_df 
#'
#' @return pat, a data frame the has the dependent variable (died_in_90) included
#' @export none
#'
#' @examples create_dependent_var(patients_data_frame)
create_dependent_var <- function(patients_df){
   pat = patients_df %>%
      mutate(inc_age=ifelse(inc_age>90, 90, inc_age),
            masked_firstdial = as_date(masked_firstdial, origin = "1960-01-01"),
             
             masked_died = as_date(masked_died, origin = "1960-01-01"),
             
             days_on_dial = as.double(difftime(masked_died,
                                               masked_firstdial,
                                               units = "days")),
             
             died_in_90 = ifelse(is.na(days_on_dial), 0, ifelse(days_on_dial <= 90, 1, 0)),
             
             # convert data vars to dates that are used to calculate waitlist and transplant status
             # in S1c-txWaitlist.R
             masked_first_se = as_date(masked_first_se, origin = "1960-01-01"),
             
             #can_first_listing_dt = First date patient is ever waitlisted
             masked_can_first_listing_dt = as_date(masked_can_first_listing_dt, origin = "1960-01-01"),
            
             #can_rem_dt = Date patient was removed from the waitlist the first time
             masked_can_rem_dt = as_date(masked_can_rem_dt, origin = "1960-01-01"),
             masked_tx1date = as_date(masked_tx1date, origin = "1960-01-01"),
             masked_tx1fail = as_date(masked_tx1fail, origin = "1960-01-01")
)
   return(pat)
}

# Execute functions --------------------------------------------------------
data_dir = file.path("data", "")
source_dir = file.path("CreateDataSet")
create_patients_table(
   source_dir,
   data_dir,
   table_name_pt = "patients")