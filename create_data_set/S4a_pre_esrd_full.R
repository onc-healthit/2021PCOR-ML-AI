library(readr)
library(haven)
library(dplyr)
library(magrittr)
library(stringr)

# USRDS data have multiple pre-esrd claims per patient. This script 
# 1) merges the pre-esrd claims tables
# 2) constructs counts of claims grouped by type of claim and diagnosis code
# 3) creates one record per patient, with all pre-esrd summary statistics aggregated for each patient
# - creates binary variables to indicate the presence or absence of pre-esrd claims and each type (ip, hh, hs, op, sn)
# 
# 
# The record includes total number of claims and total length of stay, grouped by 
# 1. type of claim (in-patient,out-patient, home-health, hospice, and skilled nursing) and
# 2. by the aggregated diagnosis grouping.	
# 
# - Input: The postgresql tables `preesrd5y_xx_clm_inc` for xx="ip","op","hh","hs","sn"; the utility script *setfieldtypes.R*	
#   - Output: The postgresql table `preesrdfeatures`

#Updated Nov 18 with changes suggested in code review
#1) Drop the detailed disaggregation of claims by dx group for home-health and hospice
#2) Include the elapsed time from the very first claim to the very last claim (Jarcy)
#3) Include binary variables for each diagnosis grouping (James)

main_data = "patients_medevid_waitlist"
pre_esrd_tblname = "preesrdfeatures"

source(file.path("CreateDataSet","S0-connectToPostgres.R"))
sourcedir = file.path("data")
source(file.path("CreateDataSet", "setfieldtypes.R"))

prepareQuery = function(dxcols, tablename, qryAggType = 1, testMode = 0) {
  
  qry_pt1=paste0("b.", dxcols$column_name, collapse=",")
  
  if (qryAggType == 1) {
    vec1 = paste0("SUM(stay*", dxcols$column_name, ")")
    vec2 = paste0(" AS stay", substr(dxcols$column_name, 3, 6))
    qry_pt5 = paste0(vec1, vec2, collapse = ", ")

  } else if (qryAggType == 2) {
    vec1 = paste0("SUM(", dxcols$column_name, ")")
    vec2 = paste0(" AS clms", substr(dxcols$column_name, 3, 6))
    qry_pt5 = paste0(vec1, vec2, collapse = ", ")

  }  else if (qryAggType == 3) {
    vec1 = paste0("MAX(", dxcols$column_name, ")")
    vec2 = paste0(" AS has", substr(dxcols$column_name, 3, 6))
    qry_pt5 = paste0(vec1, vec2, collapse = ", ")
  }
  
    qry_main = str_glue("WITH w AS (
                                  SELECT a.usrds_id,
                                    a.pdgns_cd, 
                                    a.masked_clm_thru-a.masked_clm_from AS stay,
                                    a.cdtype, 
                                    a.hgb, 
                                    a.hcrit, 
                                    {qry_pt1}
                                   FROM {tablename} a 
                                   LEFT JOIN dxmap b 
                                    ON a.cdtype=b.cdtype 
                                    AND a.pdgns_cd=b.pdgns_cd
                                ) 
                      SELECT usrds_id, {qry_pt5}
                      FROM w
                      GROUP BY usrds_id"
                      )
  return(qry_main)
}
prepareAggQuery = function(clm_type) {
  #Nov 16 2020: Introduce MAX(masked_clm_thru)-MIN(masked_clm_from) as the
  #time range of claims, per comment by Jarcy in Nov 12 code review
  #grouped by ursds_id
  # calculate the number of rows(claims) for each group
  qry_main = str_glue("SELECT usrds_id, 
                        SUM(masked_clm_thru-masked_clm_from) AS stay,
                        MAX(masked_clm_thru)-MIN(masked_clm_from) AS range, 
                        MIN(masked_clm_from) AS earliest_clm,
                        MAX(masked_clm_thru) AS latest_clm, 
                        COUNT(*) AS claims 
                      FROM preesrd5y_{clm_type}_clm_inc
                      GROUP BY usrds_id"
                     )            
  return(qry_main)
}


# Execute function --------------------------------------------------------
dxcols = names(dbGetQuery(
  con, 
  "
  SELECT * 
  FROM dxmap 
  LIMIT 5
  "))

dxcols = dxcols[4:length(dxcols)] %>% as.data.frame()
names(dxcols) = "column_name"
####dep####
ip1 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_ip_clm_inc",
                                 qryAggType = 1,
                                 testMode = 0
                 ))

