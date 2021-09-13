library(dplyr)
library(magrittr)
library(tidyr)
library(plyr)
library(sqldf)
library(RPostgres)
library(DBI)
library(stringr)
library(readxl)


# Script for creating `medxpreesrd`. Uses the full dataset `patients_medevid_waitlist` and  `preesrdfeatures` to construct the table `medxpreesrd` 
# 
# - creates binary variables to indicate whether imputed values are missing or out of bounds for a given patient
# - encodes character values to numeric
# - count the number of value types for como_* columns
# - incorporates pdis_recode column
# - deletes features not used for modeling
# 
# - Input: `patients_medevid_waitlist`, `preesrdfeatures`, `pdis_recode_map`, `dxmap`, imputation_rules.xlsx
# - Output: `medxpreesrd`	

source(file.path("CreateDataSet","S0-connectToPostgres.R"))
source_dir = file.path("CreateDataSet","")

main_data = "patients_medevid_waitlist"
medex_tblname = "medxpreesrd"
table_preesrd = "preesrdfeatures"

valueExceptions = function(df, vars) {
  #For each variable in the list "vars", introduce a binary variable for whether the variable
  #is NA (which means "missing") and a separate binary variable for whether it is out of bounds
  #(that is, not missing but below the clinically plausible min or above the clinically plausible max )
  bounds = read_excel(str_glue("{source_dir}imputation_rules.xlsx"), sheet =
                        "Bounds") %>% as.data.frame()
  isnavars = c()
  for (v in vars) {
    newv = str_glue("wasna_{v}")
    df[, newv] = as.integer(is.na(df[, v]))
    isnavars = c(isnavars, newv)
  }
  outofbndsvars = c()
  for (v in vars) {
    newv = str_glue("outofbnds_{v}")
    df[, newv] = as.integer(!is.na(df[, v]) &
                              !(df[, v] >= bounds[1, v] &
                                  df[, v] <= bounds[2, v]))
    #sum(as.integer(!is.na(df[,v]) & !(df[,v]>=bounds[1,v] & df[,v]<=bounds[2,v])))
    #The sum checks for reasonableness of the count, to guard against typos
    outofbndsvars = c(outofbndsvars, newv)
  }
  #returns a data frame with usrds_id (the key field) and binary values to indicate whether or not
  #each column in "vars" is NA
  return(df[, c("usrds_id", isnavars, outofbndsvars)])
}
setOutOfBoundsToNA=function(df,vars) {
  for (v in vars) {
    df[,v]=ifelse(
      df[,paste0("outofbnds_",v)] == 1,
      NA,
      df[,v])
  }
  return(df)
}
recodePdis = function(df, con) {
  #pdis must be encoded as a number prior to training by gradient-boosting
  df$pdis = df$pdis %>% 
    trimws() %>% str_pad(.,
                         width = 7,
                         side = "right",
                         pad = "0") #Format pdis with
  #same padding as in pdis_recode_map
  print("get map")
  pdis_map = dbGetQuery(
    con, "
    SELECT pdis, cdtype, pdis_recode
    FROM pdis_recode_map") 
  print("summary")
  pdis_map = pdis_map %>% 
    group_by(pdis, cdtype) %>% 
    dplyr::summarise(pdis_recode = min(pdis_recode))
  print("join")
  df = df %>% 
    left_join(
      pdis_map, 
      by = c("cdtype", "pdis")) %>% 
    mutate(
      pdis_recode = ifelse(is.na(pdis_recode), 9999, pdis_recode)
      )
  
  return(df)
}

replaceCharacterVals = function(dx, 
                                vars,
                                sourceValue = c("N", "Y", "M", "F", "U", "C", "X", "D", "I", "A", "R"),
                                sinkValue = c("2", "1", "12", "13", "9", "15", "16", "17", "18", "20", "21"))
{
  #XGBoost wants numeric values instead of characters or factors
  #xgboost requires numeric columns (null values are OK, but the column must be numeric)
  #The function 'replaceCharacterVals' ensures that character values are replaced with a number
  for (v in vars) {
    print(v)
    dx[, v] = mapvalues(pull(dx, v), sourceValue, sinkValue)
    dx[, v] = as.integer(pull(dx, v))
  }
  return(dx)
}
getCategoryVars <- function(dataset){
  pattern1 = "^MEDCOV|^PATTXOP|^PATINFORMED$|^DIET|^NEPHCARE|^EPO" %>% tolower()
  pattern2 = "^DIAL|^TYPTRN|^AVGMATURING|^AVFMATURING" %>% tolower()
  pattern3 = "^ACCESSTYPE|^TRCERT|^CDTYPE" %>% tolower()
  pattern4 = "^EMPCUR|^EMPPREV|^pdis$|^hispanic$|^COMO_" %>% tolower()
  categoryVars = names(dataset)[grepl(pattern1, names(dataset))]
  categoryVars = union(categoryVars, names(dataset)[grepl(pattern2, names(dataset))])
  categoryVars = union(categoryVars, names(dataset)[grepl(pattern3, names(dataset))])
  categoryVars = union(categoryVars, names(dataset)[grepl(pattern4, names(dataset))])
  return(categoryVars)
}
getContinuousVars <- function(dataset){
  pattern_continuous = "^GFR_EPI|^SERCR|^ALBUM|^HEGLB|^HBA1C|^BMI$|^HEIGHT|^WEIGHT" %>% tolower()
  continuousVars = names(dataset)[grepl(pattern_continuous, names(dataset))]
  return(continuousVars)
}
getNonNumericCols = function(dx) {
  cols = c()
  for (v in names(dx)) {
    if (!is.numeric(dx[, v])) {
      cols = c(cols, v)
    }
  }
  return(cols)
}
comoEncode <- function(dataset){
  # count value types in como_* variables for each ID
    como_names = names(dataset)[grepl("^como_", names(dataset))]

    dataset$num_como_nas = apply(
      dataset[, como_names],
      1,
      function(xx)
        sum(is.na(xx))
      )
    dataset$num_como_Ns = apply(
      dataset[, como_names],
      1,
      function(xx)
        sum(xx == 2, na.rm = TRUE)
      )
    dataset$num_como_Ys = apply(
      dataset[, como_names],
      1,
      function(xx)
        sum(xx == 1, na.rm = TRUE)
      )
    dataset$num_como_Us = apply(
      dataset[, como_names],
      1,
      function(xx)
        sum(xx == 9, na.rm = TRUE)
      )
    return(dataset)
}
prepareDataSet <- function(con,
                         subsets = "0, 1",
                          tablename = "patients_medevid_waitlist",
                         table_preesrd = "preesrdfeatures",
                         medex_tblname = "medxpreesrd") {
  
  qry = str_glue(
                  "SELECT *
                  FROM {tablename} 
                  WHERE subset IN ({subsets})"
                )
  data_subset = dbGetQuery(con, qry)
  
  #set out of bounds lab variables to NA 
  labvars=c("height","weight","bmi","sercr","album","gfr_epi","heglb")
  ve=valueExceptions(data_subset,labvars)
  df=data_subset %>% 
    left_join(
      ve,
      by="usrds_id")
  df=setOutOfBoundsToNA(df,labvars)
  
  #select the columns to keep
  oobvars = setdiff(names(df),names(data_subset))
  categoryVars = getCategoryVars(df)
  continuousVars = getContinuousVars(df)
  df = df[, c("usrds_id",
              "subset",
              "comorbid",
              "inc_age",
              "race",
              "sex",
              "disgrpc",
              "waitlist_status",
              "days_on_waitlist",
              "died_in_90",
              oobvars,
              categoryVars,
              continuousVars)]
  
  nonNumCols = setdiff(getNonNumericCols(df), c("pdis", "comorbid", "cdtype","hispanic","waitlist_status"))
  df = replaceCharacterVals(df, nonNumCols)
  df = recodePdis(df, con)
  df = comoEncode(df)

  print("delete unused vars")
#   #########varsToDelete per discussion of Nov 30 2020#####
  varsToDelete = c(
    "albumlm",
    "como_ihd",
    "como_mi",
    "como_cararr",
    "como_dysrhyt",
    "como_pericar",
    "como_diabprim",
    "como_hiv",
    "como_aids",
    "comorbid_count",
    "comorbid_mortality",
    "comorbid_se",
    "comorbid",
    "ethn",
    "hba1c",
    "incyear",
    "masked_died",
    "masked_tx1fail",
    "masked_txactdt",
    "masked_txlstdt",
    "masked_txinitdt",
    "masked_remdate",
    "masked_unossdt",
    "masked_mefdate",
    "masked_ctdate",
    "masked_tdate",
    "masked_patsign",
    "masked_trstdat",
    "masked_trnend",
    "pdis_count",
    "pdis_mortality",
    "pdis_se",
    "pdis",
    "recnum",
    "tottx"
  )
######
  df[, varsToDelete] = NULL

  print("get subset of preesrdfeatures")
  qry = str_glue(
        "SELECT *
        FROM {table_preesrd} 
        WHERE subset in ({subsets})"
        )
  preesrd = dbGetQuery(con, qry)

  print("join main with preesrdfeatures")

  full_data = df %>%
    left_join(
      preesrd,
      by = c("usrds_id","subset")
      )
  return(full_data)
}

save_data <- function(con, medex_tblname, data, appendFlag){
  if (appendFlag == FALSE) {
    drop_table_function(con, medex_tblname)
  }
  dbWriteTable(
    con,
    medex_tblname,
    data,
    append = appendFlag,
    row.names = FALSE
                      )
}
# Execute function--------------------------------------------------------
# create a full data set for each of the 10 partitions and save in one table
df = prepareDataSet(con, 
                     subsets = "0,1", 
                     tablename = "patients_medevid_waitlist",
                     table_preesrd = "preesrdfeatures"
                     )
save_data(
  con, 
  medex_tblname = "medxpreesrd",
  df, 
  appendFlag = FALSE
  )

#run for the rest of the subsets
sets = c(
  "2,3",
  "4,5",
  "6,7",
  "8,9"
)
rm(df)

for (s in sets) { 
  print(s)
  df = prepareDataSet(
    con, 
    subsets = s, 
    tablename = "patients_medevid_waitlist",
    table_preesrd = "preesrdfeatures",
    medex_tblname = "medxpreesrd")
  
  save_data(
    con, 
    medex_tblname = "medxpreesrd",
    df, 
    appendFlag = TRUE
    )
  rm(df)
}