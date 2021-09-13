library(readr)
library(stringr)
library(sqldf)
library(tidyr)
library(dplyr)

#' Maps each pdgns_cd in the pre-esrd data to one of 12 aggregated diagnosis groupings, 
#' and stores the mapping in a table icd9_ccs_codes.R, icd10_ccs_codes.R (for CCS groupings); 
#' icd9_dx_2014.txt, icd10_dx_codes.txt (for the icd9 and ics10 pdgsn_cd's);
#' 
#' Input: ucsf_dx_mappings.csv (for UCSF-advised categorizations of diagnosis codes)
#' Output: dxmap Maps pdgns_cd to one of 12 diagnosis-code groupings. 
#' Two sources of input are used for the groupings: CCS (Clinical Classification System); 
#' and UCSF physician expertise
#' 
source('CreateDataSet/S0-connectToPostgres.R')

source_dir = file.path(".","CreateDataSet")

#read in lists of codes for mapping steps
source(file.path(source_dir, "icd9_ccs_codes.R"))
source(file.path(source_dir, "icd10_ccs_codes.R"))

read_icd9 <- function(directory, filename) {
  #READ IN ICD9 SOURCE DATA
  lines = readLines(file.path(directory,filename))
  lines =
    iconv(lines[2:length(lines)],
          from = "latin1",
          to = "ASCII",
          sub = ""
          )  
  
  #Convert utf-8 to ASCII and remove special characters like umlauts and accents
  pdgns_cd = substr(lines, 1, 6) %>% 
              trimws() %>% 
              str_pad(.,
                      width = 7,
                      side = "right",
                      pad = "0"
                      )
  description = substr(lines, 7, 130)
  
  df9 = as.data.frame(cbind(pdgns_cd, description))
  df9$cdtype = "I"
  return(df9)
}
read_icd10 <- function(directory, filename){
  lines = readLines(file.path(directory, filename))
  lines <-
    iconv(lines[2:length(lines)],
          from = "latin1",
          to = "ASCII",
          sub = ""
          )  
  pdgns_cd = substr(lines, 1, 7) %>%
              trimws() %>% 
              str_pad(.,
                      width = 7,
                      side = "right",
                      pad = "0"
                      )
  description = substr(lines, 11, 130)
  df10 = as.data.frame(cbind(pdgns_cd, description), stringsAsFactors = F)
  df10 = df10 %>% filter(pdgns_cd != '0000000')
  #There may be multiple entries with the same pdgns_cd for icd10, so choose one
  df10 = sqldf(
              "
              SELECT pdgns_cd, MAX(description) AS description 
              FROM df10 
              GROUP BY pdgns_cd"
              )
  df10$cdtype = "D"
  return(df10)
}
map_pdgns = function(df9, df10){
  # join icd9 and icd10
  df <- as.data.frame(rbind(df9, df10)) %>% 
    mutate_at(
      vars('cdtype', 'pdgns_cd', 'description'),
      as.character
    )
  df = df %>% 
    mutate(
      dx_neo = as.integer(
        grepl("malignant neoplasm", tolower(df$description)) &
          grepl("family history", tolower(df$description))
      ),
      # dx_poi=as.integer(grepl("poisoning",tolower(df$description))),
      dx_smo = as.integer((
        cdtype == 'D' & pdgns_cd %in% smo_10
      ) |(
        cdtype == 'I' & pdgns_cd %in% smo_9)
      ),
      dx_alc = as.integer((
        cdtype == 'D' & pdgns_cd %in% alc_10
      ) | (
        cdtype == 'I' & pdgns_cd %in% alc_9)
      ),
      dx_drg = as.integer((
        cdtype == 'D' & pdgns_cd %in% drg_10
      ) | (
        cdtype == 'I' & pdgns_cd %in% drg_9)
      ),
      dx_pne = as.integer((
        cdtype == 'D' & pdgns_cd %in% pne_10
      ) | (
        cdtype == 'I' & pdgns_cd %in% pne_9)
      ),
      dx_kid = as.integer((
        cdtype == 'D' & pdgns_cd %in% kid_10
      ) | (
        cdtype == 'I' & pdgns_cd %in% kid_9)
      )
    )
  return(df)
}
getComorbids <- function(directory, filename, df, colname, prefix = 'dx_') {
  ucsf_mappings = read.csv(file.path(directory, filename), stringsAsFactors = FALSE)
  dg = sqldf(
    "SELECT df.*, b.label 
    FROM df  
    LEFT JOIN ucsf_mappings b 
    ON df.pdgns_cd>=b.lb 
    AND df.pdgns_cd<=b.ub",
    method = "raw"
  )
  #df[,colname]=gsub('[ (-/)._aeiou]','',df[,colname]) %>% substr(1,strlength)
  values = unique(dg[, colname]) %>% setdiff(NA)
  for (v in values) {
    dg[, paste0(prefix, v)] = (as.integer(dg[, colname] == v))
    dg[, paste0(prefix, v)] = replace_na(dg[, paste0(prefix, v)], 0)
  }
  dg$label = NULL
  return(dg)
}

# Execute Functions -------------------------------------------------------
df9 = read_icd9(source_dir, "icd9_dx_2014.txt")
df10 = read_icd9(source_dir, "icd10_dx_codes.txt")
mapped9_10 = map_pdgns(df9, df10)
dh = getComorbids(source_dir, "dx_mappings_ucsf.csv", df=mapped9_10, colname = "label")

#save to postgres database as dxmap
drop_table_function(con, "dxmap")
tblname = "dxmap"
dbWriteTable(
  con,
  tblname,
  dh,
  append = FALSE,
  row.names = FALSE
  )