ip2 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_ip_clm_inc",
                                 qryAggType = 2,
                                 testMode = 0
                 ))

ip3 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_ip_clm_inc",
                                 qryAggType = 3,
                                 testMode = 0
                 ))

op1 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_op_clm_inc",
                                 qryAggType = 1,
                                 testMode = 0
                 ))

op2 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_op_clm_inc",
                                 qryAggType = 2,
                                 testMode = 0
                 ))

op3 = dbGetQuery(con,prepareQuery(
                                 dxcols,
                                 "preesrd5y_op_clm_inc",
                                 qryAggType = 3,
                                 testMode = 0
                 ))

sn1 = dbGetQuery(con, prepareQuery(
                                   dxcols,
                                   "preesrd5y_sn_clm_inc",
                                   qryAggType = 1,
                                   testMode = 0
                 ))

sn2 = dbGetQuery(con, prepareQuery(
                                   dxcols,
                                   "preesrd5y_sn_clm_inc",
                                   qryAggType = 2,
                                   testMode = 0
                 ))

sn3 = dbGetQuery(con, prepareQuery(
                                   dxcols,
                                   "preesrd5y_sn_clm_inc",
                                   qryAggType = 3,
                                   testMode = 0
                 ))
#####AGGS#####
hha = dbGetQuery(con, prepareAggQuery("hh"))
ipa = dbGetQuery(con, prepareAggQuery("ip"))
opa = dbGetQuery(con, prepareAggQuery("op"))
sna = dbGetQuery(con, prepareAggQuery("sn"))
hsa = dbGetQuery(con, prepareAggQuery("hs"))


countNulls = function(listnames) {
  df = NULL
  for (n in listnames) {
    x = get(n)
    x = x[, 2:dim(x)[2]] #Omit the USRDS_ID
    totalpatients = dim(x)[1] #total patients
    nullpatients = totalpatients - sum(rowSums(x > 0, na.rm = TRUE)) #total patients having null or zero
    df = rbind(df, t(c(n, totalpatients, nullpatients))) %>% 
      as.data.frame(stringsAsFactors = FALSE)
  }
  names(df) = c("listname", "totalpatients", "nullpatients")
  return(df)
}
###dep####
names(ip1)[2:length(names(ip1))] = paste0(names(ip1)[2:length(names(ip1))], "_ip")
names(ip2)[2:length(names(ip2))] = paste0(names(ip2)[2:length(names(ip2))], "_ip")
names(ip3)[2:length(names(ip3))] = paste0(names(ip3)[2:length(names(ip3))], "_ip")
names(op1)[2:length(names(op1))] = paste0(names(op1)[2:length(names(op1))], "_op")
names(op2)[2:length(names(op2))] = paste0(names(op2)[2:length(names(op2))], "_op")
names(op3)[2:length(names(op3))] = paste0(names(op3)[2:length(names(op3))], "_op")
names(sn1)[2:length(names(sn1))] = paste0(names(sn1)[2:length(names(sn1))], "_sn")
names(sn2)[2:length(names(sn2))] = paste0(names(sn2)[2:length(names(sn2))], "_sn")
names(sn3)[2:length(names(sn3))] = paste0(names(sn3)[2:length(names(sn3))], "_sn")
names(hha)[2:length(names(hha))] = paste0(names(hha)[2:length(names(hha))], "_hh")
names(hsa)[2:length(names(hsa))] = paste0(names(hsa)[2:length(names(hsa))], "_hs")
names(ipa)[2:length(names(ipa))] = paste0(names(ipa)[2:length(names(ipa))], "_ip")
names(opa)[2:length(names(opa))] = paste0(names(opa)[2:length(names(opa))], "_op")
names(sna)[2:length(names(sna))] = paste0(names(sna)[2:length(names(sna))], "_sn")


#dbGetQuery(con,"select distinct table_schema, table_name from information_schema.tables where table_schema like 'public'")
dfnames = c(
  "ip1",
  "ip2",
  "ip3",
  "op1",
  "op2",
  "op3",
  "sn1",
  "sn2",
  "sn3",
  "hha",
  "hsa",
  "ipa",
  "opa",
  "sna"
)
for (s in dfnames) {
  tblname = str_glue("temp_{s}")
  drop_table_function(con, tblname)
  dbWriteTable(
              con,
              tblname,
              get(s),
              temporary = TRUE)
}

