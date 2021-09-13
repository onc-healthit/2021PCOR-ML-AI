library(readr)
library(dplyr)
library(magrittr)
library(lubridate)
library(RPostgres)
library(DBI)
library(stringr)

#This script investigates and creates the `waitseq_ki`, `waitseq_kp`, `tx`, `tx_waitlist_vars` 
#and `patients_medevid_waitlist` tables in the postgres database from the .csv 
#files and the `patients_medevid` table.
#The result is the calculation of the variables added to the data to create the 
#`patients_medevid_waitlist` table.
# days_on_waitlist (number of days in transplant waitlist
#        waitlist_status (active, transplanted, removed, never)
#  - Input: Postgresql table `patients_medevid`, tx.csv, waitseq_kp.csv, waitseq_ki.csv
#files produced in script S1a-convertSAStoCSV.R
#  - Output: New postgresql tables `waitseq_ki`, `waitseq_kp`, `tx`, 
# `tx_waitlist_vars` and 
# `patients_medevid_waitlist` (this is the full dataset that should be used going forward). 


data_dir = file.path("data", "")
source_dir = file.path("CreateDataSet")
source(file.path(source_dir, "S0-connectToPostgres.R"))

#####LOAD PATIENT DATA####
pat = dbGetQuery(con,
                      "SELECT *
                      FROM patients_medevid")
####WAITSEQ_KI PRE-PROCESSING####
#WS_LIST_DT = New Waiting Period Starting Date
#WS_END_DT = New Waiting Period Ending Date
#PROVUSRD = USRDS Assigned Facility ID

#Read in WAITSEQ_KI
waitseq_ki = read_csv(file.path(data_dir,"waitseq_ki.csv"), col_types = cols(
    USRDS_ID = col_double(),
    randomOffsetInDays = col_double(),
    PROVUSRD = col_double(),
    PID = col_double(),
    masked_BEGIN = col_double(),
    masked_ENDING = col_double()
  ))
  
names(waitseq_ki) = tolower(names(waitseq_ki))

#Only keep rows with USRDS_ID in cohort
waitseq_ki = waitseq_ki %>%
  filter(usrds_id %in% pat$usrds_id) %>%
  mutate(ws_list_dt = as_date(masked_begin, origin = "1960-01-01"),
         ws_end_dt = as_date(masked_ending, origin = "1960-01-01"),
         source = "ki") %>%
  select(usrds_id, pid, provusrd, ws_list_dt, ws_end_dt, source)

#save to postgres
fields = names(waitseq_ki)
drop_table_function(con, "waitseq_ki") 
print(str_glue("create waitseq_ki in postgres"))
dbCreateTable(
  con,
  name = "waitseq_ki",
  fields = waitseq_ki,
  row.names = NULL
)
dbWriteTable(
  con,
  name = "waitseq_ki",
  value = waitseq_ki,
  row.names = FALSE,
  append = TRUE
)
####WAITSEQ_KP PRE-PROCESSING####
#WS_LIST_DT = New Waiting Period Starting Date
#WS_END_DT = New Waiting Period Ending Date
#PROVUSRD = USRDS Assigned Facility ID

#Read in WAITSEQ_KP
waitseq_kp = read_csv(file.path(data_dir,"waitseq_kp.csv"), col_types = cols(
  USRDS_ID = col_double(),
  randomOffsetInDays = col_double(),
  PROVUSRD = col_double(),
  PID = col_double(),
  masked_BEGIN = col_double(),
  masked_ENDING = col_double()
))
names(waitseq_kp) = tolower(names(waitseq_kp))

#Only keep rows with USRDS_ID that's in refined patients cohort
waitseq_kp = waitseq_kp %>%
  filter(usrds_id %in% pat$usrds_id) %>%
  mutate(ws_list_dt = as_date(masked_begin, origin = "1960-01-01"),
         ws_end_dt = as_date(masked_ending, origin = "1960-01-01"),
         source = "kp") %>%
  select(usrds_id, pid, provusrd, ws_list_dt, ws_end_dt, source)

#save to postgres
fields = names(waitseq_kp)
drop_table_function(con, "waitseq_kp") 
print(str_glue("create waitseq_kp in postgres"))
dbCreateTable(
  con,
  name = "waitseq_kp",
  fields = waitseq_kp,
  row.names = NULL
)
dbWriteTable(
  con,
  name = "waitseq_kp",
  value = waitseq_kp,
  row.names = FALSE,
  append = TRUE
)
####ROW BIND WAITSEQ_KI AND WAITSEQ_KP TOGETHER####
waitseq = bind_rows(waitseq_ki, waitseq_kp) %>%
  arrange(usrds_id, ws_list_dt)

####LEFT JOIN PATIENTS AND WAITSEQ####
pat_waitseq = left_join(
  pat %>% select(usrds_id, masked_first_se, masked_firstdial,
                 masked_can_first_listing_dt, masked_can_rem_dt,
                 masked_tx1date, masked_died, can_rem_cd, masked_tx1fail),
  waitseq,
  by = "usrds_id") %>%
  arrange(usrds_id, ws_list_dt)

###########################################
#Get number of rows in pat_waitseq where can_first_listing_date is not missing
nrow(pat_waitseq %>% filter(!is.na(masked_can_first_listing_dt)))
# 243,580

#Get number of rows in pat_waitseq where ws_list_date is not missing
nrow(pat_waitseq %>% filter(!is.na(ws_list_dt)))
# 243,575
### Why aren't those numbers the same??

#Look at the 5 rows that are different
setdiff(pat_waitseq %>% filter(!is.na(masked_can_first_listing_dt)),
        pat_waitseq %>% filter(!is.na(ws_list_dt)))
# They're patients who have rem_code = "listed in error" or list_date = list_end_date
# Both are reasons they've been removed from the waitseq files

####ACTIVE ON WAITLIST####
#If list_date is before dial_date and end_date is on or after dial_date:
# status is ACTIVE ON FIRST DAY OF DIALYSIS

#First, check if earliest listing date from waitseq matches first listing date from pat
first_list = pat_waitseq %>% group_by(usrds_id) %>%
  arrange(usrds_id, ws_list_dt) %>%
  distinct(usrds_id, .keep_all = TRUE) %>%
  ungroup(usrds_id)

#Get number of rows where patients listing date != waitseq listing date
nrow(first_list %>% filter(masked_can_first_listing_dt != ws_list_dt))
# 20 rows, but all have rem_code = 10 --> Candidate listed in error, so we can ignore them

#If list_date is before dial_date and end_date is on or after dial_date,
# OR if list_dt < dial_dt and end_dt == NA:
# status is ACTIVE ON FIRST DAY OF DIALYSIS
pat_waitseq = pat_waitseq %>%
  mutate(active = ifelse(
    (ws_list_dt < masked_firstdial & ws_end_dt >= masked_firstdial) | (ws_list_dt < masked_firstdial & is.na(ws_end_dt)), 1, 0))

num_active = sum(pat_waitseq$active == 1, na.rm = TRUE)

active = pat_waitseq %>%
  filter((ws_list_dt < masked_firstdial & ws_end_dt >= masked_firstdial) | (ws_list_dt < masked_firstdial & is.na(ws_end_dt)))

if (num_active != nrow(active)) {
  print("problem calc active rows, should be 49,924")
}

### Days on waitlist for ACTIVE ppl is dial_dt - ws_list_dt ###
active = active %>%
  mutate(
    days_on_waitlist = as.double(difftime(masked_firstdial,
                                          ws_list_dt,
                                          units = "days"))
  )

#Then sort by USRDS_ID and WS_LIST_DT and keep row w/ EARLIEST WS_LIST_DT
active = active %>% group_by(usrds_id) %>%
  arrange(usrds_id, ws_list_dt) %>%
  distinct(usrds_id, .keep_all = TRUE) %>%
  ungroup(usrds_id)

### REMOVE ROWS FROM PAT_WAITSEQ WHERE USRDS_ID IS IN ACTIVE ###

#Get unique usrds_id's in active dataframe
active_id = unique(active$usrds_id)

#Filter out rows from pat_waitseq where usrds_id is in active_id
pat_waitseq_not_act = pat_waitseq %>%
  filter(!usrds_id %in% active_id)

####TX PRE-PROCESSING####
#T_TX_DT = transplant date, 
#YEAR = year of transplant, 
#T_FAIL_DT = Transplant Failure Date
#PROVUSRD = USRDS Assigned Facility ID, 
#TX_SRCE = Source of Transplant Record
#TOTTX = Patient Total Number of TXs

#Read in TX dataset
tx = read_csv(file.path(data_dir,"tx.csv"), col_types = cols(
  DHISP = "c",
  DSEX = "c",
  RHISP = "c",
  RSEX = "c"
))

names(tx) = tolower(names(tx))

tx = tx %>%
  filter(usrds_id %in% pat$usrds_id) %>%
  mutate(t_tx_dt = as_date(masked_tdate, origin = "1960-01-01"),
         t_fail_dt = as_date(masked_faildate, origin = "1960-01-01")) %>%
  select(usrds_id, provusrd, t_tx_dt, t_fail_dt, tottx, tx_srce) %>%
  arrange(usrds_id, t_tx_dt)

#save to postgres
fields = names(tx)
drop_table_function(con, "tx") 
print(str_glue("create tx in postgres"))
dbCreateTable(
  con,
  name = "tx",
  fields = tx,
  row.names = NULL
)
dbWriteTable(
  con,
  name = "tx",
  value = tx,
  row.names = FALSE,
  append = TRUE
)
################################
### Subset rows where LISTING DATE and LIST END DATE are both BEFORE DIAL START DATE ###
# STEP 1. Subset rows with ws_list_dt & ws_end_date BEFORE pat first dial date
list_before_dial = pat_waitseq_not_act %>%
  filter(ws_list_dt < masked_firstdial & ws_end_dt < masked_firstdial)

# STEP 2. Group by usrds_id, sort by largest to smallest end_date, and keep max(end_date) for each usrds_id
closest_end_dt_to_dial = list_before_dial %>% group_by(usrds_id) %>%
  arrange(usrds_id, desc(ws_end_dt)) %>%
  distinct(usrds_id, .keep_all = TRUE) %>%
  ungroup(usrds_id)

#Left join CLOSEST_END_DT_TO_DIAL and TX on USRDS_ID
# This has effect of filtering TX dataset and keeping rows
# where USRDS_ID is in CLOSEST_END_DT_TO_DIAL
max_end_dt = left_join(
  closest_end_dt_to_dial %>% select(-pid, -provusrd),
  tx %>% select(usrds_id, t_tx_dt, t_fail_dt),
  by = "usrds_id"
)

max_end_dt = max_end_dt %>%
  mutate(transplanted = if_else(is.na(t_tx_dt), 0,
                                if_else(ws_end_dt == t_tx_dt, 1, 0))) 

#Check how many rows have transplanted = 1
transplated_rows = sum(max_end_dt$transplanted == 1, na.rm = TRUE)

transplanted = max_end_dt %>%
  filter(ws_end_dt == t_tx_dt)
  
if (nrow(transplanted) != transplated_rows) {
    print("transplated rows should be 1186 incorrect see 'max_end_dt'")
  }

###Days on waitlist for TRANSPLANTED ppl is t_tx_dt - ws_list_dt####
transplanted = transplanted %>%
  mutate(
    days_on_waitlist = as.double(difftime(t_tx_dt,
                                          ws_list_dt,
                                          units = "days"))
  )

###Remove rows from MAX_END_DT where USRDS_ID is in TRANSPLANTED####
#Get unique usrds_id's in transplanted dataframe
transplanted_id = unique(transplanted$usrds_id)

#Filter out rows from MAX_END_DT where USRDS_ID is in TRANSPLANTED_ID
no_act_or_trans = max_end_dt %>%
  filter(!usrds_id %in% transplanted_id)

###EVERONE LEFT IN NO_ACT_OR_TRANS SHOULD HAVE REMOVED STATUS####
#Check that all rows meet the removed criteria
num_no_act_tx = nrow(no_act_or_trans %>%
       filter(ws_end_dt != t_tx_dt | is.na(t_tx_dt)))

## Create REMOVED col and set REMOVED = 1 if WS_END_DT != T_TX_DT or T_TX_DT = NA
no_act_or_trans = no_act_or_trans %>%
  mutate(removed = if_else(ws_end_dt != t_tx_dt | is.na(t_tx_dt), 1, 0))

num_removed = sum(no_act_or_trans$removed == 1, na.rm = TRUE)

if (num_no_act_tx != num_removed){
  print("number of patients in Removed col=1 does not equal number calculated 
        for 'no active or transplanted' status. both should equal 1490")
}

removed = no_act_or_trans %>%
  filter(ws_end_dt != t_tx_dt | is.na(t_tx_dt))

if (nrow(removed) != num_removed){
  print("number of patients in Removed col=1 does not equal number calculated 
        for 'no active or transplanted' status. both should equal 1490")
}

### Days on waitlist for REMOVED ppl is ws_end_dt - ws_list_dt ###
removed = removed %>%
  mutate(
    days_on_waitlist = as.double(difftime(ws_end_dt,
                                          ws_list_dt,
                                          units = "days"))
  )
#REMOVED only has dupes cuz TX has multiple rows, but the waitseq start and end dates are
# the same for both rows of each USRDS_ID, so we can just keep the first
removed = removed %>% group_by(usrds_id) %>%
  arrange(usrds_id, ws_list_dt) %>%
  distinct(usrds_id, .keep_all = TRUE) %>%
  ungroup(usrds_id)

#Get unique usrds_ids in removed dataframe
removed_id = unique(removed$usrds_id)

###ROW BIND DAYS_ON_WAITLIST####
#with usrds_id from active, transplanted, and removed ###
days = bind_rows(active %>% select(usrds_id, days_on_waitlist),
                 transplanted %>% select(usrds_id, days_on_waitlist),
                 removed %>% select(usrds_id, days_on_waitlist))
days = days %>% arrange(usrds_id)

###ADD ACTIVE TO MAIN PAT DATASET#### 
#Set all rows in pat where usrds_id is in active_id to ACTIVE = 1
pat = pat %>%
  mutate(active = if_else(usrds_id %in% active_id, 1, 0)) %>%
  select(usrds_id, active, masked_first_se, masked_firstdial, masked_can_first_listing_dt,
         masked_can_rem_dt, masked_tx1date, masked_died, can_rem_cd, masked_tx1fail)

### ADD TRANSPLANTED TO MAIN PAT DATASET ###
#Set all rows in pat where USRDS_ID is in transplanted_id to TRANSPLANTED = 1
pat = pat %>%
  mutate(transplanted = if_else(usrds_id %in% transplanted_id, 1, 0))

n_both = nrow(pat %>% filter(active == 1 & transplanted == 1))
if (n_both!=0){
  print("WARNING! rows exist where active and transplanted are both == 1")
}

### ADD REMOVED TO MAIN PAT DATASET ###
#Set all rows in pat where usrds_id is in removed_id to REMOVED = 1
pat = pat %>%
  mutate(removed = if_else(usrds_id %in% removed_id, 1, 0))

#Check that no rows have more than one 1 across active, transplanted, and removed
pat %>%
  rowwise() %>%
  filter((sum(active, transplanted, removed, na.rm = TRUE) > 1)) %>%
  tally()
# A tibble: 0 x 1 
# … with 1 variable: n <int>
#Returns 0 so we have no rows marked with more than one status. Good!

if (apply(pat %>% select(active), 2, function(x) sum(is.na(x)))!=0){
  print("WARNING! NaN present in 'active")
}
if (apply(pat %>% select(transplanted), 2, function(x) sum(is.na(x)))!=0){
  print("WARNING! NaN present in 'transplanted")
}
if (apply(pat %>% select(removed), 2, function(x) sum(is.na(x)))!=0){
  print("WARNING! NaN present in 'removed")
}

###FINAL STATUS: NEVER ON WAITLIST####

#Set all rows where active, transplanted, and removed are all 0 to NEVER = 1
pat = pat %>%
  mutate(never = if_else(active == 0 & transplanted == 0 & removed == 0, 1, 0))

#Check that no rows have more than one 1 across active, transplanted, removed, & never
pat %>%
  rowwise() %>%
  filter((sum(active, transplanted, removed, never, na.rm = TRUE) > 1)) %>%
  tally()
#Returns 0 so we have no rows marked with more than one status.

if (sum(pat %>% tally(active == 1),
    pat %>% tally(transplanted == 1),
    pat %>% tally(removed == 1),
    pat %>% tally(never == 1)) != nrow(pat)){
  
  print("sum of the number of rows where each status == 1 DOES NOT sum to number of rows in patients")
}

###TIME ON TX WAITLIST####
#Join DAYS_ON_WAITLIST onto PAT
pat = left_join(
  pat,
  days,
  by = "usrds_id"
)

library(tidyr)
#When NEVER == 0, set DAYS_ON_WAITLIST = 0
pat = pat %>%
  mutate(days_on_waitlist = replace_na(days_on_waitlist, 0))

#Check that no rows have more than one 1 across active, transplanted, removed, & never
pat %>%
  rowwise() %>%
  filter((sum(active, transplanted, removed, never, na.rm = TRUE) > 1)) %>%
  tally()
#Returns 0 so we have no rows marked with more than one status.

if (nrow(pat %>% filter(days_on_waitlist != 0 & never == 1)) != 0) {
  print("Warning! existing rows with non-zero days_on_waitlist but never == 1.
        NOTE: THIS IS POSSIBLE IF SOMEONE WAS ONLY ON THE LIST FOR A DAY")
}

#####Reshape#######
#into long form with one WAITLIST_STATUS variable
pat2 = pat %>%
  mutate(waitlist_status = names(
    pat %>% select(
      active, transplanted, removed,never))[
        max.col(pat %>% select(active, transplanted, removed, never))])

#Check for rows where waitlist_status value doesn't match the 1's in binary status cols
nrow(pat2 %>% filter(waitlist_status == "never" & never != 1))
#Running above line with each status all return 0 rows so we're good

####SAVE WAITLIST VARS TO CSV AND POSTGRES####
tx_waitlist_vars = pat2 %>%
  select(usrds_id, waitlist_status, days_on_waitlist) %>%
  arrange(usrds_id)

csv_path = str_glue("{data_dir}tx_waitlist_vars.csv")
write_csv(tx_waitlist_vars,csv_path)
drop_table_function(con, "tx_waitlist_vars")
dbWriteTable(
  con, 
  name = "tx_waitlist_vars", 
  value = tx_waitlist_vars, 
  row.names = FALSE, 
  append = TRUE)


####Merge with patients_medevid and save to postgres####
# add the waitlist and transplant features to the table of patient and medevid features
patients_med = dbGetQuery(con,
                 "SELECT *
                  FROM patients_medevid")

patients_med_waitlist = inner_join(
  patients_med,
  tx_waitlist_vars,
  by="usrds_id"
)
fields = names(patients_med_waitlist)
print(str_glue("create patients_medevid_waitlist in postgres"))
drop_table_function(con, "patients_medevid_waitlist") 
dbCreateTable(
  con,
  name = "patients_medevid_waitlist",
  fields = patients_med_waitlist,
  row.names = NULL
)
dbWriteTable(
  con,
  name = "patients_medevid_waitlist",
  value = patients_med_waitlist,
  row.names = FALSE,
  append = TRUE
)