library(readr)
library(haven)
library(dplyr)
library(magrittr)
library(stringr)
library(RPostgres)
library(DBI)
source('CreateDataSet/S0-connectToPostgres.R')
source('CreateDataSet/create_claim_table.R')
data_dir = file.path("data")

#extract, filter, and store pre ESRD Claims tables from 2011-2017
#- Input: 
#create_claim_table.R
#pre_esrd_ip_claim_variables.R
#pre_esrd_hh_claim_variables.R
#pre_esrd_hs_claim_variables.R
#pre_esrd_op_claim_variables.R
#pre_esrd_sn_claim_variables.R

#- Output: The postgresql tables 
#preesrd5y_ip_clm_inc
#preesrd5y_hh_clm_inc
#preesrd5y_hs_clm_inc
#preesrd5y_op_clm_inc
#preesrd5y_sn_clm_inc

claim_types = c(
  "ip",
  "hs",
  "hh",
  "op",
  "sn"
)
for (typ in claim_types) {
  # load fieldnames specific to claim type
  source(str_glue("CreateDataSet/pre_esrd_{typ}_claim_variables.R"))
  
  create_claim_table(
    data_dir, 
    con, 
    filenames_esrd, 
    fieldnames_esrd, 
    columns_esrd, 
    columns_esrd_2015, 
    table_name_pt='patients_medevid_waitlist'
    )
  
  rm(filenames_esrd, fieldnames_esrd, columns_esrd, columns_esrd_2015)
}