#If you write "select a.usrds_id, ip1.*, ip2.* from patients a left join temp_ip1 as ip1, temp_ip2 as ip2... etc."
#then postgres returns an error because you are selecting usrds_id more than once.
#This has to be addressed in postgres by replacing "ip1.*", "ip2.*" with an explicit
#list of names *other than usrds_id"
#The following code creates these lists of names
#Note that the problem is easily addressed in dplyr's "left_join", but we need to worry about memory limits in R,
#so we solve the problem by creating the postgres query in code
############# BEGIN############
ip1names = paste0("ip1.", names(ip1)[2:length(names(ip1))], collapse = ", ")
ip2names = paste0("ip2.", names(ip2)[2:length(names(ip2))], collapse = ", ")
ip3names = paste0("ip3.", names(ip3)[2:length(names(ip3))], collapse = ", ")
op1names = paste0("op1.", names(op1)[2:length(names(op1))], collapse = ", ")
op2names = paste0("op2.", names(op2)[2:length(names(op2))], collapse = ", ")
op3names = paste0("op3.", names(op3)[2:length(names(op3))], collapse = ", ")
sn1names = paste0("sn1.", names(sn1)[2:length(names(sn1))], collapse = ", ")
sn2names = paste0("sn2.", names(sn2)[2:length(names(sn2))], collapse = ", ")
sn3names = paste0("sn3.", names(sn3)[2:length(names(sn3))], collapse = ", ")
# 
######
hhanames = paste0("hha.", names(hha)[2:length(names(hha))], collapse = ", ")
ipanames = paste0("ipa.", names(ipa)[2:length(names(ipa))], collapse = ", ")
opanames = paste0("opa.", names(opa)[2:length(names(opa))], collapse = ", ")
snanames = paste0("sna.", names(sna)[2:length(names(sna))], collapse = ", ")
hsanames = paste0("hsa.", names(hsa)[2:length(names(hsa))], collapse = ", ")
# ######END##################
ip1str = paste0(ip1names, collapse = ",") %>% paste0(", ")
ip2str = paste0(ip2names, collapse = ",") %>% paste0(", ")
ip3str = paste0(ip3names, collapse = ",") %>% paste0(", ")
op1str = paste0(op1names, collapse = ",") %>% paste0(", ")
op2str = paste0(op2names, collapse = ",") %>% paste0(", ")
op3str = paste0(op3names, collapse = ",") %>% paste0(", ")
sn1str = paste0(sn1names, collapse = ",") %>% paste0(", ")
sn2str = paste0(sn2names, collapse = ",")  %>% paste0(", ")
sn3str = paste0(sn3names, collapse = ",")  %>% paste0(", ")
########agg#########
ipastr = paste0(ipanames, collapse = ",")  %>% paste0(", ")
opastr = paste0(opanames, collapse = ",")  %>% paste0(", ")
snastr = paste0(snanames, collapse = ",")  %>% paste0(", ")
hhastr = paste0(hhanames, collapse = ",")  %>% paste0(", ")
hsastr = paste0(hsanames, collapse = ",")  %>% paste0(" ")

# qry=paste0("create table preesrdfeatures as select a.usrds_id, ",ip1str,ip2str,ip3str,
#            op1str, op2str,op3str, sn1str, sn2str, sn3str, ipastr, opastr,
#            snastr, hhastr, hsastr)

qry = paste0(
  "SELECT a.usrds_id, ",
  ip1str,
  ip2str,
  ip3str,
  op1str,
  op2str,
  op3str,
  sn1str,
  sn2str,
  sn3str,
  ipastr,
  opastr,
  snastr,
  hhastr,
  hsastr
)
qry = str_glue(
  "{qry} FROM {main_data} a
            LEFT JOIN temp_ip1 AS ip1 ON a.usrds_id=ip1.usrds_id
            LEFT JOIN temp_ip2 AS ip2 ON a.usrds_id=ip2.usrds_id
            LEFT JOIN temp_ip3 AS ip3 ON a.usrds_id=ip3.usrds_id
            LEFT JOIN temp_op1 AS op1 ON a.usrds_id=op1.usrds_id
            LEFT JOIN temp_op2 AS op2 ON a.usrds_id=op2.usrds_id
            LEFT JOIN temp_op3 AS op3 ON a.usrds_id=op3.usrds_id
            LEFT JOIN temp_sn1 AS sn1 ON a.usrds_id=sn1.usrds_id
            LEFT JOIN temp_sn2 AS sn2 ON a.usrds_id=sn2.usrds_id
            LEFT JOIN temp_sn3 AS sn3 ON a.usrds_id=sn3.usrds_id
            LEFT JOIN temp_ipa AS ipa ON a.usrds_id=ipa.usrds_id
            LEFT JOIN temp_opa AS opa ON a.usrds_id=opa.usrds_id
            LEFT JOIN temp_sna AS sna ON a.usrds_id=sna.usrds_id
            LEFT JOIN temp_hha AS hha ON a.usrds_id=hha.usrds_id
            LEFT JOIN temp_hsa AS hsa ON a.usrds_id=hsa.usrds_id"
)
df = dbGetQuery(con, qry)

