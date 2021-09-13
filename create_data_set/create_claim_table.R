#Functions used in S3a_esrd_claims.R to create the pre-esrd claims tables. 
#The schema for the tables changes from year to year. For example, there is no 
#cdtype field prior to 2014, since all diagnosis codes were ICD9 prior to 2014.
#The script handles these year-to-year changes in schema.

create_claim_table <- function(
  data_dir, 
  con, 
  filenames, 
  fieldnames, 
  column_type,
  column_type_2015,
  table_name_pt) {
  # send information to insert each year of claims data into the same postgres table
  
  fieldnames = tolower(fieldnames)
  for (filename in filenames) {
    incident_year =
      substr(filename, str_length(filename) - 3, str_length(filename))
    
    if (incident_year < 2015) {
      # claims prior to 2015 are all icd9, so we set cdtype to I for those years
      csvfile = read_csv(file.path(data_dir, str_glue("{filename}.csv")), col_types = column_type_2015)
      csvfile = csvfile %>%  
        mutate(cdtype =  "I")
    }
    else {
      csvfile = read_csv(file.path(data_dir, str_glue("{filename}.csv")), col_types = column_type)
    }
    
    tblname = str_remove(filename, incident_year)
    names(csvfile) = tolower(names(csvfile))
    fields = names(csvfile)
    
    patients = dbGetQuery(
      con,
      str_glue(
        "SELECT usrds_id
            FROM {table_name_pt}")
    )
    
    df = patients %>%
      inner_join(
        csvfile, 
        by = "usrds_id") %>%
      mutate(
        incident_year = incident_year)
    
    df$pdgns_cd = df$pdgns_cd %>%
          trimws() %>%
          str_pad(.,
                  width = 7,
                  side = "right",
                  pad = "0")
    
    if (grepl('_ip_', tblname)){
      df = createIP_CLM(df, incident_year)
    } 
    else {
      df <- df %>%
        filter(!is.na(masked_clm_from) & (masked_clm_from != ""))
  }
    
    rm(csvfile)
    
    # Append every set, except '2012' which will be the first table to import. 
    # this is b/c 2012 has the format that we want to use to create the table 
    # and append the other years since the format changes between 2011 and 2012-2017
    
    if (incident_year==2012){
      drop_table_function(con, tblname)
      print(str_glue("creating {tblname} claims using {incident_year}={nrow(df)}
                      patients={nrow(df %>% distinct(usrds_id, keep_all=FALSE))}"))
      
      dbWriteTable(
        con, 
        tblname,
        df[, fieldnames], 
        append = FALSE, 
        row.names = FALSE)
    } 
    else {
      print(str_glue("adding {incident_year} to {tblname}={nrow(df)}
                     patients={nrow(df %>% distinct(usrds_id, keep_all=FALSE))}"))
      dbWriteTable(
        con, 
        tblname,
        df[, fieldnames],
        append = TRUE, 
        row.names = FALSE)
    }
  }
}

createIP_CLM = function(df, incident_year) {
  # filtering for table named "preesrd5y_ip_clm"
  print(str_glue("filtering IP claims {incident_year}"))
  
  df = df %>%
    filter(
      !is.na(masked_clm_from) &
      (masked_clm_from != "") &
      !is.na(drg_cd) & 
      (drg_cd != "")
      ) 
  
  return(df)
}