library(readr)
library(plyr)
library(dplyr)
library(tidyr)
library(sqldf)
library(RPostgres)
library(DBI)
library(stringr)

#' Creates a postgres table pdis_recode_map, which is used in S6-PrepareDataSet.R, 
#' for assigning pdis to a numeric value called pdis_recode.
#' 
#' Input: The pdis column from medevid table
#' Output: pdis_recode_map
#' 
source(file.path("CreateDataSet","S0-connectToPostgres.R"))
source_dir = file.path("CreateDataSet")

df1 = dbGetQuery(con,
                 "SELECT * 
                  FROM patients_medevid_waitlist")

#We must know whether the pdis is ICD9 or ICD10, 
#exclude where cdtype is unknown. 
#There are 20,003 patients where cdtype is unknown

pdis_occurrences = dbGetQuery(con,
  "SELECT cdtype, pdis, COUNT(*) AS nmbr 
    FROM patients_medevid_waitlist
    WHERE cdtype IS NOT NULL
    GROUP BY pdis, cdtype"
)


if (sum(is.na(pdis_occurrences$cdtype))!=0){
  print("not all null cdtypes excluded")
}

#Standardize the format so that we can match with another pdis file
pdis_occurrences$pdis = pdis_occurrences$pdis %>% 
                            trimws() %>% 
                            str_pad(.,
                                    width = 7,
                                    side = "right",
                                    pad = "0"
                                    )

map_icd_9_to_10 = read.table(file = file.path(source_dir, "2017_I9gem_map.txt"), 
                             header = TRUE) %>% 
                             select(icd9, icd10)


map_icd_9_to_10 = map_icd_9_to_10 %>% 
  mutate(icd9 = icd9 %>% 
                trimws() %>% 
                str_pad(.,
                        width = 7,
                        side = "right",
                        pad = "0"
                        ),
          icd10 = icd10 %>% 
                  trimws() %>% 
                  str_pad(.,
                          width = 7,
                          side = "right",
                          pad = "0"
                        )
)

#icd-10
#The character-level pdis_recode is same as pdis when cdtype equals "D"
pdis_occurrences_D = pdis_occurrences %>%
  filter(cdtype == "D") %>%
  mutate(pdis_recode_char = pdis)

# use the crosswalk to map the icd9 codes to icd10
pdis_occurrences_I = sqldf(
  "SELECT a.*, b.icd10 AS pdis_recode_char 
   FROM pdis_occurrences a 
   LEFT JOIN map_icd_9_to_10 b 
     ON a.pdis=b.icd9 
     WHERE a.cdtype='I'",
  method = "raw"
)

pdis_recode_map = union(pdis_occurrences_D, pdis_occurrences_I)
pdis_recode_map = pdis_recode_map %>% 
  mutate(pdis_recode = as.factor(pdis_recode_char) %>% as.numeric())

#gets sum of numbr for each recode value when recode isn't na
pdis_recode_agg = pdis_recode_map %>% 
  group_by(pdis_recode) %>% 
  dplyr::summarise(pdis_recode_nmbr = sum(nmbr)) %>%
  as.data.frame()

pdis_recode_map = pdis_recode_map %>% left_join(pdis_recode_agg, by = "pdis_recode")
# pdis_recode_map=pdis_recode_map %>% filter(pdis_recode_nmbr>=100)

tblname = "pdis_recode_map"
drop_table_function(con, tblname)
dbWriteTable(con,
             tblname,
             pdis_recode_map,
             append = FALSE,
             row.names = FALSE)