earliest_cols = names(df)[grepl("earliest_clm", names(df))]
latest_cols = names(df)[grepl("latest_clm", names(df))]
for (c in earliest_cols) {
  df[, c] = ifelse(is.na(df[, c]), 500000, df[, c])
}
for (c in latest_cols) {
  df[, c] = ifelse(is.na(df[, c]), -500000, df[, c])
}

earliest_claim_date = apply(df[, earliest_cols], 1, "min")
latest_claim_date = apply(df[, latest_cols], 1, "max")
df$claims_range = latest_claim_date - earliest_claim_date

cols_to_delete = union(earliest_cols, latest_cols)
df[, cols_to_delete] = NULL

#Out of the individual columns named "has_dx_claimtype" (e.g., "has_neo_ip")
#create a single column "has_dx"
has_cols = names(df)[grepl("has_", names(df))]
dxs = unique(
  substr(
    has_cols, 5, 7)) #list of diagnosis groupings

mymax = function(x) {
  #create a binary result to yield 1 if the patients has any present, 0 if not, na if all are nans
  #Example 1: has_dia_ip=NA, has_dia_op=0, has_dia_sn=1. So x=c(NA,0,1)
  #Then returns 1
  #Example 2: x=c(NA,NA,NA). Then returns NA
  #Example 3: x=c(NA,0,NA). Then returns 0
  p_sum = sum(x > 0, na.rm = T) #number of positive elements
  z_sum = sum(x == 0, na.rm = T) #number of zero elements
  return(ifelse(p_sum > 0, 1, ifelse(z_sum > 0, 0, NA)))
}
 # use this so we end up with NA if a vector is all NA
safe.max = function(invector) {
  na.pct = sum(is.na(invector))/length(invector)
  if (na.pct == 1) {
    return(NA) }
  else {
    return(max(invector,na.rm=TRUE))
  }
}

for (c in dxs) {
  hasdxcols = has_cols[grepl(c, has_cols)]
  df[,paste0("has_",c)]=apply(
    df[,hasdxcols],
    1,
    function(x) safe.max(as.numeric(x))
    )
}

hasvars = names(df)[grepl("has_", names(df))]
hasvarsettings = hasvars[grepl("_ip$|_op$|_sn$|_hh$|_hs$", hasvars)]
df[, hasvarsettings] = NULL #remove variables like "has_neo_ip", keeping in "has_neo"
df$claims_range = ifelse(df$claims_range < 0, NA, df$claims_range)

#Per discussion of 11-30-2020, add binary for each type
df$prior_hh_care = as.integer(df$claims_hh > 0 &
                                !is.na(df$claims_hh))
df$prior_hs_care = as.integer(df$claims_hs > 0 &
                                !is.na(df$claims_hs))
df$prior_ip_care = as.integer(df$claims_ip > 0 &
                                !is.na(df$claims_ip))
df$prior_op_care = as.integer(df$claims_op > 0 &
                                !is.na(df$claims_op))
df$prior_sn_care = as.integer(df$claims_sn > 0 &
                                !is.na(df$claims_sn))
priorvars = names(df)[grepl("prior_", names(df))]

df$has_preesrd_claim = apply(
  df[, priorvars], 
  1, 
  function(x) safe.max(as.numeric(x))
)
#Per request by Ken Wilkins (Dec 17 2020) to include binary
#variable for existence of preesrd claims
# these are also used in the parametric models instead of claim counts

drop_table_function(con, pre_esrd_tblname)
dbWriteTable(
  con,
  pre_esrd_tblname,
  df,
  field.types = myfieldtypes,
  append = FALSE,
  row.names = FALSE
)